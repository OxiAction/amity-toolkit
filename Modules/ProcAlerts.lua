--[[
	Amity modules: Overpower Alert and Revenge Alert
	================================================
	Warriors only: each shows its own movable spell icon with a 5 second
	countdown while its proc is up (Overpower after the target dodges, Revenge
	after you block, dodge or parry). Both are built by CreateProcAlert, and
	each is a module of its own: its own tab, switch, sound and icon position.
	While the spell is on cooldown the icon shows the action bar's radial sweep,
	but only out of combat: in combat the cooldown API returns secret values,
	which this client's Cooldown widget may refuse (see UpdateCooldown).
	The Unavailable check makes the core skip them entirely on other classes:
	no frames, no events.

	WoW Forever: CombatLogGetCurrentEventInfo is restricted to the secure
	Blizzard environment (ADDON_ACTION_FORBIDDEN for addons), so the modules
	track the spell's usability instead: it becomes usable only during the
	window after its proc. A proc also counts when only rage is missing (the
	client reports that separately); the icon is then tinted blue, like the
	action bars.

	Overpower in Berserker Stance: the spell is never usable outside Battle
	Stance, so there the module watches UNIT_COMBAT on the target instead
	(its "DODGE" action is readable, only the amount is a secret value). The
	event does not say whose attack was dodged, so in a group it is only
	used when no other member or pet could have attacked the target: each
	one is ruled out only when it is definitely not visible, offline, dead,
	out of range (~40 yd) or targeting something else. Anything the game
	won't tell (an error or a secret value) counts as a possible attacker.
	(The combo point Overpower is flagged with is not given to warriors:
	GetComboPoints stays 0 after a dodge, tested in game.) What the game would still
	refuse after the stance swap is checked by hand:
	* Overpower's own 5s cooldown, timed from our last cast (the cooldown API
	  is secret in combat). A dodge is ignored when the cooldown outlasts
	  the window, otherwise the icon shows the remaining cooldown sweep.
	* Rage: a stance swap keeps only what Tactical Mastery allows (5 per
	  rank). Too little for Overpower tints the icon blue, as in Battle Stance.
	* The window belongs to the target that dodged (Overpower works like
	  combo points), so changing target ends it.
]]

local _, Amity = ...

local DURATION = 5
local EXPIRY_GRACE = 0.5 -- seconds a still usable spell may outlast the countdown before it restarts

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
Amity.ALERT_SOUNDS = SOUNDS -- shared with BattleShoutAlert.lua

