--[[
	Amity module: Overpower Alert
	=============================
	Warriors only: shows a movable Overpower icon with a 5 second countdown
	when the target dodges. The module's Unavailable check makes the core
	skip it entirely on other classes: no frame, no events.

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
	title       = "Overpower Alert - Warrior",
	notes       = "Warriors only: movable Overpower icon with a 5s countdown when your target dodges.",
	description = "Warriors only. When your target dodges, a large Overpower icon appears with a 5 second countdown. "
		.. "It disappears when you use Overpower or leave combat. Unlock the icon to drag it "
		.. "where you want it.",
	defaults    = { sound = "RAID_WARNING" }, -- a SOUNDKIT name, or "NONE"
})

local db -- AmityDB.overpower
local f  -- the alert frame, created in Init (warriors only)

-- Sounds to pick from, by SOUNDKIT name. Only the ones this client has are offered.
local SOUNDS = {
	{ "RAID_WARNING",                 "Raid warning" },
	{ "UI_RAID_BOSS_WHISPER_WARNING", "Boss warning" },
	{ "READY_CHECK",                  "Ready check" },
	{ "PVP_THROUGH_QUEUE",            "Queue ready" },
	{ "ALARM_CLOCK_WARNING_2",        "Alarm clock" },
	{ "ALARM_CLOCK_WARNING_3",        "Alarm bell" },
	{ "UI_BATTLEGROUND_COUNTDOWN_TIMER",    "Countdown tick" },
	{ "UI_BATTLEGROUND_COUNTDOWN_FINISHED", "Countdown end" },
	{ "LFG_ROLE_CHECK",               "Role check" },
}

local function PlayAlertSound()
	local id = SOUNDKIT and SOUNDKIT[db.sound]
	if id then PlaySound(id, "Master") end
end

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

-- Unlocked: the icon stays visible and can be dragged.
local function SetUnlocked(on)
	f.unlocked = on
	f:EnableMouse(on)
	f.border:SetShown(on)
	f.label:SetShown(on)
	if on then
		f.expires = nil
		f.icon:SetTexture(GetOverpowerTexture())
		f.text:SetText("5.0")
		f:Show()
	else
		f:Hide()
	end
	Amity:UpdatePanel()
end

local function Trigger()
	if f.unlocked or f.expires then return end
	f.expires = GetTime() + DURATION
	f.icon:SetTexture(GetOverpowerTexture())
	f:Show()
	PlayAlertSound()
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
	f:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and self.unlocked then SetUnlocked(false) end
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
	f.label:SetText("Drag to move  |  right-click to lock")
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
	-- a sound that is not in the list goes back to the default
	local known = db.sound == "NONE"
	for _, entry in ipairs(SOUNDS) do
		if entry[1] == db.sound then known = true end
	end
	if not known then db.sound = "RAID_WARNING" end
	-- Only called for warriors, at PLAYER_LOGIN (see M:Unavailable).
	Setup()
end

-------------------------------------------------------------------------------
-- Panel options
-------------------------------------------------------------------------------

function M:Unavailable()
	local _, class = UnitClass("player")
	if class ~= "WARRIOR" then return "Warriors only: this character is not a warrior." end
end

M.options = {
	{ type = "select", key = "sound", label = "Sound when the alert appears",
		tooltip = "Picking a sound plays it once so you can hear it.",
		values = (function()
			local values = { { "NONE", "No sound" } }
			for _, entry in ipairs(SOUNDS) do
				if SOUNDKIT and SOUNDKIT[entry[1]] then values[#values + 1] = entry end
			end
			return values
		end)() },
	{ type = "button", label = function() return (f and f.unlocked) and "Lock icon" or "Unlock icon" end,
		tooltip = "Unlocked, the icon stays visible and can be dragged. Right-click it to lock.",
		onClick = function() SetUnlocked(not f.unlocked) end },
	{ type = "button", label = "Test alert",
		tooltip = "Shows the alert as if your target had dodged.",
		disabled = function() return f and f.unlocked end,
		onClick = function() f.expires = nil; Trigger() end },
	{ type = "button", label = "Reset position",
		onClick = function() db.pos = nil; ApplyPosition() end },
}

function M:OnOptionChanged(key)
	if key == "sound" then PlayAlertSound() end -- preview
end
