--[[
	Amity module: Chat Timestamps
	=============================
	Puts the time in front of every message in the chat windows, e.g.
	"14:17 [Guild] [Someone]: hi". Format, brackets and colour are settings.

	How it hooks in
	---------------
	It doesn't hook anything. The module writes a date() format into Blizzard's
	own "showTimestamps" CVar (the Options > Social > Chat Timestamps setting),
	so Blizzard's chat code adds the time itself. Brackets and the gray colour
	are part of that format string ("|cff808080%H:%M|r ").

	An earlier version wrapped every chat frame's AddMessage. That put addon
	code inside Blizzard's chat event handler, which then ran tainted for every
	message and failed on protected tables ("attempted to iterate a table that
	cannot be accessed while tainted"), thousands of times in battlegrounds.
	Never wrap AddMessage or add chat filters here again.

	The CVar value the module wrote is remembered (db.applied) together with
	the value it replaced (db.previous). When the module is switched off, that
	previous value is restored at the next login, unless the user changed the
	setting themselves in the meantime.
]]

local _, Amity = ...

local M = Amity:RegisterModule("chattime", {
	title       = "Chat Timestamps",
	notes       = "Shows the time, e.g. 14:17, in front of every chat message.",
	description = "Shows the time in front of every message in your chat windows, e.g. \"14:17\". "
		.. "Uses your computer's clock and Blizzard's own chat timestamp setting (Options > Social), "
		.. "so it takes over that setting while it is on. The combat log is left alone. "
		.. "If a change does not show up right away, /reload.",
	defaults    = {
		format   = "%H:%M", -- a date() format, see FORMATS
		brackets = false,
		gray     = true,
	},
})

local db -- AmityDB.chattime

local CVAR = "showTimestamps"

local FORMATS = {
	{ "%H:%M",       "14:17" },
	{ "%H:%M:%S",    "14:17:05" },
	{ "%I:%M %p",    "02:17 PM" },
	{ "%I:%M:%S %p", "02:17:05 PM" },
}

local GRAY = "|cff808080"

local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

-- The full format for Blizzard's CVar, e.g. "|cff808080[%H:%M]|r ".
local function BuildFormat(settings)
	local text = settings.format
	if settings.brackets then text = "[" .. text .. "]" end
	if settings.gray then text = GRAY .. text .. "|r" end
	return text .. " "
end

local function Apply()
	local value = BuildFormat(db)
	local current = GetCVar(CVAR)
	if current ~= value and current ~= db.applied then
		db.previous = current -- the user's own setting, restored when switched off
	end
	if current ~= value then SetCVar(CVAR, value) end
	db.applied = value
end

-- Module switched off: give the setting back, unless the user changed it.
local function Restore(settings)
	if not settings or not settings.applied then return end
	if GetCVar(CVAR) == settings.applied then
		local previous = settings.previous
		if not previous or previous == "" then previous = "none" end
		SetCVar(CVAR, previous)
	end
	settings.applied, settings.previous = nil, nil
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
			frame:AddMessage(Amity.NAME .. ": chat messages now look like this: "
				.. date(BuildFormat(db)) .. "|cff40ff40[Guild] [Someone]: hi|r")
		end },
}

function M:OnOptionChanged()
	if db and Amity.loaded.chattime then Apply() end
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------

function M:Init(settings)
	db = settings
end

-- CVars are only reliable from PLAYER_LOGIN on (account settings load late).
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
	if Amity.loaded.chattime and db then
		Apply()
	elseif Amity.db then
		Restore(Amity.db.chattime)
	end
end)