local function CreateProcAlert(spec)
	local SPELL = spec.spell

	local M = Amity:RegisterModule(spec.key, {
		title       = spec.title,
		notes       = spec.notes,
		description = spec.description,
		defaults    = { sound = "RAID_WARNING" }, -- a SOUNDKIT name, or "NONE"
	})

	local db -- AmityDB[spec.key]
	local f  -- the alert frame, created in Init (warriors only)
	local procActive = false
	local lastCast -- GetTime() of our last cast, for spec.cooldown

	local function PlayAlertSound()
		local id = SOUNDKIT and SOUNDKIT[db.sound]
		if id then PlaySound(id, "Master") end
	end

	local function GetSpellIcon()
		local tex
		if C_Spell and C_Spell.GetSpellTexture then
			tex = C_Spell.GetSpellTexture(spec.spellID) or C_Spell.GetSpellTexture(SPELL)
		elseif GetSpellTexture then
			tex = GetSpellTexture(spec.spellID) or GetSpellTexture(SPELL)
		end
		return tex or spec.fallbackIcon
	end

	-- Returns whether the proc is up, and whether only rage is missing to use it.
	local function ProcState()
		local fn = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
		local ok, usable, noRage = pcall(fn, SPELL)
		if not ok then return false, false end
		noRage = noRage == true
		return usable == true or noRage, noRage
	end

	-- In combat the cooldown API returns secret values: tainted code may not
	-- compare them or do math on them, only hand them to widgets that accept
	-- secrets (Cooldown:SetCooldown does).
	local function IsSecret(v)
		return issecretvalue ~= nil and issecretvalue(v) == true
	end

	-- A flag that says the cooldown is off; a secret flag is assumed on.
	local function IsOff(flag)
		if IsSecret(flag) then return false end
		return flag == false or flag == 0
	end

	local TACTICAL_MASTERY = { 12295, 12676, 12677, 12678, 12679 } -- ranks 1-5

	local function IsKnown(spellID)
		for _, fn in ipairs({ IsPlayerSpell or false, C_SpellBook and C_SpellBook.IsSpellKnown or false }) do
			if fn then
				local ok, known = pcall(fn, spellID)
				if ok and known == true then return true end
			end
		end
		return false
	end

	-- After swapping to Battle Stance, would there be rage enough to cast?
	-- Unknown (secret rage) counts as enough.
	local function TooLittleRageAfterSwap()
		local ok, rage = pcall(UnitPower, "player", Enum and Enum.PowerType and Enum.PowerType.Rage or 1)
		if not ok or type(rage) ~= "number" or IsSecret(rage) then return false end
		local kept = 0
		for rank, id in ipairs(TACTICAL_MASTERY) do
			if IsKnown(id) then kept = rank * 5 end
		end
		return math.min(rage, kept) < spec.rageCost
	end

	local function SpellCooldown()
		if C_Spell and C_Spell.GetSpellCooldown then
			local ok, info = pcall(C_Spell.GetSpellCooldown, SPELL)
			if ok and info and not IsOff(info.isActive) and not IsOff(info.isEnabled) then
				return info.startTime, info.duration, info.modRate
			end
			return 0, 0
		end
		local ok, start, duration, enabled, modRate = pcall(GetSpellCooldown, SPELL)
		if ok and not IsOff(enabled) then return start, duration, modRate end
		return 0, 0
	end

	---------------------------------------------------------------------------
	-- UI
	---------------------------------------------------------------------------

	local function UpdateRageTint()
		local noRage
		if f.fromDodge and not procActive then
			noRage = TooLittleRageAfterSwap() -- still in Berserker Stance
		else
			noRage = select(2, ProcState())
		end
		if noRage then
			f.icon:SetVertexColor(0.5, 0.5, 1)
		else
			f.icon:SetVertexColor(1, 1, 1)
		end
	end

	-- Includes the global cooldown, like the action bars.
	local function UpdateCooldown()
		-- Our own record first: in combat the API's values are secret.
		if spec.cooldown and lastCast and GetTime() < lastCast + spec.cooldown then
			f.cooldown:SetCooldown(lastCast, spec.cooldown)
			return
		end
		local start, duration, modRate = SpellCooldown()
		if IsSecret(start) or IsSecret(duration) or IsSecret(modRate) then
			-- Can't check them, so let the widget decide: a zero duration draws no sweep.
			if not pcall(f.cooldown.SetCooldown, f.cooldown, start, duration, modRate) then
				f.cooldown:Clear()
			end
		elseif start and duration and start > 0 and duration > 0 then
			f.cooldown:SetCooldown(start, duration, modRate)
		else
			f.cooldown:Clear()
		end
	end

	local function ApplyPosition()
		f:ClearAllPoints()
		if db.pos then
			f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
		else
			f:SetPoint("CENTER", UIParent, "CENTER", 0, spec.defaultY)
		end
	end

	-- Unlocked: the icon stays visible and can be dragged.
	local function SetUnlocked(on)
		f.unlocked = on
		f:EnableMouse(on)
		f.border:SetShown(on)
		f.label:SetShown(on)
		f.cooldown:Clear()
		if on then
			f.expires = nil
			f.icon:SetTexture(GetSpellIcon())
			f.icon:SetVertexColor(1, 1, 1)
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
		f.icon:SetTexture(GetSpellIcon())
		UpdateRageTint()
		f:Show()
		UpdateCooldown()
		PlayAlertSound()
	end

	local function Cancel()
		if f.unlocked then return end
		f.expires = nil
		f.fromDodge = nil
		f.cooldown:Clear()
		f:Hide()
	end

	local function TestAlert()
		f.expires = nil
		Trigger()
	end

	local function CreateAlertFrame()
		f = CreateFrame("Frame", spec.frameName, UIParent)
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

		f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
		f.cooldown:SetAllPoints()
		-- drawn like the action bars: dark sweep, no edge line, no numbers of its own
		if f.cooldown.SetDrawSwipe then f.cooldown:SetDrawSwipe(true) end
		if f.cooldown.SetSwipeColor then f.cooldown:SetSwipeColor(0, 0, 0, 0.8) end
		if f.cooldown.SetDrawEdge then f.cooldown:SetDrawEdge(false) end
		if f.cooldown.SetHideCountdownNumbers then f.cooldown:SetHideCountdownNumbers(true) end

		-- a frame above the sweep, which would otherwise darken the countdown
		local textLayer = CreateFrame("Frame", nil, f)
		textLayer:SetAllPoints()
		textLayer:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)

		f.text = textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
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
			if remaining > 0 then
				self.text:SetFormattedText("%.1f", remaining)
			elseif not (procActive and ProcState()) then
				Cancel()
			elseif remaining > -EXPIRY_GRACE then
				self.text:SetText("0.0")
			else
				-- Still up after the countdown: a new dodge/block/parry renewed the
				-- proc, which raises no event of its own, so count down again.
				self.expires = GetTime() + DURATION - EXPIRY_GRACE
			end
		end)
	end

	---------------------------------------------------------------------------
	-- Proc tracking
	---------------------------------------------------------------------------

	local function IsTrackedSpell(spellID)
		if spec.spellIDs[spellID] then return true end
		local ok, name = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, spellID)
		return ok and name == SPELL
	end

	local function CheckUsable()
		local procced = ProcState()
		if procced and not procActive then
			procActive = true
			Trigger()
		elseif not procced and procActive then
			procActive = false
			Cancel()
		end
		if f.expires then UpdateRageTint() end -- rage changes while the icon is up
	end

	local function InStance(stanceSpellID)
		local form = GetShapeshiftForm and GetShapeshiftForm() or 0
		if form == 0 then return false end
		local _, _, _, formSpellID = GetShapeshiftFormInfo(form)
		return formSpellID == stanceSpellID
	end

	-- Calls fn(...) and returns its first result if it is a plain boolean;
	-- an error or a secret value gives nil (unknown).
	local function SafeBool(fn, ...)
		if not fn then return nil end
		local ok, v = pcall(fn, ...)
		if not ok or IsSecret(v) or type(v) ~= "boolean" then return nil end
		return v
	end

	-- Could this group unit (a member or their pet) have attacked our target?
	-- Only a definite "no" clears it: anything unknown counts as yes.
	local function CouldAttackTarget(unit)
		if SafeBool(UnitExists, unit) == false then return false end
		if SafeBool(UnitIsUnit, unit, "player") then return false end
		if SafeBool(UnitIsVisible, unit) == false then return false end -- far away or another zone
		if SafeBool(UnitIsConnected, unit) == false then return false end
		if SafeBool(UnitIsDeadOrGhost, unit) == true then return false end
		if UnitInRange then
			local ok, inRange, checked = pcall(UnitInRange, unit)
			if ok and not IsSecret(inRange) and not IsSecret(checked)
				and checked == true and inRange == false then
				return false -- more than ~40 yards from us, so not at our melee target
			end
		end
		-- Not targeting our target (and no target at all counts as unknown).
		if SafeBool(UnitExists, unit .. "target") == false then return true end
		return SafeBool(UnitIsUnit, unit .. "target", "target") ~= false
	end

	-- In a group the dodge may come from someone else's attack. It is ours
	-- only if no other member or pet could have attacked our target.
	local function DodgeCouldBeOthers()
		if not IsInGroup() then return false end
		local prefix, count
		if IsInRaid() then
			prefix, count = "raid", 40
		else
			prefix, count = "party", 4
		end
		for i = 1, count do
			local unit = prefix .. i
			local petUnit = prefix == "raid" and ("raidpet" .. i) or ("partypet" .. i)
			if CouldAttackTarget(unit) or CouldAttackTarget(petUnit) then return true end
		end
		return false
	end

	-- The target dodged while we are in spec.dodgeStance (where the spell is
	-- not usable, so CheckUsable never sees the proc).
	local function OnTargetDodge()
		if f.unlocked or not InStance(spec.dodgeStance) then return end
		if DodgeCouldBeOthers() then return end -- can't tell whose attack was dodged
		if not UnitCanAttack("player", "target") or not UnitAffectingCombat("player") then return end
		-- On cooldown for the whole window: no chance to use it.
		if spec.cooldown and lastCast and lastCast + spec.cooldown - GetTime() >= DURATION then return end
		if f.expires then
			f.expires = GetTime() + DURATION -- dodged again: the window starts over
		else
			f.fromDodge = true
			Trigger()
		end
	end

	local function OnEvent(self, event, arg1, arg2, arg3)
		if event == "UNIT_COMBAT" then
			if arg2 == "DODGE" then OnTargetDodge() end
		elseif event == "SPELL_UPDATE_USABLE" then
			CheckUsable()
		elseif event == "SPELL_UPDATE_COOLDOWN" then
			if f.expires then UpdateCooldown() end
		elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
			if IsTrackedSpell(arg1) then Trigger() end
		elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
			if IsTrackedSpell(arg1) then Cancel() end
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			if IsTrackedSpell(arg3) then lastCast = GetTime() procActive = false Cancel() end
		elseif event == "PLAYER_TARGET_CHANGED" then
			-- The window belongs to the target that dodged.
			if f.fromDodge and not procActive then Cancel() end
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
		f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
		f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
		f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		if spec.dodgeStance then
			f:RegisterUnitEvent("UNIT_COMBAT", "target")
			f:RegisterEvent("PLAYER_TARGET_CHANGED")
		end
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
				for _, entry in ipairs(SOUNDS) do
					if SOUNDKIT and SOUNDKIT[entry[1]] then values[#values + 1] = entry end
				end
				return values
			end)() },
		{ type = "button", label = function() return (f and f.unlocked) and "Lock icon" or "Unlock icon" end,
			tooltip = "Unlocked, the icon stays visible and can be dragged. Right-click it to lock.",
			onClick = function() SetUnlocked(not f.unlocked) end },
		{ type = "button", label = "Test alert",
			tooltip = spec.testTooltip,
			disabled = function() return f and f.unlocked end,
			onClick = function() TestAlert() end },
		{ type = "button", label = "Reset position",
			onClick = function() db.pos = nil; ApplyPosition() end },
	}

	function M:OnOptionChanged(key)
		if key == "sound" then PlayAlertSound() end -- preview
	end
