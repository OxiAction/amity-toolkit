--[[
	The Amity panel, opened by /amity, the minimap button or the addon
	compartment. A tab list on the left: "Overview" (all modules, minimap
	button option) and one tab per module with its enable switch,
	description and settings. The settings controls are built from
	module.options (see Core.lua), so a new module needs no panel code.

	The panel can be dragged by any empty spot and remembers its position,
	its last tab and whether it was open, so after a /reload it comes back
	exactly as it was. It stays open until closed (Escape does not close
	it), so it can sit next to whatever is being tested.

	Module changes need a reload, so a "Reload UI" button lights up while
	an enable switch differs from what is running.

	Layout rule: nothing may overflow the panel. Every widget gets the width
	that is left for it; text wraps (or truncates, for one-line titles) and
	row heights are measured from the wrapped text. Buttons size to their
	text but never exceed the row and wrap to a new row when full. The tab
	list and every page sit in scroll areas, so any amount of content fits.
]]

local _, Amity = ...

local PANEL_WIDTH   = 630
local PANEL_HEIGHT  = 440
local NAV_WIDTH     = 180
local NAV_ROW       = 24
local TOP           = 34   -- below the title bar
local BOTTOM        = 44   -- above the reload bar
local SCROLLBAR     = 26   -- room kept free on the right of a scroll area for its bar
local CONTENT_LEFT  = NAV_WIDTH + 22
local INNER_WIDTH   = PANEL_WIDTH - CONTENT_LEFT - 18 - SCROLLBAR -- usable page width
local ROW           = 28   -- minimum height of one settings row
local CHECK         = 24   -- check button size
local OVERVIEW      = "overview"

local panel
local loggingOut = false

local logout = CreateFrame("Frame")
logout:RegisterEvent("PLAYER_LOGOUT")
logout:SetScript("OnEvent", function() loggingOut = true end)

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function SetTooltip(widget, title, text)
	if not text then return end
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		GameTooltip:AddLine(text, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function SetLabelEnabled(fs, enabled)
	if enabled then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.5, 0.5, 0.5) end
end

