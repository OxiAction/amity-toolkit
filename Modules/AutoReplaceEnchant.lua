--[[
	Amity module: Auto Replace Enchant
	==================================
	Off by default. Answers "Yes" for you when the game asks whether to replace
	an existing enchant, so levelling Enchanting on already enchanted items
	takes one click per item.

	How it hooks in
	---------------
	StaticPopup_Show is post-hooked rather than listening to the events, so the
	popup is guaranteed to exist when it is confirmed and closed. Enchanting an
	item in the trade window (TRADE_REPLACE_ENCHANT) keeps its prompt: that item
	is someone else's.

	If the game refuses the confirmation (the Blizzard API marks these calls as
	unrestricted, but a client patch could change that), the module stops for
	the session and the normal prompt comes back.
]]

local ADDON_NAME, Amity = ...

local M = Amity:RegisterModule("replaceenchant", {
	title        = "Auto Replace Enchant",
	notes        = "Skips the \"replace this enchant?\" prompt and enchants right away.",
	description  = "Removes the prompt that asks whether to replace an existing enchant: the new enchant is applied "
		.. "right away, which saves a click per item when levelling Enchanting. Careful: this applies to every "
		.. "enchant on your own items, including weapon oils and stones, so a good enchant can be overwritten "
		.. "without warning. Off by default. Enchanting an item in the trade window still asks.",
	offByDefault = true,
})

-- popup -> the function its Yes button calls
local CONFIRM = {
	REPLACE_ENCHANT            = "ReplaceEnchant",
	REPLACE_TRADESKILL_ENCHANT = "ReplaceTradeskillEnchant",
}

local BLOCKED_WINDOW = 1 -- seconds after a confirmation in which a blocked action is ours

local lastConfirm = 0
local blocked = false

local function OnPopupShown(which)
	local name = CONFIRM[which]
	if not name or blocked then return end
	local confirm = (C_Item and C_Item[name]) or _G[name]
	if not confirm then return end
	lastConfirm = GetTime()
	confirm()
	if not blocked then StaticPopup_Hide(which) end
end

local function OnActionBlocked(_, _, addon)
	if addon ~= ADDON_NAME or blocked or GetTime() - lastConfirm > BLOCKED_WINDOW then return end
	blocked = true
	local frame = DEFAULT_CHAT_FRAME or ChatFrame1
	if frame then
		frame:AddMessage(Amity.NAME .. ": the game blocked Auto Replace Enchant, so you will get the normal "
			.. "prompt until you reload. Enchant the item again.")
	end
end

function M:Init()
	hooksecurefunc("StaticPopup_Show", OnPopupShown)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_ACTION_BLOCKED")
	frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	frame:SetScript("OnEvent", OnActionBlocked)
end
