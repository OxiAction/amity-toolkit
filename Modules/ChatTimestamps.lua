--[[
	Amity module: Chat Timestamps
	=============================
	Puts the time in front of every message in the chat windows, e.g.
	"14:17 [Guild] [Someone]: hi". Format, brackets and colour are settings
	and apply to new messages right away.

	How it hooks in
	---------------
	Every chat frame's AddMessage is wrapped: the wrapper prefixes the text and
	calls the original. This covers the normal windows (ChatFrame1..N) and the
	temporary whisper / pet battle windows, which are wrapped when
	FCF_OpenTemporaryWindow creates them. The combat log window is skipped (it
	has its own timestamp setting), and so is everything while Blizzard's own
	"Chat Timestamps" interface option is on, so messages never get two times.
	If prefixing fails for some message, it is shown unchanged. Some messages
	arrive as secret strings, which tainted code must never compare (see
	Stamped).
]]

local _, Amity = ...

local M = Amity:RegisterModule("chattime", {
	title       = "Chat Timestamps",
	notes       = "Shows the time, e.g. 14:17, in front of every chat message.",
	description = "Shows the time in front of every message in your chat windows, e.g. \"14:17\". "
		.. "Uses your computer's clock. The combat log is left alone, and while Blizzard's own "
		.. "Chat Timestamps option is on this module stays out of the way so you never see the time twice.",
	defaults    = {
		format   = "%H:%M", -- a date() format, see FORMATS
		brackets = false,
		gray     = true,
	},
})

local db -- AmityDB.chattime

local FORMATS = {
	{ "%H:%M",       "14:17" },
	{ "%H:%M:%S",    "14:17:05" },
	{ "%I:%M %p",    "2:17 PM" },
	{ "%I:%M:%S %p", "2:17:05 PM" },
}

local GRAY = "|cff808080"

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar

-- Blizzard's own timestamps are on: leave messages alone.
local function BlizzardTimestampsOn()
	local value = GetCVar and GetCVar("showTimestamps")
	return value ~= nil and value ~= "" and value ~= "none"
end

local function Stamp()
	local text = date(db.format)
	if db.format:find("%I", 1, true) then
		text = text:gsub("^0", "") -- "02:17 PM" -> "2:17 PM"
	end
	if db.brackets then text = "[" .. text .. "]" end
	if db.gray then text = GRAY .. text .. "|r" end
	return text .. " "
end

-- Returns the stamped text, or nil to leave the message as it is.
-- Some messages are secret strings (WoW Forever): tainted code may not compare
-- them or ask their length, only concatenate them (the result stays secret).
-- So secrets skip the empty check; if even concatenating is refused, the
-- caller's pcall leaves the message unchanged.
local function Stamped(text)
	if issecretvalue and issecretvalue(text) then
		return Stamp() .. text
	end
	if type(text) ~= "string" or text == "" then return nil end
	return Stamp() .. text
end

local wrapped = {} -- chat frame -> true

local function WrapFrame(frame)
	if not frame or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
	wrapped[frame] = true
	local original = frame.AddMessage
	frame.AddMessage = function(self, text, ...)
		if self ~= _G.COMBATLOG and Amity:IsModuleEnabled("chattime") and not BlizzardTimestampsOn() then
			local ok, stamped = pcall(Stamped, text)
			if ok and stamped then text = stamped end
		end
		return original(self, text, ...)
	end
end

local function WrapAllFrames()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		WrapFrame(_G["ChatFrame" .. i])
	end
	if CHAT_FRAMES then
		for _, name in ipairs(CHAT_FRAMES) do
			WrapFrame(_G[name])
		end
	end
end

-------------------------------------------------------------------------------
-- Panel options
-------------------------------------------------------------------------------

M.options = {
	{ type = "select", key = "format", label = "Time format", values = FORMATS },
	{ type = "toggle", key = "brackets", label = "Brackets around the time",
		tooltip = "[14:17] instead of 14:17" },
	{ type = "toggle", key = "gray", label = "Gray time",
		tooltip = "Show the time in gray instead of the message's colour." },
	{ type = "button", label = "Show example",
		tooltip = "Prints a line in your chat window so you can see the result.",
		onClick = function()
			local frame = DEFAULT_CHAT_FRAME or ChatFrame1
			if not frame then return end
			if BlizzardTimestampsOn() then
				frame:AddMessage(Amity.NAME .. ": Blizzard's own Chat Timestamps option is on, so this module "
					.. "adds nothing. Turn it off under Options > Social to use these settings.")
			else
				frame:AddMessage(Amity.NAME .. ": this is how chat messages look now.")
			end
		end },
}

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------

function M:Init(settings)
	db = settings
	WrapAllFrames()
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", WrapAllFrames)
	end
end
