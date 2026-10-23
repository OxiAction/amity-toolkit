--[[
	Amity Toolkit
	=============
	One addon, several independent modules (Bar Text, Auction Item Level,
	LFG Role Filter, Overpower Alert). Each module lives in Modules\ and
	registers itself with Amity:RegisterModule. On ADDON_LOADED the core
	creates the saved variables and initializes every enabled module.

	There is one slash command, /amity, which opens the panel (same as the
	minimap button). The panel has a tab per module with its enable switch,
	description and settings; modules describe their settings as data
	(module.options) and the panel builds the controls.

	Modules install hooks that cannot be undone at runtime, so switching a
	module on or off takes effect after a UI reload. The panel offers a
	reload button whenever changes are pending.

	Saved variables (AmityDB):
	{
		modules = { [key] = true|false },  -- which modules are enabled
		minimap = { angle = 225, hide = false },
		panel   = { pos = { point, relPoint, x, y }, tab = key, open = true|false },
		[key]   = { ... },                 -- each module's own settings
	}
]]

local ADDON_NAME, Amity = ...

Amity.NAME = "|cff3fe0c5Amity|r Toolkit" -- full name for titles
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
Amity.unavailable = {} -- key -> reason when the module cannot run for this character

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

-------------------------------------------------------------------------------
-- Modules
-------------------------------------------------------------------------------

--[[
	module = {
		title       = "Bar Text",
		notes       = "one line, shown in the overview and tooltips",
		description = "a paragraph for the module's tab",
		defaults    = { ... },              -- module settings (AmityDB[key])
		options     = { option, ... },      -- controls on the module's tab, see below
		Init        = function(self, db),   -- called once at load if enabled
		OnOptionChanged = function(self, optionKey), -- optional, after a control changed a setting
		Unavailable = function(self) -> reason or nil, -- optional, e.g. "Warriors only."
		              -- Modules with this check are initialized at PLAYER_LOGIN (when the
		              -- character's class is known) and never run while it returns a reason.
	}

	option = one of
		{ type = "header",  label = "..." }
		{ type = "toggle",  key = "setting", label = "...", tooltip = "..." }
		{ type = "range",   key = "setting", label = "...", min = 6, max = 20, step = 1,
		                    zero = "Default" }  -- optional: one step below min is 0, shown as this text
		{ type = "select",  key = "setting", label = "...", values = { { value, "text" }, ... } }
		{ type = "button",  label = "..." or function() -> text, tooltip = "...", onClick = function(module) }

	Toggles, ranges and selects read and write AmityDB[key][option.key];
	they can supply get(db) -> value / set(db, value) instead. Every option
	may have disabled = function(module) -> true. Controls are only active
	while the module is running.
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
	self:UpdatePanel()
end

-- True when some module's enabled flag differs from what is running.
-- Modules that cannot run for this character never count as pending.
function Amity:HasPendingChanges()
	for _, key in ipairs(self.moduleOrder) do
		if not self.unavailable[key]
			and (self:IsModuleEnabled(key) and true or false) ~= (self.loaded[key] or false) then
			return true
		end
	end
	return false
end

-- Puts a module's settings back to its defaults.
function Amity:ResetModuleSettings(module)
	local db = self.db[module.key]
	for k, v in pairs(module.defaults or {}) do db[k] = v end
	if module.OnOptionChanged then module:OnOptionChanged(nil) end
	self:UpdatePanel()
end

local function InitModule(key)
	local module = Amity.modules[key]
	if not Amity:IsModuleEnabled(key) then return end
	-- one broken module must not take the others down
	local ok = xpcall(function() module:Init(Amity.db[key]) end, geterrorhandler())
	Amity.loaded[key] = ok or nil
end

-- ADDON_LOADED: settings for every module (so the panel can show them),
-- then every module without an availability check.
local function InitModules()
	for _, key in ipairs(Amity.moduleOrder) do
		local module = Amity.modules[key]
		Amity.db[key] = Amity.CopyDefaults(module.defaults or {}, Amity.db[key])
		if not module.Unavailable then InitModule(key) end
	end
end

-- PLAYER_LOGIN: the modules with an availability check, if they can run.
local function InitLoginModules()
	for _, key in ipairs(Amity.moduleOrder) do
		local module = Amity.modules[key]
		if module.Unavailable then
			Amity.unavailable[key] = module:Unavailable()
			if not Amity.unavailable[key] then InitModule(key) end
		end
	end
end

-------------------------------------------------------------------------------
-- Slash command and addon compartment
-------------------------------------------------------------------------------

SLASH_AMITY1 = "/amity"
SlashCmdList["AMITY"] = function()
	Amity:TogglePanel()
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
		AmityDB = Amity.CopyDefaults({ modules = {}, minimap = {}, panel = {} }, AmityDB)
		Amity.db = AmityDB
		Amity.CopyDefaults({ angle = 225, hide = false }, Amity.db.minimap)
		InitModules()
	elseif event == "PLAYER_LOGIN" then
		InitLoginModules()
		Amity:CreateMinimapButton()
		Amity:RestorePanel()
	end
end)
