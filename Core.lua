--[[
	Amity Toolkit
	=============
	One addon, several independent modules (Bar Text, Auction Item Level,
	LFG Role Filter, Overpower Alert). Each module lives in Modules\ and
	registers itself with Amity:RegisterModule. On ADDON_LOADED the core
	creates the saved variables and initializes every enabled module.

	Modules install hooks that cannot be undone at runtime, so switching a
	module on or off takes effect after a UI reload. The panel (minimap
	button or /amity) offers a reload button whenever changes are pending.

	Saved variables (AmityDB):
	{
		modules = { [key] = true|false },  -- which modules are enabled
		minimap = { angle = 225, hide = false },
		[key]   = { ... },                 -- each module's own settings
	}
]]

local ADDON_NAME, Amity = ...

Amity.BRAND = "|cff3fe0c5Amity|r"           -- short chat prefix
Amity.NAME = "|cff3fe0c5Amity|r Toolkit"   -- full name for titles
Amity.ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Icon"
Amity.MINIMAP_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\MinimapIcon"

local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
Amity.version = GetMetadata and GetMetadata(ADDON_NAME, "Version") or "?"
if Amity.version:find("@", 1, true) then
	Amity.version = "dev" -- running from the git checkout; the packager fills in the real version
end

Amity.modules = {}     -- key -> module
Amity.moduleOrder = {} -- keys in registration (= TOC) order
Amity.loaded = {}      -- key -> true when the module was initialized this session

-- The standalone addons Amity replaces; running both would hook everything twice.
local LEGACY_ADDONS = { "AlwaysBarText", "AuctionItemLevel", "LFGRoleFilter", "OverpowerAlert" }

-------------------------------------------------------------------------------
-- Shared helpers
-------------------------------------------------------------------------------

function Amity.CopyDefaults(src, dst)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if dst[k] == nil then dst[k] = v end
	end
	return dst
end

function Amity.OnOff(v) return v and "|cff00ff00on|r" or "|cffff0000off|r" end

function Amity.ParseBool(s)
	if s == "on" or s == "1" or s == "true" or s == "enable" then return true end
	if s == "off" or s == "0" or s == "false" or s == "disable" then return false end
	return nil
end

-- "Amity: msg" or, with a tag, "Amity [Bar Text]: msg"
function Amity.Print(msg, tag)
	local prefix = Amity.BRAND
	if tag then prefix = prefix .. " |cffaaaaaa[" .. tag .. "]|r" end
	DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------

