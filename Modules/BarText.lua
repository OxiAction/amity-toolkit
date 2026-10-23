--[[
	Amity module: Bar Text (formerly the AlwaysBarText addon)
	==========================================================
	Permanently shows the health / resource text on the player frame, the
	target frame and the target-of-target frame, formatted as

		100/200 50%

	(current / maximum and percent) for both health and the unit's resource.

	Design notes (important for WoW Forever / the 12.x engine)
	----------------------------------------------------------
	* Health and power values are SECRET for addon code: UnitHealth() always
	  returns a secret number, and tainted code may not compare it or do math
	  with it. Blizzard's own (untainted) code can.
	* Writing ANY field into a Blizzard frame table (e.g. bar.forceShow = true)
	  taints Blizzard's code paths that read it, which then blow up on the
	  secret values. So this addon never writes into Blizzard's frame tables.
	* We draw our own font strings on separate overlay frames and feed the
	  secret values straight into FontString:SetFormattedText, which is
	  explicitly allowed for tainted callers. The percent comes from
	  UnitHealthPercent / UnitPowerPercent with a 0-100 curve, which is the
	  sanctioned way to get a displayable percentage out of a secret value.
	* Blizzard's own status text cannot produce "cur/max pct%" (its "Both"
	  option draws "50%" left and "100" right). While our format is on we turn
	  the "statusText" CVar off and set the alpha of Blizzard's text strings to
	  0 so the mouse-over text does not overlap ours. SetAlpha is a plain
	  widget method and does not taint anything.
	* With "/abt percent off" everything falls back to the previous behaviour:
	  Blizzard's CVar-driven text on player / target, and our target-of-target
	  text mirrors the Options > Interface > Status Text format.
]]

local _, Amity = ...

