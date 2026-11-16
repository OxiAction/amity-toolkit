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

	Only enchants cast from the profession window are confirmed. Armor kits,
	weapon oils and sharpening stones are item uses, and finishing an item use
	from addon code is a protected action: the game blocks it and shows the
	"blocked from an action only available to the Blizzard UI" dialog. So the
	module only confirms while an enchant started from the profession window
	(DoCraft / DoTradeSkill, hooked as globals) is pending, and leaves the
	prompt alone for items. The flag is cleared by the player's spellcast
	events, never by hooking item use: hooking C_Container.UseContainerItem
	and friends puts Amity on the path of every bag click, and then the game
	blocks right-clicking a recipe or any other item.

	If the game still refuses a confirmation, the module stops for the session
	and the normal prompt comes back.
]]

local ADDON_NAME, Amity = ...

local M = Amity:RegisterModule("replaceenchant", {
	title        = "Auto Replace Enchant",
	notes        = "Skips the \"replace this enchant?\" prompt for profession enchants.",
	description  = "Removes the prompt that asks whether to replace an existing enchant when you enchant from the "
		.. "Enchanting window: the new enchant is applied right away, which saves a click per item when levelling "
		.. "Enchanting. Careful: a good enchant can be overwritten without warning. Off by default. Armor kits, "
		.. "weapon oils and stones still ask (the game does not let addons confirm those), and so does enchanting "
		.. "an item in the trade window.",
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
local fromProfession = false -- the pending enchant was cast from the profession window

local function OnPopupShown(which)
	local name = CONFIRM[which]
	if not name or blocked or not fromProfession then return end
	local confirm = (C_Item and C_Item[name]) or _G[name]
	if not confirm then return end
	fromProfession = false
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

local function OnEvent(_, event, ...)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		OnActionBlocked(_, event, ...)
	else
		-- the pending cast finished, failed or was cancelled: forget where it came from
		fromProfession = false
	end
end

function M:Init()
	hooksecurefunc("StaticPopup_Show", OnPopupShown)

	-- Plain global functions only: never hook C_Container / C_Item / UseAction.
	for _, name in ipairs({ "DoCraft", "DoTradeSkill" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function() fromProfession = true end)
		end
	end

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_ACTION_BLOCKED")
	frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP" }) do
		pcall(frame.RegisterUnitEvent, frame, event, "player")
	end
	frame:SetScript("OnEvent", OnEvent)
end