--[[
	module = {
		title    = "Bar Text",
		notes    = "one line for the panel",
		defaults = { ... },             -- module settings
		slash    = { "/abt", ... },     -- optional slash commands, routed to module:Slash(msg)
		Init     = function(self, db),  -- called once at load if enabled
		Slash    = function(self, msg), -- optional
	}
]]
function Amity:RegisterModule(key, module)
	module.key = key
	self.modules[key] = module
	self.moduleOrder[#self.moduleOrder + 1] = key
	return module
end

function Amity:IsModuleEnabled(key)
	return self.db and self.db.modules[key] ~= false
end

function Amity:SetModuleEnabled(key, enabled)
	self.db.modules[key] = enabled and true or false
	if self.UpdatePanel then self:UpdatePanel() end
end

-- True when some module's enabled flag differs from what is running.
function Amity:HasPendingChanges()
	for _, key in ipairs(self.moduleOrder) do
		if (self:IsModuleEnabled(key) and true or false) ~= (self.loaded[key] or false) then
			return true
		end
	end
	return false
end

function Amity:FindModule(name)
	if not name or name == "" then return end
	name = name:lower()
	if self.modules[name] then return self.modules[name] end
	for _, key in ipairs(self.moduleOrder) do
		local module = self.modules[key]
		if module.title:lower():gsub("%s", "") == name:gsub("%s", "") then return module end
		for _, cmd in ipairs(module.slash or {}) do
			if cmd:sub(2) == name then return module end
		end
	end
end

local function RegisterModuleSlash(module)
	if not module.slash or not module.Slash then return end
	local id = "AMITY_" .. module.key:upper()
	for i, cmd in ipairs(module.slash) do
		_G["SLASH_" .. id .. i] = cmd
	end
	SlashCmdList[id] = function(msg)
		if not Amity.loaded[module.key] then
			Amity.Print(module.title .. " is turned off. Enable it in the Amity panel (/amity).")
			return
		end
		module:Slash(msg or "")
	end
end

local function InitModules()
	for _, key in ipairs(Amity.moduleOrder) do
		local module = Amity.modules[key]
		RegisterModuleSlash(module)
		if Amity:IsModuleEnabled(key) then
			local db = Amity.CopyDefaults(module.defaults or {}, Amity.db[key])
			Amity.db[key] = db
			-- one broken module must not take the others down
			local ok = xpcall(function() module:Init(db) end, geterrorhandler())
			Amity.loaded[key] = ok or nil
		end
	end
end

-------------------------------------------------------------------------------
-- Slash command
-------------------------------------------------------------------------------

local function ShowHelp()
	Amity.Print("v" .. Amity.version .. " commands:")
	Amity.Print("  /amity                       - open / close the modules panel")
	Amity.Print("  /amity enable|disable <module>")
	Amity.Print("  /amity minimap               - show / hide the minimap button")
	Amity.Print("  /amity <module> ...          - same as the module's own command")
	for _, key in ipairs(Amity.moduleOrder) do
		local module = Amity.modules[key]
		local cmds = module.slash and table.concat(module.slash, ", ") or ""
		Amity.Print(("  %s %s  |cffaaaaaa%s  (%s)|r"):format(
			Amity.OnOff(Amity.loaded[key]), module.title, cmds, key))
	end
end

SLASH_AMITY1 = "/amity"
SlashCmdList["AMITY"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower()

	if not cmd then
		Amity:TogglePanel()
	elseif cmd == "help" or cmd == "?" or cmd == "list" then
		ShowHelp()
	elseif cmd == "minimap" then
		Amity:SetMinimapButtonShown(Amity.db.minimap.hide)
		Amity.Print("minimap button " .. Amity.OnOff(not Amity.db.minimap.hide))
	elseif cmd == "enable" or cmd == "disable" or cmd == "toggle" then
		local module = Amity:FindModule(rest)
		if not module then
			Amity.Print("unknown module '" .. rest .. "'. /amity help lists them.")
			return
		end
		local v = cmd == "enable" or (cmd == "toggle" and not Amity:IsModuleEnabled(module.key))
		Amity:SetModuleEnabled(module.key, v)
		Amity.Print(module.title .. " " .. Amity.OnOff(v) .. (Amity:HasPendingChanges() and " - /reload to apply" or ""))
	else
		local module = Amity:FindModule(cmd)
		if module and module.slash then
			SlashCmdList["AMITY_" .. module.key:upper()](rest)
		else
			ShowHelp()
		end
	end
end

-- Addon compartment (the addon list button by the minimap), see Amity.toc.
function Amity_OnAddonCompartmentClick()
	Amity:TogglePanel()
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		self:UnregisterEvent("ADDON_LOADED")
		AmityDB = Amity.CopyDefaults({ modules = {}, minimap = {} }, AmityDB)
		Amity.db = AmityDB
		Amity.CopyDefaults({ angle = 225, hide = false }, Amity.db.minimap)
		InitModules()
	elseif event == "PLAYER_LOGIN" then
		Amity:CreateMinimapButton()
		local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
		for _, name in ipairs(LEGACY_ADDONS) do
			if IsLoaded and IsLoaded(name) then
				Amity.Print("|cffff5555" .. name .. " is still enabled.|r Amity already contains it; disable or delete the standalone addon to avoid doubled features.")
			end
		end
	end
end)