-- Wrapping text of a fixed width; returns the font string and its height.
local function CreateText(parent, font, width, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetText(text or "")
	return fs, fs:GetStringHeight()
end

-- One line that truncates instead of growing past width.
local function CreateLine(parent, font, width, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	fs:SetText(text or "")
	return fs
end

local function CreateCheck(parent)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(CHECK, CHECK)
	return check
end

-- A button as wide as its text (at least minWidth), but never wider than maxWidth.
local function CreateButton(parent, text, minWidth, maxWidth)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetHeight(22)
	button:SetText(text)
	local fs = button:GetFontString()
	local width = math.max(minWidth or 0, (fs and fs:GetStringWidth() or 0) + 28)
	if maxWidth then width = math.min(width, maxWidth) end
	button:SetWidth(width)
	if fs then fs:SetWidth(width - 16); fs:SetWordWrap(false) end
	return button
end

local function CreateDivider(parent, y)
	local divider = parent:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.12)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	divider:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
	return divider
end

-- A vertical scroll area inside the panel. Returns the scroll frame and the
-- child to build on; call scroll:SetContentHeight(h) once the content is built.
--
-- The scrollbar is drawn and driven by hand (no Slider, no template), so it
-- behaves the same on every client: drag the thumb, click the track above or
-- below it to move a page, or use the mouse wheel. It sits in the SCROLLBAR
-- space right of the area and only shows while the content does not fit.
local SCROLL_STEP = 40
local BAR_WIDTH   = 16 -- clickable width; the drawn bar is thinner
local BAR_LINE    = 6

local function CursorY(frame)
	local _, y = GetCursorPosition()
	return y / frame:GetEffectiveScale()
end

local function CreateScrollArea(left, top, right, bottom, width)
	local scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", left, top)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", right, bottom)
	if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, 1)
	scroll:SetScrollChild(child)
	scroll.child = child

	-- The bar sits outside the scroll area, which clips its children, so it
	-- belongs to the panel and follows the area's visibility by hand. It
	-- takes the mouse, so clicks on it never start dragging the panel.
	local bar = CreateFrame("Frame", nil, panel)
	bar:SetFrameLevel(scroll:GetFrameLevel() + 2)
	bar:SetWidth(BAR_WIDTH)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", (SCROLLBAR - BAR_WIDTH) / 2, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", (SCROLLBAR - BAR_WIDTH) / 2, 0)
	bar:EnableMouse(true)
	bar:EnableMouseWheel(true)
	bar:Hide()

	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetWidth(BAR_LINE)
	track:SetPoint("TOP", bar, "TOP", 0, 0)
	track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
	track:SetColorTexture(0, 0, 0, 0.45)

	local thumb = CreateFrame("Frame", nil, bar)
	thumb:SetWidth(BAR_WIDTH)
	thumb:EnableMouse(true)
	local thumbLine = thumb:CreateTexture(nil, "OVERLAY")
	thumbLine:SetWidth(BAR_LINE)
	thumbLine:SetPoint("TOP", thumb, "TOP", 0, 0)
	thumbLine:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
	thumbLine:SetColorTexture(0.25, 0.88, 0.77, 0.7)

	local offset, range = 0, 0

	local function PlaceThumb()
		local travel = bar:GetHeight() - thumb:GetHeight()
		local y = range > 0 and travel * offset / range or 0
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -y)
	end

	local function SetOffset(value)
		offset = math.max(0, math.min(range, value))
		scroll:SetVerticalScroll(offset)
		PlaceThumb()
	end

	-- Pages are built while hidden, when their size is not known yet, so the
	-- bar is measured again whenever the area is shown, and once more on the
	-- next frame when the layout has settled.
	local function UpdateBar()
		local visible = scroll:GetHeight()
		range = math.max(0, child:GetHeight() - visible)
		if not scroll:IsShown() or visible <= 0 or range < 1 then
			range = 0
			bar:Hide()
			SetOffset(0)
			return
		end
		-- thumb length follows the visible share of the content
		thumb:SetHeight(math.max(24, bar:GetHeight() * visible / (visible + range)))
		bar:Show()
		SetOffset(offset)
	end
	scroll:SetScript("OnSizeChanged", UpdateBar)
	scroll:SetScript("OnShow", function()
		UpdateBar()
		C_Timer.After(0, UpdateBar)
	end)
	scroll:SetScript("OnHide", function() bar:Hide() end)

	-- dragging the thumb: the content follows the cursor 1:1 from the grab point
	thumb:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local startY, startOffset = CursorY(bar), offset
		local travel = bar:GetHeight() - self:GetHeight()
		self:SetScript("OnUpdate", function()
			if not IsMouseButtonDown("LeftButton") then
				self:SetScript("OnUpdate", nil)
				return
			end
			if travel > 0 then
				SetOffset(startOffset + (startY - CursorY(bar)) * range / travel)
			end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function() thumbLine:SetColorTexture(0.25, 0.88, 0.77, 1) end)
	thumb:SetScript("OnLeave", function() thumbLine:SetColorTexture(0.25, 0.88, 0.77, 0.7) end)

	-- clicking the track moves one page towards the click
	bar:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local page = scroll:GetHeight() - SCROLL_STEP
		if CursorY(bar) > thumb:GetBottom() then
			SetOffset(offset - page)
		else
			SetOffset(offset + page)
		end
	end)

	local function OnWheel(_, delta)
		if range > 0 then SetOffset(offset - delta * SCROLL_STEP) end
	end
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", OnWheel)
	bar:SetScript("OnMouseWheel", OnWheel)

	function scroll:SetContentHeight(h)
		child:SetHeight(math.max(1, h))
		UpdateBar()
	end
	return scroll, child
end

-- "on", "off", "on after reload", "off after reload", "inactive ...", coloured
local function ModuleState(key)
	if Amity.unavailable[key] then
		return "|cff888888inactive on this character|r"
	end
	local enabled = Amity:IsModuleEnabled(key)
	local running = Amity.loaded[key] or false
	if enabled == running then
		return running and "|cff33ff33on|r" or "|cff888888off|r"
	end
	return enabled and "|cffffd100on after reload|r" or "|cffffd100off after reload|r"
end

-------------------------------------------------------------------------------
-- Settings controls, built from module.options
-------------------------------------------------------------------------------

local function GetValue(module, opt)
	local db = Amity.db[module.key]
	if opt.get then return opt.get(db) end
	return db[opt.key]
end

local function SetValue(module, opt, value)
	local db = Amity.db[module.key]
	if opt.set then
		opt.set(db, value)
	else
		db[opt.key] = value
	end
	if module.OnOptionChanged then module:OnOptionChanged(opt.key) end
	Amity:UpdatePanel()
end

