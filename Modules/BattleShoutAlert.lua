--[[
	Amity module: Battle Shout Alert
	================================
	Warriors only: a movable, flashing Battle Shout icon that stays up while
	the buff is missing or about to run out (warnBefore seconds, a setting, with
	a countdown above the icon). The look and the unlock / test / reset / sound
	controls follow the Overpower and Revenge alerts (ProcAlerts.lua). The
	Unavailable check makes the core skip it entirely on other classes: no
	frames, no events.

	WoW Forever: in combat aura data can be secret, which tainted code must not
	compare. "Could not read the buffs" is therefore kept apart from "the buff
	is gone" (see ScanBuffs). While the buffs can't be read the module relies on
	the expiry it last saw, or on your own cast, so a shout from another warrior
	that lands in combat is only noticed once the buffs are readable again.
]]

local _, Amity = ...

local SPELL_ID     = 6673 -- Rank 1; all ranks share the name/icon
local SPELL_IDS    = {
	[6673] = true, [5242] = true, [6192] = true, [11549] = true,
	[11550] = true, [11551] = true, [25289] = true, [2048] = true,
}
local FALLBACK_ICON = "Interface/Icons/Ability_Warrior_BattleShout"
local BASE_DURATION = 120 -- seconds, until a real duration has been read
local TEST_DURATION = 5
local FLASH_SPEED   = 2 * math.pi * 2 -- two pulses per second
local CHECK_EVERY   = 1 -- seconds; catches what raises no event (death, taxi, an expiry while unreadable)

local M = Amity:RegisterModule("battleshout", {
	title       = "Battle Shout Alert - Warrior",
	notes       = "Warriors only: movable, flashing icon while Battle Shout is not active.",
	description = "Warriors only. A large flashing Battle Shout icon appears when the buff is about to run out or is "
		.. "missing, and goes away as soon as you have a fresh shout. It is tinted blue while you lack the rage to "
		.. "shout, and stays hidden while you are dead or on a flight path. Unlock the icon to drag it where you "
		.. "want it.",
	defaults    = {
		sound      = "RAID_WARNING", -- a SOUNDKIT name, or "NONE"
		combatOnly = false,
		warnBefore = 30, -- seconds before the buff ends; 0 warns only once it is gone
	},
})

local db -- AmityDB.battleshout
local f  -- the alert frame, created in Init (warriors only)

local spellName = "Battle Shout" -- replaced by the client's localized name in Init
local inCombat = false
local knownExpires -- GetTime() when the buff is expected to end, nil when it is not up
local knownDuration = BASE_DURATION

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

local function IsShout(spellID, name)
	return SPELL_IDS[spellID] == true or name == spellName
end

local function GetSpellIcon()
	local tex
	if C_Spell and C_Spell.GetSpellTexture then
		tex = C_Spell.GetSpellTexture(SPELL_ID)
	elseif GetSpellTexture then
		tex = GetSpellTexture(SPELL_ID)
	end
	return tex or FALLBACK_ICON
end

local function PlayAlertSound()
	local id = SOUNDKIT and SOUNDKIT[db.sound]
	if id then PlaySound(id, "Master") end
end

---------------------------------------------------------------------------
-- Buff tracking
---------------------------------------------------------------------------

-- A buff lookup that may come back empty only because auras are hidden right now.
local function AurasAreHidden()
	if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
	local ok, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
	return ok and not IsSecret(hidden) and hidden == true
end

-- Returns one buff slot as found, spellID, name, duration, expires.
-- found is false past the last buff, nil when the slot can't be read.
local function ReadBuff(index)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
		if not ok or IsSecret(aura) then return nil end
		if not aura then return false end
		return true, aura.spellId, aura.name, aura.duration, aura.expirationTime
	end
	local ok, name, _, _, _, duration, expires, _, _, _, spellID = pcall(UnitBuff, "player", index)
	if not ok or IsSecret(name) then return nil end
	if not name then return false end
	return true, spellID, name, duration, expires
