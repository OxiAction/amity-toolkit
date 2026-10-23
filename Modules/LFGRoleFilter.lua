--[[
	Amity module: LFG Role Filter
	=============================
	Adds three toggle buttons (Tank / Healer / DPS) to the "Browse" tab of the
	Looking For Group window on WoW Forever and filters the result list by
	role. Pick one or more roles; with none picked the list is untouched.

	What a selected role matches
	----------------------------
	* Solo players ("Looking for group" listings): the player can fill that role.
	* Groups ("Looking for more" listings): the group still needs that role
	  (default), or, with the "already has" group mode, the group has that role.
	* Your own listing is always shown.
	Several selected roles are OR-ed: a result is kept if any of them match.

	How it hooks in (WoW Forever uses Blizzard_GroupFinder_VanillaStyle)
	--------------------------------------------------------------------
	Blizzard's browse tab fetches the result IDs, sorts them with the global
	LFGBrowseUtil_SortSearchResults(results), then builds the scroll list from
	that same table. We hooksecurefunc that sort function and remove the
	non-matching IDs from the table in place, so the stock code draws only the
	results we kept. No Blizzard function is replaced and no Blizzard frame
	field is written; the only Blizzard-side mutation is the result-ID table,
	which only ever feeds unprotected actions (invite, whisper, report).
]]

local _, Amity = ...
local BLIZZ_ADDON = "Blizzard_GroupFinder_VanillaStyle"

local defaults = {
	tank   = false,
	healer = false,
	dps    = false,
	mode   = "needs", -- for groups: "needs" = has an open slot for the role, "has" = already has that role
}

local M = Amity:RegisterModule("lfgfilter", {
	title       = "LFG Role Filter",
	notes       = "Adds Tank / Healer / DPS filter buttons to the Looking For Group browse list.",
	description = "Adds Tank / Healer / DPS buttons to the Looking For Group browse list. Solo players "
		.. "are matched by the roles they can fill, groups by the roles they still need (or already "
		.. "have). Several roles show anyone matching any of them; your own listing is always shown.",
	defaults    = defaults,
})

local db -- AmityDB.lfgfilter

local ROLES = {
	{ key = "tank",   countKey = "TANK",    atlas = "groupfinder-icon-role-large-tank", label = TANK    or "Tank"   },
	{ key = "healer", countKey = "HEALER",  atlas = "groupfinder-icon-role-large-heal", label = HEALER  or "Healer" },
	{ key = "dps",    countKey = "DAMAGER", atlas = "groupfinder-icon-role-large-dps",  label = DAMAGER or "Damage" },
}

local BUTTON_SIZE = 26
local BUTTON_GAP  = 6

local function AnyRoleSelected()
	return db and (db.tank or db.healer or db.dps) or false
end

-------------------------------------------------------------------------------
-- Matching
-------------------------------------------------------------------------------

-- Solo listing: can this player fill the role?
local function SoloHasRole(resultID, counts, role)
	local flag = counts and counts["LEADER_ROLE_" .. role.countKey]
	if flag ~= nil then
		return flag == true
	end
	-- Older shape: roles live on the member info.
	local info = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
	local lfgRoles = info and info.lfgRoles
	return lfgRoles ~= nil and lfgRoles[role.key] == true
end

-- Group listing: does the group need (or have) the role?
local function GroupMatchesRole(counts, role)
	if not counts then return false end
	if db.mode == "has" then
		return (counts[role.countKey] or 0) > 0
	end
	return (counts[role.countKey .. "_REMAINING"] or 0) > 0
end