local function IsActive(module, opt)
	if not Amity.loaded[module.key] then return false end
	if module.Unavailable and module:Unavailable() then return false end
	if opt.disabled and opt.disabled(module) then return false end
	return true
end

local function ButtonText(opt)
	if type(opt.label) == "function" then return opt.label() end
	return opt.label
end

-- Each builder places its widgets at y on the page, within width, and
-- returns a control { height, Refresh }. Buttons are placed by the layout
-- loop instead and return { widget, width, height, Refresh }.
local builders = {}

function builders.header(page, module, opt, y, width)
	local text, h = CreateText(page, "GameFontNormal", width, opt.label)
	text:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 8)
	return { height = h + 14, Refresh = function() end }
end

function builders.toggle(page, module, opt, y, width)
	local check = CreateCheck(page)
	check:SetPoint("TOPLEFT", page, "TOPLEFT", -4, y)
	local label, h = CreateText(page, "GameFontHighlight", width - CHECK, opt.label)
	label:SetPoint("TOPLEFT", page, "TOPLEFT", CHECK - 2, y - 6)
	check:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SetValue(module, opt, self:GetChecked() and true or false)
	end)
	SetTooltip(check, opt.label, opt.tooltip)
	return {
		height = math.max(ROW, h + 12),
		Refresh = function()
			local active = IsActive(module, opt)
			check:SetChecked(GetValue(module, opt) and true or false)
			check:SetEnabled(active)
			SetLabelEnabled(label, active)
		end,
	}
end

function builders.range(page, module, opt, y, width)
	-- [-] value [+] on the right, the label wraps in the space left of it
	local STEPPER = 24 + 64 + 24
	local label, h = CreateText(page, "GameFontHighlight", width - STEPPER - 8, opt.label)
	label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 6)

	local minus = CreateButton(page, "-", 24, 24)
	minus:SetPoint("TOPLEFT", page, "TOPLEFT", width - STEPPER, y - 1)
	local value = CreateLine(page, "GameFontHighlight", 64)
	value:SetJustifyH("CENTER")
	value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
	local plus = CreateButton(page, "+", 24, 24)
	plus:SetPoint("LEFT", value, "RIGHT", 0, 0)

	local step = opt.step or 1
	local function Step(dir)
		local v = GetValue(module, opt) or opt.min
		if opt.zero and v == 0 then
			v = dir > 0 and opt.min or 0
		elseif opt.zero and dir < 0 and v <= opt.min then
			v = 0
		else
			v = math.max(opt.min, math.min(opt.max, v + dir * step))
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SetValue(module, opt, v)
	end
	minus:SetScript("OnClick", function() Step(-1) end)
	plus:SetScript("OnClick", function() Step(1) end)
	SetTooltip(minus, opt.label, opt.tooltip)
	SetTooltip(plus, opt.label, opt.tooltip)

	return {
		height = math.max(ROW, h + 12),
		Refresh = function()
			local active = IsActive(module, opt)
			local v = GetValue(module, opt)
			value:SetText((opt.zero and v == 0) and opt.zero or tostring(v))
			local low = opt.zero and 0 or opt.min
			minus:SetEnabled(active and v > low)
			plus:SetEnabled(active and v < opt.max)
			SetLabelEnabled(label, active)
			SetLabelEnabled(value, active)
		end,
	}
end

