--[[
	Amity module: Overpower Alert (formerly the OverpowerAlert addon)
	==================================================================
	Warriors only: shows a movable Overpower icon with a 5 second countdown
	when the target dodges.

	WoW Forever: CombatLogGetCurrentEventInfo is restricted to the secure
	Blizzard environment (ADDON_ACTION_FORBIDDEN for addons), so the module
	tracks Overpower's usability instead: it becomes usable only during the
	window after a dodge.
]]

local _, Amity = ...

local DURATION = 5
local OVERPOWER_ID = 7384 -- Overpower (Rank 1); all ranks share the name/icon
local OVERPOWER_IDS = { [7384] = true, [7887] = true, [11584] = true, [11585] = true }

local M = Amity:RegisterModule("overpower", {
	title    = "Overpower Alert",
	notes    = "Warriors: movable Overpower icon with a 5s countdown when your target dodges.",
	defaults = { sound = true },
	slash    = { "/opa", "/overpoweralert" },
})

local db -- AmityDB.overpower
local f  -- the alert frame, created in Init for warriors only

local function Print(msg) Amity.Print(msg, M.title) end

local function GetOverpowerTexture()
	local tex
	if C_Spell and C_Spell.GetSpellTexture then
		tex = C_Spell.GetSpellTexture(OVERPOWER_ID) or C_Spell.GetSpellTexture("Overpower")
	elseif GetSpellTexture then
		tex = GetSpellTexture(OVERPOWER_ID) or GetSpellTexture("Overpower")
	end
	return tex or "Interface/Icons/Ability_MeleeDamage"
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------

local function ApplyPosition()
	f:ClearAllPoints()
	if db.pos then
		f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
	end
end

local function SetTestMode(on)
	f.unlocked = on
	f:EnableMouse(on)
	f.border:SetShown(on)
	f.label:SetShown(on)
	if on then
		f.expires = nil
		f.icon:SetTexture(GetOverpowerTexture())
		f.text:SetText("5.0")
		f:Show()
		Print("test mode ON - drag the icon, then /opa lock")
	else
		f:Hide()
		Print("test mode OFF, position saved")
	end
end

local function Trigger()
	if f.unlocked or f.expires then return end
	f.expires = GetTime() + DURATION
	f.icon:SetTexture(GetOverpowerTexture())
	f:Show()
	if db.sound then
		PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
	end
end

local function Cancel()
	if f.unlocked then return end
	f.expires = nil
	f:Hide()
end

local function CreateAlertFrame()
	f = CreateFrame("Frame", "AmityOverpowerAlertFrame", UIParent)
	f:SetSize(64, 64)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.pos = { point, relPoint, x, y }
	end)
	f:Hide()

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.text:SetPoint("CENTER")
	f.text:SetTextColor(1, 1, 0)

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", -3, 3)
	f.border:SetPoint("BOTTOMRIGHT", 3, -3)
	f.border:SetColorTexture(0, 1, 0, 0.6)
	f.border:Hide()

	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.label:SetText("Drag to move  |  /opa lock to finish")
	f.label:Hide()

	f:SetScript("OnUpdate", function(self)
		if self.unlocked then return end
		local remaining = (self.expires or 0) - GetTime()
		if remaining <= 0 then Cancel() return end
		self.text:SetFormattedText("%.1f", remaining)
	end)
end

-------------------------------------------------------------------------------
-- Proc tracking
-------------------------------------------------------------------------------

local procActive = false

local function IsOverpower(spellID)
	if OVERPOWER_IDS[spellID] then return true end
	local ok, name = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, spellID)
	return ok and name == "Overpower"
end

local function OverpowerUsable()
	local fn = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
	local ok, usable = pcall(fn, "Overpower")
	return ok and usable == true
end

local function CheckUsable()
	local usable = OverpowerUsable()
	if usable and not procActive then
		procActive = true
		Trigger()
	elseif not usable and procActive then
		procActive = false
		Cancel()
	end
end

local function OnEvent(self, event, arg1, arg2, arg3)
	if event == "SPELL_UPDATE_USABLE" then
		CheckUsable()
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		if IsOverpower(arg1) then Trigger() end
	elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		if IsOverpower(arg1) then Cancel() end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if IsOverpower(arg3) then procActive = false Cancel() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		procActive = false
		Cancel()
	end
end

local function Setup()
	local _, class = UnitClass("player")
	if class ~= "WARRIOR" then return end

	CreateAlertFrame()
	ApplyPosition()
	f:SetScript("OnEvent", OnEvent)
	f:RegisterEvent("SPELL_UPDATE_USABLE")
	f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
	f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
	f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function M:Init(settings)
	db = settings
	-- the player's class is only reliable from PLAYER_LOGIN on
	if IsLoggedIn() then
		Setup()
	else
		local loader = CreateFrame("Frame")
		loader:RegisterEvent("PLAYER_LOGIN")
		loader:SetScript("OnEvent", function(self)
			self:UnregisterEvent("PLAYER_LOGIN")
			Setup()
		end)
	end
end

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

function M:Slash(msg)
	if not f then Print("warriors only.") return end
	local cmd, arg = msg:match("^(%S*)%s*(%S*)$")
	cmd = (cmd or ""):lower()
	if cmd == "unlock" or cmd == "test" or cmd == "" then
		SetTestMode(not f.unlocked)
	elseif cmd == "lock" then
		SetTestMode(false)
	elseif cmd == "proc" then
		f.expires = nil
		Trigger()
	elseif cmd == "reset" then
		db.pos = nil
		ApplyPosition()
		Print("position reset")
	elseif cmd == "sound" then
		arg = (arg or ""):lower()
		if arg == "on" then db.sound = true elseif arg == "off" then db.sound = false end
		Print("sound " .. (db.sound and "on" or "off"))
	else
		Print("/opa test (toggle position mode) | lock | proc (simulate) | reset | sound on|off")
	end
end