local function ResultMatches(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if not info or info.hasSelf then
		return true
	end
	local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
	local isSolo = info.numMembers == 1
	for _, role in ipairs(ROLES) do
		if db[role.key] then
			if isSolo then
				if SoloHasRole(resultID, counts, role) then return true end
			else
				if GroupMatchesRole(counts, role) then return true end
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- The filter hook
-------------------------------------------------------------------------------

local lastTotal, lastShown = 0, 0

-- Runs right after Blizzard's sort, on the very table the list is built from.
local function FilterResults(results)
	if type(results) ~= "table" then return end
	lastTotal = #results
	if not AnyRoleSelected() then
		lastShown = lastTotal
		return
	end
	for i = #results, 1, -1 do
		local ok, keep = pcall(ResultMatches, results[i])
		if ok and not keep then
			table.remove(results, i)
		end
	end
	lastShown = #results
end

-------------------------------------------------------------------------------
-- UI
-------------------------------------------------------------------------------

local ui -- { bar, buttons = {}, count, noMatch }

local function RoleTooltip(button)
	local role = button.role
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(role.label, 1, 1, 1)
	GameTooltip:AddLine("Solo players who can play this role.", nil, nil, nil, true)
	if db.mode == "has" then
		GameTooltip:AddLine("Groups that already have this role.", nil, nil, nil, true)
	else
		GameTooltip:AddLine("Groups that still need this role.", nil, nil, nil, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to toggle. Several roles = any of them.", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

local function UpdateButtonLook(button)
	local on = button:GetChecked()
	button.Icon:SetDesaturated(not on)
	button.Icon:SetAlpha(on and 1 or 0.4)
end

local function Refresh()
	if LFGBrowseFrame and LFGBrowseFrame:IsShown() and LFGBrowseFrame.UpdateResultList then
		LFGBrowseFrame:UpdateResultList()
	end
end

local function UpdateLabels()
	if not ui then return end
	local frame = LFGBrowseFrame
	local filtering = AnyRoleSelected()
	if not filtering or frame.searching then
		ui.count:Hide()
		ui.noMatch:Hide()
		return
	end
	ui.count:SetFormattedText("%d / %d", lastShown, lastTotal)
	ui.count:Show()
	ui.noMatch:SetShown(lastShown == 0 and lastTotal > 0 and not frame.searchFailed)
end

local function OnRoleClick(button)
	db[button.role.key] = button:GetChecked() and true or false
	UpdateButtonLook(button)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	Refresh()
	Amity:UpdatePanel()
end

local function CreateUI()
	if ui then return end
	local parent = LFGBrowseFrame
	if not parent then return end

	local bar = CreateFrame("Frame", "AmityLFGRoleFilterBar", parent)
	local width = #ROLES * BUTTON_SIZE + (#ROLES - 1) * BUTTON_GAP
	bar:SetSize(width, BUTTON_SIZE)
	-- Bottom row, centred between "Send Message" and "Invite".
	bar:SetPoint("BOTTOM", parent, "BOTTOM", 0, 17)

	ui = { bar = bar, buttons = {} }

	for i, role in ipairs(ROLES) do
		local b = CreateFrame("CheckButton", "AmityLFGRoleFilterButton" .. role.countKey, bar)
		b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
		b.role = role

		b.Icon = b:CreateTexture(nil, "ARTWORK")
		b.Icon:SetAllPoints(b)
		b.Icon:SetAtlas(role.atlas, false)

		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")

		b:SetChecked(db[role.key] and true or false)
		UpdateButtonLook(b)

		b:SetScript("OnClick", OnRoleClick)
		b:SetScript("OnEnter", RoleTooltip)
		b:SetScript("OnLeave", GameTooltip_Hide)

		ui.buttons[i] = b
	end

	-- "shown / total" just above the buttons
	ui.count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ui.count:SetPoint("BOTTOM", bar, "TOP", 0, 1)
	ui.count:Hide()

	-- Message in the list area when the filter hides everything
	ui.noMatch = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	ui.noMatch:SetWidth(240)
	ui.noMatch:SetPoint("TOP", parent.BackgroundArt or parent, "TOP", 0, -40)
	ui.noMatch:SetText("No results for the selected roles")
	ui.noMatch:Hide()

	-- Keep the labels in step with every list rebuild (hooksecurefunc on the
	-- frame's own method; Mixin copied it onto the frame table).
	if rawget(parent, "UpdateResults") then
		hooksecurefunc(parent, "UpdateResults", UpdateLabels)
	end
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

local hooked = false

local function IsBlizzAddonLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(BLIZZ_ADDON)
	elseif IsAddOnLoaded then
		return IsAddOnLoaded(BLIZZ_ADDON)
	end
	return false
end

local function TrySetup()
	if hooked then return end
	if not IsBlizzAddonLoaded() or not LFGBrowseFrame then return end
	if type(LFGBrowseUtil_SortSearchResults) ~= "function" then return end
	hooksecurefunc("LFGBrowseUtil_SortSearchResults", FilterResults)
	CreateUI()
	hooked = true
end

-------------------------------------------------------------------------------
-- Panel options
-------------------------------------------------------------------------------

local function SyncButtons()
	if not ui then return end
	for _, b in ipairs(ui.buttons) do
		b:SetChecked(db[b.role.key] and true or false)
		UpdateButtonLook(b)
	end
end

M.options = {
	{ type = "header", label = "Show listings for these roles" },
	{ type = "toggle", key = "tank",   label = ROLES[1].label },
	{ type = "toggle", key = "healer", label = ROLES[2].label },
	{ type = "toggle", key = "dps",    label = ROLES[3].label },
	{ type = "select", key = "mode", label = "Which groups count as a match?",
		tooltip = "Solo players always match by the roles they can play.",
		values = {
			{ "needs", "Groups that are still looking for the role" },
			{ "has",   "Groups that already have a player in the role" },
		} },
	{ type = "button", label = "Clear role filters",
		onClick = function() db.tank, db.healer, db.dps = false, false, false; M:OnOptionChanged() end },
}

function M:OnOptionChanged()
	SyncButtons()
	Refresh()
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function M:Init(settings)
	db = settings

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:SetScript("OnEvent", function(self, event, arg1)
		-- PLAYER_LOGIN: in case the group finder was already loaded before us
		if (event == "ADDON_LOADED" and arg1 == BLIZZ_ADDON) or event == "PLAYER_LOGIN" then
			TrySetup()
		end
	end)
	TrySetup()
end
