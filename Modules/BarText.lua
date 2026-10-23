--[[
	Amity module: Bar Text
	======================
	Permanently shows the health / resource text on the player frame, the
	target frame and the target-of-target frame, in one of three formats:

		100/200 50%    current / maximum and percent (default)
		100/200        current / maximum
		50%            percent

	for both health and the unit's resource.

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
	  option draws "50%" left and "100" right), so the module always draws its
	  own text. It turns the "statusText" CVar off and sets the alpha of
	  Blizzard's text strings to 0 so the mouse-over text does not overlap
	  ours. SetAlpha is a plain widget method and does not taint anything.
]]

local _, Amity = ...

local defaults = {
	format   = "full", -- "full" = "cur/max pct%", "numeric" = "cur/max", "percent" = "pct%"
	mainSize = 0,      -- font size for the player / target text; 0 = template default
	tot      = true,   -- target-of-target health + resource text
	totSize  = 9,      -- font size for the target-of-target text (bars are tiny)
}

local M = Amity:RegisterModule("bartext", {
	title       = "Bar Text",
	notes       = "Always shows health / resource text, like \"100/200 50%\", on player, target and target-of-target.",
	description = "Health and resource values stay visible on the player, target and target-of-target frames, "
		.. "without hovering. Pick how they read: \"100/200 50%\" (current / maximum and percent), "
		.. "\"100/200\" or \"50%\".",
	defaults    = defaults,
})

local db -- AmityDB.bartext

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
local function SetNumeric(fs, cur, max)
	local ok = pcall(fs.SetFormattedText, fs, "%d/%d", cur, max)
	if not ok then fs:SetText("") end
	fs:SetShown(ok)
end

local function SetPercent(fs, pct)
	local ok = pct ~= nil and pcall(fs.SetFormattedText, fs, "%d%%", pct)
	if not ok then fs:SetText("") end
	fs:SetShown(ok)
end

-- "100/200 50%". Falls back to the plain numbers when no percent is available.
local function SetFull(fs, cur, max, pct)
	local ok = pct ~= nil and pcall(fs.SetFormattedText, fs, "%d/%d %d%%", cur, max, pct)
	if ok then
		fs:Show()
	else
		SetNumeric(fs, cur, max)
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

-- format: db.format ("full", "numeric" or "percent")
local function UpdateText(fs, cur, max, pct, format)
	if format == "percent" then
		SetPercent(fs, pct)
	elseif format == "numeric" then
		SetNumeric(fs, cur, max)
	else
		SetFull(fs, cur, max, pct)
	end
end

--[[
	A "unit set" is:
	{
		key       = "player" | "target" | "tot",
		getUnit   = function() -> unit token,
		overlay   = our frame,
		health    = font string on the health bar,
		mana      = font string on the resource bar,
		blizzText = { Blizzard font strings we fade out },
	}
]]
local unitSets = {}

local function UpdateUnitSet(set)
	local unit = set.getUnit()
	if not unit or not UnitExists(unit) then
		set.health:Hide(); set.mana:Hide()
		return
	end

	-- Dead units: step aside for the frame's own "DEAD" label.
	local okDead, dead = pcall(function() return UnitIsDeadOrGhost(unit) == true end)
	if okDead and dead then
		set.health:Hide(); set.mana:Hide()
		return
	end

	local curve = GetPctCurve()

	-- Health
	local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
	UpdateText(set.health, hp, hpMax, GetHealthPercent(unit, curve), db.format)

	-- Power (whatever the unit's displayed power is)
	local pw, pwMax = UnitPower(unit), UnitPowerMax(unit)
	if IsZero(pwMax) then
		set.mana:Hide()
	else
		UpdateText(set.mana, pw, pwMax, GetPowerPercent(unit, curve), db.format)
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
		health  = CreateText(overlay, healthBar, "CENTER", 0, "CENTER"),
		mana    = CreateText(overlay, manaBar,   "CENTER", 0, "CENTER"),
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
	ApplyFontSize(set.health, size)
	ApplyFontSize(set.mana, size)
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
	for _, key in ipairs({ "player", "target" }) do
		local set = unitSets[key]
		if set then
			SetBlizzardTextAlpha(set, 0)
			SetFontSizes(set, db.mainSize)
			set.overlay:Show()
			UpdateUnitSet(set)
		end
	end
	-- Our text replaces Blizzard's; no need for the always-on CVar.
	if GetCVar("statusText") ~= "0" then
		SetCVar("statusText", "0")
	end
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
-- Panel options
-------------------------------------------------------------------------------

M.options = {
	{ type = "select", key = "format", label = "Text format",
		values = {
			{ "full",    "100/200 50%  (current/max and percent)" },
			{ "numeric", "100/200  (current/max)" },
			{ "percent", "50%  (percent)" },
		} },
	{ type = "range", key = "mainSize", label = "Player and target font size", min = 6, max = 20, zero = "Default" },
	{ type = "toggle", key = "tot", label = "Target-of-target text" },
	{ type = "range", key = "totSize", label = "Target-of-target font size", min = 6, max = 16 },
	{ type = "button", label = "Restore defaults", onClick = function(self) Amity:ResetModuleSettings(self) end },
}

function M:OnOptionChanged()
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