end

-- Returns true and the buff's duration and expiry when it is up, false when it
-- is certainly gone, nil when the buffs can't be read.
local function ScanBuffs()
	local unreadable = AurasAreHidden()
	for i = 1, 40 do
		local found, spellID, name, duration, expires = ReadBuff(i)
		if found == nil then
			unreadable = true
		elseif found == false then
			break
		elseif IsSecret(spellID) or IsSecret(name) then
			unreadable = true
		elseif IsShout(spellID, name) then
			return true, duration, expires
		end
	end
	if unreadable then return nil end
	return false
end

local function Positive(v)
	return v ~= nil and not IsSecret(v) and v > 0
end

-- Seconds of Battle Shout left, 0 when it is gone.
local function BuffTimeLeft()
	local up, duration, expires = ScanBuffs()
	local now = GetTime()
	if up == false then
		knownExpires = nil
		return 0
	end
	if up then
		if Positive(duration) then knownDuration = duration end
		if Positive(expires) then
			knownExpires = expires
		elseif not knownExpires or knownExpires <= now then
			knownExpires = now + knownDuration
		end
	end
	return knownExpires and math.max(knownExpires - now, 0) or 0
end

-- Returns whether to warn, and the seconds of buff left.
local function ShouldWarn()
	if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return false end
	if db.combatOnly and not inCombat then return false end
	local left = BuffTimeLeft()
	return left <= db.warnBefore, left
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

local function UpdateRageTint()
	local fn = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
	local ok, _, noRage = pcall(fn, spellName)
	if ok and noRage == true then
		f.icon:SetVertexColor(0.5, 0.5, 1)
	else
		f.icon:SetVertexColor(1, 1, 1)
	end
end

local function SetWarningText(left)
	if left and left > 0 then
		f.text:SetFormattedText("BATTLE SHOUT %d", math.ceil(left))
	else
		f.text:SetText("NO BATTLE SHOUT")
	end
end

-- left: seconds of buff remaining; nil or 0 means it is gone.
local function ShowWarning(left)
	SetWarningText(left)
	f.icon:SetTexture(GetSpellIcon())
	UpdateRageTint()
	if not f:IsShown() then
		f:Show()
		PlayAlertSound()
	end
end

local function Refresh()
	if not f or f.unlocked then return end
	if f.testUntil then
		if GetTime() < f.testUntil then return end
		f.testUntil = nil
	end
	local warn, left = ShouldWarn()
	if warn then
		ShowWarning(left)
	else
		f:Hide()
	end
end

local function ApplyPosition()
	f:ClearAllPoints()
	if db.pos then
		f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 280) -- above the Revenge icon
	end
end

local function SetFlash(alpha)
	f.glow:SetAlpha(alpha)
	f.rim:SetAlpha(alpha)
	f.icon:SetAlpha(0.45 + 0.55 * alpha)
end

-- Unlocked: the icon stays visible, steady, and can be dragged.
local function SetUnlocked(on)
	f.unlocked = on
	f.testUntil = nil
	f:EnableMouse(on)
	f.border:SetShown(on)
	f.label:SetShown(on)
	if on then
		SetWarningText(nil)
		f.icon:SetTexture(GetSpellIcon())
		f.icon:SetVertexColor(1, 1, 1)
		SetFlash(1)
		f:Show()
	else
		f:Hide()
		Refresh()
	end
	Amity:UpdatePanel()
end

local function TestAlert()
	f.testUntil = GetTime() + TEST_DURATION
	f:Hide() -- so ShowWarning plays the sound even if the warning is already up
	ShowWarning()
end