end

CreateProcAlert({
	key          = "overpower",
	spell        = "Overpower",
	spellID      = 7384, -- Rank 1; all ranks share the name/icon
	spellIDs     = { [7384] = true, [7887] = true, [11584] = true, [11585] = true },
	fallbackIcon = "Interface/Icons/Ability_MeleeDamage",
	frameName    = "AmityOverpowerAlertFrame",
	defaultY     = 100,
	dodgeStance  = 2458, -- Berserker Stance: watch the target's dodges there
	cooldown     = 5,
	rageCost     = 5,
	title        = "Overpower Alert - Warrior",
	notes        = "Warriors only: movable Overpower icon with a 5s countdown when your target dodges.",
	description  = "Warriors only. When your target dodges, a large Overpower icon appears with a 5 second countdown, "
		.. "even without the rage to use it: the icon is then tinted blue. "
		.. "It also appears in Berserker Stance, so you can switch to Battle Stance in time: while solo, "
		.. "or in a group when no one else is attacking your target (out of range or on another target). "
		.. "It disappears when you use Overpower or leave combat. Unlock the icon to drag it "
		.. "where you want it.",
	testTooltip  = "Shows the alert as if your target had dodged.",
})

CreateProcAlert({
	key          = "revenge",
	spell        = "Revenge",
	spellID      = 6572, -- Rank 1; all ranks share the name/icon
	spellIDs     = { [6572] = true, [6574] = true, [7379] = true, [11600] = true, [11601] = true, [25288] = true },
	fallbackIcon = "Interface/Icons/Ability_Warrior_Revenge",
	frameName    = "AmityRevengeAlertFrame",
	defaultY     = 190, -- above the Overpower icon, clear of its unlock label
	title        = "Revenge Alert - Warrior",
	notes        = "Warriors only: movable Revenge icon with a 5s countdown when you block, dodge or parry.",
	description  = "Warriors only. When you block, dodge or parry, a large Revenge icon appears with a 5 second "
		.. "countdown, even without the rage to use it: the icon is then tinted blue. "
		.. "It disappears when you use Revenge or leave combat. Unlock the icon "
		.. "to drag it where you want it, separately from the Overpower icon.",
	testTooltip  = "Shows the alert as if you had blocked, dodged or parried.",
})
