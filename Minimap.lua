--[[
	Minimap button: click opens the modules panel, drag moves the button
	around the minimap edge. The angle is saved in AmityDB.minimap.
]]

local _, Amity = ...

local button

local function UpdatePosition()
	local angle = math.rad(Amity.db.minimap.angle or 225)
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Amity.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(Amity.NAME .. " |cffaaaaaav" .. Amity.version .. "|r")
	for _, key in ipairs(Amity.moduleOrder) do
		local on = Amity.loaded[key]
		GameTooltip:AddDoubleLine(Amity.modules[key].title, on and "on" or "off",
			1, 1, 1, on and 0.2 or 1, on and 1 or 0.3, 0.2)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click: modules panel", 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

function Amity:CreateMinimapButton()
	if button then return end

	button = CreateFrame("Button", "AmityMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(21, 21)
	icon:SetPoint("CENTER", button, "CENTER", 0, 1)
	icon:SetTexture(Amity.MINIMAP_ICON)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function() Amity:TogglePanel() end)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	UpdatePosition()
	button:SetShown(not self.db.minimap.hide)
end

function Amity:SetMinimapButtonShown(shown)
	self.db.minimap.hide = not shown
	if button then button:SetShown(shown) end
	if self.UpdatePanel then self:UpdatePanel() end
end