local defaults = {
	main     = true,   -- player / target bar text
	percent  = true,   -- "cur/max pct%" format drawn by us (false = Blizzard's CVar format)
	mainSize = 0,      -- font size for the player / target text; 0 = template default
	tot      = true,   -- target-of-target health + resource text
	totSize  = 9,      -- font size for the target-of-target text (bars are tiny)
	totMax   = true,   -- include the max value on the target-of-target; false = "cur pct%"
}

local M = Amity:RegisterModule("bartext", {
	title    = "Bar Text",
	notes    = "Always shows health / resource text as \"100/200 50%\" on player, target and target-of-target.",
	defaults = defaults,
	slash    = { "/abt", "/alwaysbartext" },
})

local db -- AmityDB.bartext

local function Print(msg) Amity.Print(msg, M.title) end

-------------------------------------------------------------------------------
-- Secret-safe text helpers
-------------------------------------------------------------------------------

local pctCurve -- curve mapping [0,1] -> [0,100]

local function GetPctCurve()
	if pctCurve then return pctCurve end
	if CurveConstants and CurveConstants.ScaleTo100 then
		pctCurve = CurveConstants.ScaleTo100
	elseif C_CurveUtil and C_CurveUtil.CreateCurve then
		local ok, curve = pcall(function()
			local c = C_CurveUtil.CreateCurve()
			if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
			c:AddPoint(0, 0)
			c:AddPoint(1, 100)
			return c
		end)
		if ok then pctCurve = curve end
	end
	return pctCurve
end

-- All of these take possibly-secret numbers and only ever hand them to
-- SetFormattedText, which accepts secrets. Every call is guarded so a client
-- rule change can never produce a Lua error popup; we just show nothing.
local function SetNumeric(fs, cur, max, showMax)
	local ok
	if showMax then
		ok = pcall(fs.SetFormattedText, fs, "%d / %d", cur, max)
	else
		ok = pcall(fs.SetFormattedText, fs, "%d", cur)
	end
	if not ok then fs:SetText("") end
	fs:SetShown(ok)
end

local function SetPercent(fs, pct)
	local ok = pct ~= nil and pcall(fs.SetFormattedText, fs, "%d%%", pct)
	if not ok then fs:SetText("") end
	fs:SetShown(ok)
end

-- "100/200 50%" (or "100 50%" without the max). Falls back to the plain
-- numbers when no percent is available.
local function SetFull(fs, cur, max, pct, showMax)
	local ok = false
	if pct ~= nil then
		if showMax then
			ok = pcall(fs.SetFormattedText, fs, "%d/%d %d%%", cur, max, pct)
		else
			ok = pcall(fs.SetFormattedText, fs, "%d %d%%", cur, pct)
		end
	end
	if ok then
		fs:Show()
	else
		SetNumeric(fs, cur, max, showMax)
	end
end

local function IsZero(v)
	local ok, zero = pcall(function() return v == 0 end)
	return ok and zero
end

local function GetHealthPercent(unit, curve)
	if UnitHealthPercent and curve then
		local ok, v = pcall(UnitHealthPercent, unit, true, curve)
		if ok then return v end
	end
end

local function GetPowerPercent(unit, curve)
	if UnitPowerPercent and curve then
		local ok, v = pcall(UnitPowerPercent, unit, nil, false, curve)
		if ok then return v end
	end
end

-------------------------------------------------------------------------------
-- Overlay widgets (one set per unit frame: player, target, target-of-target)
-------------------------------------------------------------------------------

local UPDATE_INTERVAL = 0.2

local function CreateText(parent, bar, point, x, justify)
	local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", "TextStatusBarText")
	if not ok or not fs then
		fs = parent:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	end
	fs:SetPoint(point, bar, point, x, 0)
	fs:SetJustifyH(justify)
	fs:Hide()
	-- remember the template size so "size 0" can restore it (our own object,
	-- so storing a field here is taint-free)
	local _, defaultSize = fs:GetFont()
	fs.abtDefaultSize = defaultSize
	return fs
end

local function ApplyFontSize(fs, size)
	local font, curSize, flags = fs:GetFont()
	if not font then return end
	if not size or size <= 0 then
		size = fs.abtDefaultSize -- back to the template default
	end
	if size and size > 0 and size ~= curSize then
		fs:SetFont(font, size, flags)
	end
end

local function HideSet(w)
	w.text:Hide(); w.left:Hide(); w.right:Hide()
end

-- mode: "FULL" (our cur/max pct% format) or a statusTextDisplay CVar value
local function UpdateSet(w, cur, max, pct, mode, showMax)
	if mode == "FULL" then
		w.left:Hide(); w.right:Hide()
		SetFull(w.text, cur, max, pct, showMax)
	elseif mode == "PERCENT" then
		w.left:Hide(); w.right:Hide()
		SetPercent(w.text, pct)
	elseif mode == "BOTH" then
		w.text:Hide()
		SetPercent(w.left, pct)
		SetNumeric(w.right, cur, max, false)
	else -- NUMERIC / NONE / anything else
		w.left:Hide(); w.right:Hide()
		SetNumeric(w.text, cur, max, showMax)
	end
end

--[[
	A "unit set" is:
	{
		key       = "player" | "target" | "tot",
		getUnit   = function() -> unit token,
		overlay   = our frame,
		health    = { text, left, right },
		mana      = { text, left, right },
		blizzText = { Blizzard font strings we fade out while our format is on },
	}
]]
local unitSets = {}

local function UpdateUnitSet(set)
	local unit = set.getUnit()
	if not unit or not UnitExists(unit) then
		HideSet(set.health); HideSet(set.mana)
		return
	end

	-- Dead units: step aside for the frame's own "DEAD" label.
	local okDead, dead = pcall(function() return UnitIsDeadOrGhost(unit) == true end)
	if okDead and dead then
		HideSet(set.health); HideSet(set.mana)
		return
	end

	local mode
	if db.percent then
		mode = "FULL"
	else
		mode = GetCVar("statusTextDisplay") or "NUMERIC"
	end
	local showMax = (set.key ~= "tot") or db.totMax
	local curve = GetPctCurve()

	-- Health
	local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
	UpdateSet(set.health, hp, hpMax, GetHealthPercent(unit, curve), mode, showMax)

	-- Power (whatever the unit's displayed power is)
	local pw, pwMax = UnitPower(unit), UnitPowerMax(unit)
	if IsZero(pwMax) then
		HideSet(set.mana)
	else
		UpdateSet(set.mana, pw, pwMax, GetPowerPercent(unit, curve), mode, showMax)
	end
end

local function CollectBlizzardTexts(list, bar)
	for _, k in ipairs({ "TextString", "LeftText", "RightText" }) do
		local fs = bar[k]
		if fs and fs.SetAlpha then list[#list + 1] = fs end
	end
end

local function CreateUnitSet(key, parentFrame, healthBar, manaBar, getUnit)
	local overlay = CreateFrame("Frame", "AmityBarTextOverlay_" .. key, parentFrame)
	overlay:SetAllPoints(parentFrame)
	overlay:SetFrameLevel(math.max(healthBar:GetFrameLevel(), manaBar:GetFrameLevel()) + 5)

	local set = {
		key     = key,
		getUnit = getUnit,
		overlay = overlay,
		health  = {
			text  = CreateText(overlay, healthBar, "CENTER", 0, "CENTER"),
			left  = CreateText(overlay, healthBar, "LEFT",   2, "LEFT"),
			right = CreateText(overlay, healthBar, "RIGHT", -2, "RIGHT"),
		},
		mana = {
			text  = CreateText(overlay, manaBar, "CENTER", 0, "CENTER"),
			left  = CreateText(overlay, manaBar, "LEFT",   2, "LEFT"),
			right = CreateText(overlay, manaBar, "RIGHT", -2, "RIGHT"),
		},
		blizzText = {},
	}
	CollectBlizzardTexts(set.blizzText, healthBar)
	CollectBlizzardTexts(set.blizzText, manaBar)

	overlay:SetScript("OnShow", function() UpdateUnitSet(set) end)
	overlay:Hide()
	unitSets[key] = set
	return set
end

local function SetFontSizes(set, size)
	for _, w in ipairs({ set.health, set.mana }) do
		ApplyFontSize(w.text,  size)
		ApplyFontSize(w.left,  size)
		ApplyFontSize(w.right, size)
	end
end

local function SetBlizzardTextAlpha(set, alpha)
	for _, fs in ipairs(set.blizzText) do
		pcall(fs.SetAlpha, fs, alpha)
	end
end

-------------------------------------------------------------------------------
-- Player / Target
-------------------------------------------------------------------------------

local function GetBars(frame)
	if not frame then return end
	local healthBar = frame.healthbar or frame.HealthBar
	local manaBar   = frame.manabar   or frame.ManaBar
	if not healthBar or not manaBar then return end
	return healthBar, manaBar
end

local function SetupMain()
	if not unitSets.player then
		local h, m = GetBars(PlayerFrame)
		if h then
			CreateUnitSet("player", PlayerFrame, h, m, function()
				return PlayerFrame.unit or "player"
			end)
		end
	end
	if not unitSets.target then
		local h, m = GetBars(TargetFrame)
		if h then
			CreateUnitSet("target", TargetFrame, h, m, function()
				return TargetFrame.unit or "target"
			end)
		end
	end
end

local function ApplyMain()
	SetupMain()
	local useOwn = db.main and db.percent

	for _, key in ipairs({ "player", "target" }) do
		local set = unitSets[key]
		if set then
			SetBlizzardTextAlpha(set, useOwn and 0 or 1)
			SetFontSizes(set, db.mainSize)
			if useOwn then
				set.overlay:Show()
				UpdateUnitSet(set)
			else
				set.overlay:Hide()
			end
		end
	end

	if not db.main then
		return
	end

	if useOwn then
		-- Our text replaces Blizzard's; no need for the always-on CVar.
		if GetCVar("statusText") ~= "0" then
			SetCVar("statusText", "0")
		end
	else
		-- Blizzard's own "always show status text": statusText = "1" keeps the
		-- text visible; statusTextDisplay picks the format (NUMERIC / PERCENT /
		-- BOTH). "NONE" shows numbers anyway, but set it to NUMERIC so the
		-- options panel reflects what is on screen.
		if GetCVar("statusText") ~= "1" then
			SetCVar("statusText", "1")
		end
		if GetCVar("statusTextDisplay") == "NONE" then
			SetCVar("statusTextDisplay", "NUMERIC")
		end
	end
end

local function DisableMain()
	SetCVar("statusText", "0")
end

-------------------------------------------------------------------------------
-- Target of target
-------------------------------------------------------------------------------

local function GetToTFrame()
	return (TargetFrame and TargetFrame.totFrame) or TargetFrameToT
end

local function SetupToT()
	if unitSets.tot then return true end
	local tot = GetToTFrame()
	if not tot then return false end
	local h, m = GetBars(tot)
	if not h then return false end

	local set = CreateUnitSet("tot", tot, h, m, function() return "targettarget" end)

	-- The ToT frame itself is refreshed by Blizzard on a timer (unit events do
	-- not fire for "targettarget"), so we poll the same way, throttled.
	local elapsedTotal = 0
	set.overlay:SetScript("OnUpdate", function(self, elapsed)
		elapsedTotal = elapsedTotal + elapsed
		if elapsedTotal < UPDATE_INTERVAL then return end
		elapsedTotal = 0
		UpdateUnitSet(set)
	end)
	return true
end

local function ApplyToT()
	if not SetupToT() then return end
	local set = unitSets.tot
	SetFontSizes(set, db.totSize)
	if db.tot then
		set.overlay:Show()
		UpdateUnitSet(set)
	else
		set.overlay:Hide()
	end
end

-------------------------------------------------------------------------------
-- Apply everything
-------------------------------------------------------------------------------

local function ApplyAll()
	ApplyMain()
	ApplyToT()
end

local function UpdateShownSets(...)
	for i = 1, select("#", ...) do
		local set = unitSets[select(i, ...)]
		if set and set.overlay:IsShown() then
			UpdateUnitSet(set)
		end
	end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local OnOff, ParseBool = Amity.OnOff, Amity.ParseBool

local function ShowStatus()
	local fmt
	if db.percent then
		fmt = "cur/max pct%"
	else
		fmt = "Blizzard (" .. tostring(GetCVar("statusTextDisplay")) .. ")"
	end
	Print(("player/target %s (size %s), target-of-target %s (size %d, max value %s), format: %s"):format(
		OnOff(db.main), db.mainSize > 0 and tostring(db.mainSize) or "default",
		OnOff(db.tot), db.totSize, OnOff(db.totMax), fmt))
end

local function ShowHelp()
	Print("commands:")
	Print("  /abt main on|off        - always show player + target bar text")
	Print("  /abt percent on|off     - '100/200 50%' format (off = Blizzard's Status Text format)")
	Print("  /abt mainsize <0|6-20>  - player + target font size (0 = default)")
	Print("  /abt tot on|off         - target-of-target text")
	Print("  /abt totsize <6-16>     - target-of-target font size")
	Print("  /abt totmax on|off      - target-of-target shows 'cur/max' (on) or 'cur' (off)")
	Print("  /abt reset              - restore defaults")
end

-- slash command word -> settings key (commands arrive lowercased)
local toggleKeys = { main = "main", percent = "percent", tot = "tot", totmax = "totMax" }

function M:Slash(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = msg:match("^(%S+)%s*(.*)$")

	if not cmd or cmd == "" or cmd == "status" then
		ShowStatus()
		return
	elseif cmd == "help" or cmd == "?" then
		ShowHelp()
		return
	elseif cmd == "reset" then
		for k, v in pairs(defaults) do db[k] = v end
		Print("defaults restored.")
	elseif toggleKeys[cmd] then
		local key = toggleKeys[cmd]
		local v = ParseBool(arg)
		if v == nil then
			v = not db[key] -- no argument: toggle
		end
		db[key] = v
		if key == "main" and not v then
			DisableMain()
		end
		Print(cmd .. " " .. OnOff(v))
	elseif cmd == "mainsize" then
		local n = tonumber(arg)
		if not n or (n ~= 0 and (n < 6 or n > 20)) then
			Print("usage: /abt mainsize <0|6-20>  (0 = default)")
			return
		end
		db.mainSize = math.floor(n)
		Print("player/target font size " .. (db.mainSize > 0 and tostring(db.mainSize) or "default"))
	elseif cmd == "totsize" then
		local n = tonumber(arg)
		if not n or n < 6 or n > 16 then
			Print("usage: /abt totsize <6-16>")
			return
		end
		db.totSize = math.floor(n)
		Print("target-of-target font size " .. db.totSize)
	else
		ShowHelp()
		return
	end

	ApplyAll()
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function M:Init(settings)
	db = settings

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	frame:RegisterEvent("CVAR_UPDATE")
	-- Player + target values: these events fire for both tokens.
	for _, ev in ipairs({
		"UNIT_HEALTH", "UNIT_MAXHEALTH",
		"UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	}) do
		pcall(frame.RegisterUnitEvent, frame, ev, "player", "target")
	end

	frame:SetScript("OnEvent", function(self, event, arg1)
		if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
			ApplyAll()
		elseif event == "PLAYER_TARGET_CHANGED" then
			UpdateShownSets("target", "tot")
		elseif event == "CVAR_UPDATE" then
			-- Format follows Options > Interface > Status Text when our format is off.
			if not db.percent and (arg1 == "statusTextDisplay" or arg1 == "STATUS_TEXT_DISPLAY") then
				UpdateShownSets("player", "target", "tot")
			end
		else
			-- unit events
			if arg1 == "target" then
				UpdateShownSets("target")
			elseif arg1 == "player" or arg1 == "vehicle" then
				UpdateShownSets("player")
			end
		end
	end)
end