-- The label on its own line, then one choice per line below it.
function builders.select(page, module, opt, y, width)
	local label, h = CreateText(page, "GameFontHighlight", width, opt.label)
	label:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y - 6)
	local height = h + 10

	local INDENT = 12
	local choices = {}
	for _, entry in ipairs(opt.values) do
		local check = CreateCheck(page)
		check:SetPoint("TOPLEFT", page, "TOPLEFT", INDENT - 4, y - height)
		local text, th = CreateText(page, "GameFontHighlight", width - INDENT - CHECK, entry[2])
		text:SetPoint("TOPLEFT", page, "TOPLEFT", INDENT + CHECK - 2, y - height - 6)
		check:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			SetValue(module, opt, entry[1])
		end)
		SetTooltip(check, entry[2], opt.tooltip)
		choices[#choices + 1] = { value = entry[1], check = check, text = text }
		height = height + math.max(CHECK + 2, th + 12)
	end

	return {
		height = height + 4,
		Refresh = function()
			local active = IsActive(module, opt)
			local current = GetValue(module, opt)
			for _, c in ipairs(choices) do
				c.check:SetChecked(c.value == current)
				c.check:SetEnabled(active)
				SetLabelEnabled(c.text, active)
			end
			SetLabelEnabled(label, active)
		end,
	}
end

function builders.button(page, module, opt, y, width)
	local button = CreateButton(page, ButtonText(opt), opt.width or 120, width)
	button:SetScript("OnClick", function()
		opt.onClick(module)
		Amity:UpdatePanel()
	end)
	SetTooltip(button, ButtonText(opt), opt.tooltip)
	return {
		widget = button,
		width = button:GetWidth(),
		height = ROW,
		Refresh = function()
			button:SetText(ButtonText(opt))
			button:SetEnabled(IsActive(module, opt))
		end,
	}
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------

local function CreatePage()
	local page = CreateScrollArea(CONTENT_LEFT, -TOP, -18 - SCROLLBAR, BOTTOM, INNER_WIDTH)
	page.controls = {}
	page:Hide()
	return page, page.child
end

-- Lays out module.options top to bottom from y; returns the new y.
local function LayoutOptions(page, child, module, y)
	local x = 0 -- buttons flow left to right, everything else takes a full row
	for _, opt in ipairs(module.options) do
		if opt.type ~= "button" and x > 0 then
			x = 0
			y = y - ROW
		end
		local control = builders[opt.type](child, module, opt, y, INNER_WIDTH)
		page.controls[#page.controls + 1] = control
		if opt.type == "button" then
			if x > 0 and x + control.width > INNER_WIDTH then
				x = 0
				y = y - ROW
			end
			control.widget:SetPoint("TOPLEFT", child, "TOPLEFT", x, y - 2)
			x = x + control.width + 8
		else
			y = y - control.height
		end
	end
	if x > 0 then y = y - ROW end
	return y
end

local function BuildModulePage(module)
	local page, child = CreatePage()
	local key = module.key

	-- "[x] Enabled" in the top right, the title truncates before it
	local enable = CreateCheck(child)
	enable:SetPoint("TOPRIGHT", child, "TOPRIGHT", -60, 4)
	local enableLabel = CreateLine(child, "GameFontHighlight", 58, "Enabled")
	enableLabel:SetPoint("LEFT", enable, "RIGHT", 2, 0)
	enable:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Amity:SetModuleEnabled(key, self:GetChecked())
	end)
	SetTooltip(enable, "Enabled", "Switching a module on or off takes effect after a UI reload.")

	local title = CreateLine(child, "GameFontNormalLarge", INNER_WIDTH - 96, module.title)
	title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
	local y = -title:GetStringHeight() - 4

	local state = CreateLine(child, "GameFontHighlightSmall", INNER_WIDTH)
	state:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
	y = y - 14 - 10

	local desc, dh = CreateText(child, "GameFontHighlight", INNER_WIDTH, module.description or module.notes)
	desc:SetSpacing(2)
	dh = desc:GetStringHeight()
	desc:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
	y = y - dh - 8

	-- The note changes at runtime; reserve room for the longest text it can show.
	local reason = module.Unavailable and module:Unavailable()
	local OFF_NOTE = "Settings can be changed while the module is running."
	local note = CreateText(child, "GameFontNormalSmall", INNER_WIDTH, reason or OFF_NOTE)
	local nh = note:GetStringHeight()
	if reason then
		note:SetText(OFF_NOTE)
		nh = math.max(nh, note:GetStringHeight())
	end
	note:SetHeight(nh)
	note:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
	y = y - nh - 8

	if module.options and #module.options > 0 then
		CreateDivider(child, y)
		y = LayoutOptions(page, child, module, y - 8)
	end
	page:SetContentHeight(-y + 8)

	page.Refresh = function()
		enable:SetChecked(Amity:IsModuleEnabled(key))
		state:SetText(ModuleState(key))
		local unavailable = module.Unavailable and module:Unavailable()
		if unavailable then
			note:SetText("|cffff5555" .. unavailable .. "|r")
		elseif not Amity.loaded[key] and module.options and #module.options > 0 then
			note:SetText(OFF_NOTE)
		else
			note:SetText("")
		end
		for _, control in ipairs(page.controls) do control.Refresh() end
	end
	return page
end

local function BuildOverviewPage()
	local page, child = CreatePage()

	local title = CreateLine(child, "GameFontNormalLarge", INNER_WIDTH, "Overview")
	title:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
	local y = -title:GetStringHeight() - 10

	local intro, ih = CreateText(child, "GameFontHighlight", INNER_WIDTH,
		"Pick a module on the left to switch it on or off and change its settings.")
	intro:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
	y = y - ih - 12

	local rows = {}
	for _, key in ipairs(Amity.moduleOrder) do
		local module = Amity.modules[key]
		local row = CreateFrame("Button", nil, child)
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:SetScript("OnClick", function() Amity:SelectPanelTab(key) end)

		-- title, with the state right after it in the space that is left
		local STATE_WIDTH = 110
		local name = CreateLine(row, "GameFontNormal", INNER_WIDTH - 8 - STATE_WIDTH - 8, module.title)
		name:SetWidth(math.min(name:GetStringWidth() + 2, INNER_WIDTH - 8 - STATE_WIDTH - 8))
		name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
		local state = CreateLine(row, "GameFontHighlightSmall", STATE_WIDTH)
		state:SetPoint("LEFT", name, "RIGHT", 8, 0)
		local notes, nh = CreateText(row, "GameFontHighlightSmall", INNER_WIDTH - 8, module.notes)
		notes:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)

		local height = 4 + name:GetStringHeight() + 3 + nh + 6
		row:SetSize(INNER_WIDTH, height)
		rows[#rows + 1] = { key = key, state = state }
		y = y - height - 4
	end

	CreateDivider(child, y - 4)
	local minimapCheck = CreateCheck(child)
	minimapCheck:SetPoint("TOPLEFT", child, "TOPLEFT", -4, y - 10)
	minimapCheck:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Amity:SetMinimapButtonShown(self:GetChecked())
	end)
	local minimapLabel = CreateText(child, "GameFontHighlight", INNER_WIDTH - CHECK, "Show minimap button")
	minimapLabel:SetPoint("TOPLEFT", child, "TOPLEFT", CHECK - 2, y - 16)
	SetTooltip(minimapCheck, "Show minimap button", "Without it, open this panel with /amity or the addon compartment.")
	y = y - 10 - ROW - 8

	local hint, hh = CreateText(child, "GameFontDisableSmall", INNER_WIDTH,
		"Drag the panel to move it. It stays open while you play; close it with the X, /amity or the minimap button.")
	hint:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
	y = y - hh
	page:SetContentHeight(-y + 8)

	page.Refresh = function()
		for _, row in ipairs(rows) do row.state:SetText(ModuleState(row.key)) end
		minimapCheck:SetChecked(not Amity.db.minimap.hide)
	end
	return page
