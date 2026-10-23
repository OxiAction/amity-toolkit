--[[
	The modules panel: one checkbox per module plus the minimap button
	option. Module changes need a reload, so a "Reload UI" button lights up
	while the checkboxes differ from what is running.
]]

local _, Amity = ...

local PANEL_WIDTH = 380
local ROW_HEIGHT  = 52
local TOP         = 34

local panel

local function CreateCheck(parent)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	return check
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
	end
	frame:Hide()
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	tinsert(UISpecialFrames, "AmityPanel") -- Escape closes it

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText(Amity.BRAND .. "  |cffaaaaaav" .. Amity.version .. "|r")

	local logo = frame:CreateTexture(nil, "OVERLAY")
	logo:SetSize(18, 18)
	logo:SetPoint("RIGHT", title, "LEFT", -4, 0)
	logo:SetTexture(Amity.ICON)

	frame.rows = {}
	local y = -TOP
	for _, key in ipairs(Amity.moduleOrder) do
		local module = Amity.modules[key]
		local check = CreateCheck(frame)
		check:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
		check:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Amity:SetModuleEnabled(key, self:GetChecked())
		end)

		local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("TOPLEFT", check, "TOPRIGHT", 4, -2)
		name:SetText(module.title)

		local state = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		state:SetPoint("LEFT", name, "RIGHT", 8, 0)

		local notes = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		notes:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
		notes:SetWidth(PANEL_WIDTH - 64)
		notes:SetJustifyH("LEFT")
		local text = module.notes or ""
		if module.slash then
			text = text .. "  |cff888888" .. module.slash[1] .. "|r"
		end
		notes:SetText(text)

		frame.rows[#frame.rows + 1] = { key = key, check = check, state = state }
		y = y - ROW_HEIGHT
	end

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.12)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y + 4)
	divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, y + 4)

	local minimapCheck = CreateCheck(frame)
	minimapCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y - 4)
	minimapCheck:SetScript("OnClick", function(self)
		Amity:SetMinimapButtonShown(self:GetChecked())
	end)
	local minimapLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 4, 0)
	minimapLabel:SetText("Show minimap button  |cff888888(/amity minimap)|r")
	frame.minimapCheck = minimapCheck
	y = y - 34

	local reload = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	reload:SetSize(110, 24)
	reload:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
	reload:SetText(RELOADUI or "Reload UI")
	reload:SetScript("OnClick", function()
		if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
	end)
	frame.reload = reload

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetPoint("RIGHT", reload, "LEFT", -10, 0)
	hint:SetText("Reload to apply module changes")
	frame.hint = hint

	frame:SetSize(PANEL_WIDTH, -y + 52)
	frame:SetScript("OnShow", function() Amity:UpdatePanel() end)
	return frame
end

function Amity:UpdatePanel()
	if not panel or not panel:IsShown() then return end
	for _, row in ipairs(panel.rows) do
		local enabled = self:IsModuleEnabled(row.key)
		local running = self.loaded[row.key] or false
		row.check:SetChecked(enabled)
		if enabled == running then
			row.state:SetText("")
		elseif enabled then
			row.state:SetText("|cffffd100on after reload|r")
		else
			row.state:SetText("|cffffd100off after reload|r")
		end
	end
	panel.minimapCheck:SetChecked(not self.db.minimap.hide)
	local pending = self:HasPendingChanges()
	panel.reload:SetEnabled(pending)
	panel.hint:SetShown(pending)
end

function Amity:TogglePanel()
	panel = panel or CreatePanel()
	panel:SetShown(not panel:IsShown())
end
