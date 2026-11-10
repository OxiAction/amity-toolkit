--[[
	Amity baseline: LFG player location
	===================================
	Shows where a player currently is in every entry of the Looking For Group
	browse list, on the line of the game type ("Relaxed  Badlands"). For a
	group this is the leader's location.

	This is always on, so it is not a module: no enable switch, no settings
	and no tab in the panel.

	How it hooks in
	---------------
	C_LFGList returns areaName with the player info of a listing, Blizzard's
	list just never displays it. LFGBrowseSearchEntry_Update(row) redraws one
	row, both when a row is filled and when its listing changes, so a
	hooksecurefunc on it keeps the text current on recycled rows.

	Blizzard's rows stack name, activity and game type with no room for a
	fourth line, and their heights differ per row template, so the text sits
	in the free space on the last line and the rows are left alone. Your own
	listing has no game type line; there the text follows the activity.
]]

local BLIZZ_ADDON = "Blizzard_GroupFinder_VanillaStyle"

local TEXT_GAP = 8 -- between the line's own text and the location

local function GetLocation(resultID)
	local info = C_LFGList.GetSearchResultLeaderInfo(resultID)
		or C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
	return info and info.areaName
end

local function CreateLocationText(row)
	local text = row:CreateFontString(nil, "ARTWORK", "GameFontDisableLeft")
	local playstyle = row.PlaystyleLabel

	-- Only the game type line sits below the role display, the activity line
	-- has to stop short of it.
	local rightInset = playstyle and 8 or (row.DataDisplay:GetWidth() + 4)

	-- Left and right edges are both anchored so a long zone name truncates
	-- inside the row. Top aligned because the two anchors share no line.
	text:SetPoint("TOPLEFT", playstyle or row.ActivityName, "TOPRIGHT", TEXT_GAP, -1)
	text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -rightInset, 0)
	text:SetJustifyV("TOP")
	text:SetWordWrap(false)

	row.AmityLocation = text
	return text
end

local function UpdateRow(row)
	local text = row.AmityLocation or CreateLocationText(row)
	text:SetText(GetLocation(row.resultID) or "")
	-- Blizzard has just coloured the level, including the delisted gray.
	text:SetTextColor(row.Level:GetTextColor())
end

local hooked = false

local function TrySetup()
	if hooked then return end
	if type(LFGBrowseSearchEntry_Update) ~= "function" then return end
	hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateRow)
	hooked = true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
	-- PLAYER_LOGIN: in case the group finder was already loaded before us
	if (event == "ADDON_LOADED" and arg1 == BLIZZ_ADDON) or event == "PLAYER_LOGIN" then
		TrySetup()
	end
end)
TrySetup()