end

-------------------------------------------------------------------------------
-- Navigation
-------------------------------------------------------------------------------

local NAV_BUTTON_WIDTH = NAV_WIDTH - 4 - SCROLLBAR

-- Returns the button and its height; long names wrap onto more lines.
local function CreateNavButton(parent, key, text, y)
	local button = CreateFrame("Button", nil, parent)
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
	button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	button.selected = button:CreateTexture(nil, "BACKGROUND")
	button.selected:SetAllPoints()
	button.selected:SetColorTexture(0.25, 0.88, 0.77, 0.18)
	button.selected:Hide()

	-- module tabs: a small dot for running / off; the label wraps before it
	local labelHeight
	button.label, labelHeight = CreateText(button, "GameFontNormal", NAV_BUTTON_WIDTH - 8 - 16, text)
	button.label:SetPoint("LEFT", button, "LEFT", 8, 0)
	local height = math.max(NAV_ROW - 2, labelHeight + 8)
	button:SetSize(NAV_BUTTON_WIDTH, height)

	button.dot = button:CreateTexture(nil, "OVERLAY")
	button.dot:SetSize(6, 6)
	button.dot:SetPoint("RIGHT", button, "RIGHT", -6, 0)
	button.dot:SetColorTexture(1, 1, 1, 1)
	button.dot:SetShown(key ~= OVERVIEW)

	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Amity:SelectPanelTab(key)
	end)
	button.key = key
	return button, height
end

function Amity:SelectPanelTab(key)
	if key ~= OVERVIEW and not self.modules[key] then key = OVERVIEW end
	self.db.panel.tab = key
	if not panel.pages[key] then
		panel.pages[key] = key == OVERVIEW and BuildOverviewPage() or BuildModulePage(self.modules[key])
	end
	for k, page in pairs(panel.pages) do page:SetShown(k == key) end
	panel.current = key
	self:UpdatePanel()
end

-------------------------------------------------------------------------------
-- The frame
-------------------------------------------------------------------------------