local function CreateAlertFrame()
	f = CreateFrame("Frame", "AmityBattleShoutAlertFrame", UIParent)
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

	-- a solid red rim, with the action button glow around it
	f.rim = f:CreateTexture(nil, "BORDER")
	f.rim:SetPoint("TOPLEFT", -4, 4)
	f.rim:SetPoint("BOTTOMRIGHT", 4, -4)
	f.rim:SetColorTexture(1, 0, 0, 1)

	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.glow:SetBlendMode("ADD")
	f.glow:SetVertexColor(1, 0.1, 0.1)
	f.glow:SetSize(120, 120)
	f.glow:SetPoint("CENTER")

	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.text:SetPoint("BOTTOM", f, "TOP", 0, 10)
	f.text:SetTextColor(1, 0.2, 0.1)
	f.text:SetText("NO BATTLE SHOUT")

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", -6, 6)
	f.border:SetPoint("BOTTOMRIGHT", 6, -6)
	f.border:SetColorTexture(0, 1, 0, 0.6)
	f.border:Hide()

	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.label:SetPoint("TOP", f, "BOTTOM", 0, -8)
	f.label:SetText("Drag to move  |  right-click to lock")
	f.label:Hide()

	f:SetScript("OnUpdate", function(self)
		if self.unlocked then return end
		SetFlash(0.5 + 0.5 * math.sin(GetTime() * FLASH_SPEED))
	end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnCast(spellID)
	if IsSecret(spellID) or not SPELL_IDS[spellID] then return end
	knownExpires = GetTime() + knownDuration
end

local function OnEvent(self, event, arg1, arg2, arg3)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		OnCast(arg3)
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
	end
	Refresh()
end

local function Setup()
	local getName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
	local ok, name = pcall(getName, SPELL_ID)
	if ok and name then spellName = name end
	inCombat = InCombatLockdown()

	CreateAlertFrame()
	ApplyPosition()
	f:SetScript("OnEvent", OnEvent)
	f:RegisterUnitEvent("UNIT_AURA", "player")
	f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	C_Timer.NewTicker(CHECK_EVERY, Refresh)
	Refresh()
end

function M:Init(settings)
	db = settings
	-- a sound that is not in the list goes back to the default
	local known = db.sound == "NONE"
	for _, entry in ipairs(Amity.ALERT_SOUNDS) do
		if entry[1] == db.sound then known = true end
	end
	if not known then db.sound = "RAID_WARNING" end
	-- Only called for warriors, at PLAYER_LOGIN (see M:Unavailable).
	Setup()
end

---------------------------------------------------------------------------
-- Panel options
---------------------------------------------------------------------------

function M:Unavailable()
	local _, class = UnitClass("player")
	if class ~= "WARRIOR" then return "Warriors only: this character is not a warrior." end
end

M.options = {
	{ type = "select", key = "sound", label = "Sound when the alert appears",
		tooltip = "Picking a sound plays it once so you can hear it.",
		values = (function()
			local values = { { "NONE", "No sound" } }
			for _, entry in ipairs(Amity.ALERT_SOUNDS) do
				if SOUNDKIT and SOUNDKIT[entry[1]] then values[#values + 1] = entry end
			end
			return values
		end)() },
	{ type = "range", key = "warnBefore", label = "Seconds before it runs out to warn",
		min = 5, max = 60, step = 5, zero = "Off",
		tooltip = "Off warns only once the buff is gone." },
	{ type = "toggle", key = "combatOnly", label = "Only in combat",
		tooltip = "Show the warning only while you are in combat." },
	{ type = "button", label = function() return (f and f.unlocked) and "Lock icon" or "Unlock icon" end,
		tooltip = "Unlocked, the icon stays visible and can be dragged. Right-click it to lock.",
		onClick = function() SetUnlocked(not f.unlocked) end },
	{ type = "button", label = "Test alert",
		tooltip = "Shows the alert for 5 seconds, even if Battle Shout is active.",
		disabled = function() return f and f.unlocked end,
		onClick = function() TestAlert() end },
	{ type = "button", label = "Reset position",
		onClick = function() db.pos = nil; ApplyPosition() end },
}

function M:OnOptionChanged(key)
	if key == "sound" then PlayAlertSound() end -- preview
	Refresh()
end