local function SavePosition(frame)
	frame:StopMovingOrSizing()
	frame:SetUserPlaced(false) -- position lives in AmityDB, not the layout cache
	local point, _, relPoint, x, y = frame:GetPoint()
	Amity.db.panel.pos = { point, relPoint, x, y }
end

local function CreatePanel()
	local ok, frame = pcall(CreateFrame, "Frame", "AmityPanel", UIParent, "BasicFrameTemplateWithInset")
	if not ok then
		frame = CreateFrame("Frame", "AmityPanel", UIParent, "BackdropTemplate")
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 8, right = 8, top = 8, bottom = 8 },
		})
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	end
	panel = frame
	frame:Hide()
	frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", SavePosition)

	local pos = Amity.db.panel.pos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	end

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText(Amity.NAME .. "  |cffaaaaaav" .. Amity.version .. "|r")

	local logo = frame:CreateTexture(nil, "OVERLAY")
	logo:SetSize(18, 18)
	logo:SetPoint("RIGHT", title, "LEFT", -4, 0)
	logo:SetTexture(Amity.ICON)

	-- tab list
	local nav, navChild = CreateScrollArea(10, -TOP, -(PANEL_WIDTH - 10 - NAV_BUTTON_WIDTH), BOTTOM, NAV_BUTTON_WIDTH)
	frame.nav = {}
	local y = 0
	local button, height = CreateNavButton(navChild, OVERVIEW, "Overview", y)
	frame.nav[1] = button
	y = y - height - 8
	for _, key in ipairs(Amity.moduleOrder) do
		button, height = CreateNavButton(navChild, key, Amity.modules[key].title, y)
		frame.nav[#frame.nav + 1] = button
		y = y - height - 2
	end
	nav:SetContentHeight(-y)

	local navLine = frame:CreateTexture(nil, "ARTWORK")
	navLine:SetColorTexture(1, 1, 1, 0.12)
	navLine:SetWidth(1)
	navLine:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_WIDTH + 8, -TOP + 2)
	navLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", NAV_WIDTH + 8, BOTTOM - 4)

	-- reload bar
	local reload = CreateButton(frame, RELOADUI or "Reload UI", 110, 160)
	reload:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
	reload:SetScript("OnClick", function()
		if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
	end)
	frame.reload = reload

	local hint = CreateLine(frame, "GameFontNormalSmall", PANEL_WIDTH - 14 - reload:GetWidth() - 10 - 14)
	hint:SetJustifyH("RIGHT")
	hint:SetPoint("RIGHT", reload, "LEFT", -10, 0)
	hint:SetText("Reload to apply module changes")
	frame.hint = hint

	frame.pages = {}
	frame:SetScript("OnShow", function()
		Amity.db.panel.open = true
		Amity:UpdatePanel()
	end)
	frame:SetScript("OnHide", function()
		-- the UI being torn down on logout / reload is not the user closing it
		if not loggingOut then Amity.db.panel.open = false end
	end)
	return frame
end

function Amity:UpdatePanel()
	if not panel or not panel:IsShown() then return end
	for _, button in ipairs(panel.nav) do
		local selected = button.key == panel.current
		button.selected:SetShown(selected)
		if selected then
			button.label:SetTextColor(1, 1, 1)
		else
			button.label:SetTextColor(1, 0.82, 0)
		end
		if button.key ~= OVERVIEW then
			local running = self.loaded[button.key]
			if self.unavailable[button.key] then
				button.dot:SetVertexColor(0.4, 0.4, 0.4)
			elseif self:IsModuleEnabled(button.key) ~= (running or false) then
				button.dot:SetVertexColor(1, 0.82, 0)
			elseif running then
				button.dot:SetVertexColor(0.2, 1, 0.2)
			else
				button.dot:SetVertexColor(0.4, 0.4, 0.4)
			end
		end
	end
	local page = panel.pages[panel.current]
	if page then page.Refresh() end
	local pending = self:HasPendingChanges()
	panel.reload:SetEnabled(pending)
	panel.hint:SetShown(pending)
end

-- At login: reopen the panel if it was open when the UI was last unloaded.
function Amity:RestorePanel()
	if self.db.panel.open and not (panel and panel:IsShown()) then
		self:TogglePanel()
	end
end

function Amity:TogglePanel()
	if not panel then
		CreatePanel()
		panel:Show()
		self:SelectPanelTab(self.db.panel.tab or OVERVIEW)
		return
	end
	panel:SetShown(not panel:IsShown())
end
