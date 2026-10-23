--[[
	Amity module: Auction Item Level (formerly the AuctionItemLevel addon)
	======================================================================
	Adds an "iLvl" column to the auction house browse results (the list you get
	after searching / picking a category). Clicking the column header sorts the
	results by item level; clicking again reverses the order.

	How it works
	------------
	* The browse list is built by AuctionHouseTableBuilder.GetBrowseListLayout.
	  We replace that function with our own copy that inserts an item level
	  column before the quantity. For weapons / armor, which got a "Level"
	  (required level) column in patch 1.60.1, both columns are shown.
	* Since 1.60.1 the server's "Level" sort means required level, so the iLvl
	  header sorts the received results on the client instead. Its header uses
	  Blizzard's header template with our own owner object, so the arrow works
	  like the other headers. Clicking a Blizzard header ends the iLvl sort.
	* The item level comes from the item key or the item cache
	  (C_Item.GetDetailedItemLevelInfo / GetItemInfo).
	* Nothing is written into Blizzard's frames apart from re-ordering the
	  result array, and the auction house exposes no secret values, so the
	  taint concerns that apply to unit frames do not apply here.
]]

local _, Amity = ...

local defaults = {
	equipmentOnly = true,  -- show item level only for armor / weapons (others show blank)
}

local M = Amity:RegisterModule("auctionilvl", {
	title    = "Auction Item Level",
	notes    = "Adds a sortable iLvl column to the auction house browse results.",
	defaults = defaults,
	slash    = { "/ail", "/auctionitemlevel" },
})

local db -- AmityDB.auctionilvl

local function Print(msg) Amity.Print(msg, M.title) end

-------------------------------------------------------------------------------
-- Item level lookup (cached, with async loading)
-------------------------------------------------------------------------------

local ilvlCache = {}      -- itemID -> item level (number) once known
local pendingItems = {}   -- itemID -> true while waiting for item data

local function GetItemLevel(itemKey)
	if not itemKey then return nil end

	-- Auction data may carry an explicit item level (scaled items); prefer it.
	if itemKey.itemLevel and itemKey.itemLevel > 0 then
		return itemKey.itemLevel
	end

	local itemID = itemKey.itemID
	if not itemID then return nil end

	local cached = ilvlCache[itemID]
	if cached then return cached end

	local ilvl
	if C_Item.GetDetailedItemLevelInfo then
		ilvl = C_Item.GetDetailedItemLevelInfo(itemID)
	end
	if not ilvl then
		ilvl = select(4, C_Item.GetItemInfo(itemID))
	end

	if ilvl then
		ilvlCache[itemID] = ilvl
		pendingItems[itemID] = nil
		return ilvl
	end

	-- Not in the item cache yet; ask for it and wait for GET_ITEM_INFO_RECEIVED.
	if not pendingItems[itemID] then
		pendingItems[itemID] = true
		if C_Item.RequestLoadItemDataByID then
			C_Item.RequestLoadItemDataByID(itemID)
		end
	end
	return nil
end

local function IsEquipment(itemKey)
	local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
	if info then
		return info.isEquipment
	end
	-- Fall back on the item class if the key info is not available yet.
	local classID = select(6, C_Item.GetItemInfoInstant(itemKey.itemID))
	return classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor
end

-- Value used for sorting: equipment (or everything, per option) by item level,
-- unknown / hidden values sort as 0.
local function GetSortValue(browseResult)
	local itemKey = browseResult and browseResult.itemKey
	if not itemKey then return 0 end
	if db.equipmentOnly and not IsEquipment(itemKey) then return 0 end
	return GetItemLevel(itemKey) or 0
end

-------------------------------------------------------------------------------
-- Table cell
-------------------------------------------------------------------------------

-- Derive from Blizzard's base cell mixin: rows call OnLineEnter / OnLineLeave
-- on every cell when hovered, so those (empty) methods must exist.
AmityAuctionItemLevelCellMixin = CreateFromMixins(TableBuilderCellMixin or {})

if not AmityAuctionItemLevelCellMixin.OnLineEnter then
	function AmityAuctionItemLevelCellMixin:OnLineEnter() end
	function AmityAuctionItemLevelCellMixin:OnLineLeave() end
end

function AmityAuctionItemLevelCellMixin:Init(owner)
	self.owner = owner
	self.Text:SetFontObject(Number14FontWhite or NumberFontNormal or GameFontHighlight)
	self.Text:SetJustifyH("LEFT")
end

function AmityAuctionItemLevelCellMixin:Populate(rowData, dataIndex)
	self.rowData = rowData
	self:UpdateDisplay()
end

function AmityAuctionItemLevelCellMixin:UpdateDisplay()
	local itemKey = self.rowData and self.rowData.itemKey
	if not itemKey or (db.equipmentOnly and not IsEquipment(itemKey)) then
		self.Text:SetText("")
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		return
	end

	local ilvl = GetItemLevel(itemKey)
	if not ilvl then
		self.Text:SetText("")
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		return
	end
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")

	-- Match Blizzard's sell list: colour the number by item quality.
	local r, g, b = 1, 1, 1
	local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
	if info and ColorManager and ColorManager.GetColorDataForItemQuality then
		local colorData = ColorManager.GetColorDataForItemQuality(info.quality)
		if colorData then r, g, b = colorData.color:GetRGB() end
	end
	self.Text:SetTextColor(r, g, b)
	self.Text:SetText(ilvl)
end

function AmityAuctionItemLevelCellMixin:OnEvent(event, itemID)
	if event == "GET_ITEM_INFO_RECEIVED" then
		if self.rowData and self.rowData.itemKey and self.rowData.itemKey.itemID == itemID then
			self:UpdateDisplay()
		end
	end
end

function AmityAuctionItemLevelCellMixin:OnHide()
	self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
end

-------------------------------------------------------------------------------
-- Client-side item level sort
-------------------------------------------------------------------------------

-- The iLvl column sorts on the client only. Since patch 1.60.1 the server's
-- "Level" sort (and Blizzard's "Level" column on weapons / armor) means the
-- required level, so the column cannot share that sort order any more.
local ilvlSort = nil -- nil = inactive, "asc" or "desc"

-- Stable sort of the browse results by item level; ties keep the server order.
-- Items without a (shown) item level always go to the bottom.
local function SortBrowseResults(browseFrame)
	if not ilvlSort then return false end
	local results = browseFrame.browseResults
	if not results or #results < 2 then return false end

	local keyed = {}
	for i, result in ipairs(results) do
		keyed[i] = { value = GetSortValue(result), index = i, result = result }
	end

	local descending = ilvlSort == "desc"
	table.sort(keyed, function(a, b)
		if a.value ~= b.value then
			if a.value == 0 then return false end
			if b.value == 0 then return true end
			if descending then return a.value > b.value end
			return a.value < b.value
		end
		return a.index < b.index
	end)

	local changed = false
	for i, entry in ipairs(keyed) do
		if results[i] ~= entry.result then
			changed = true
		end
		results[i] = entry.result
	end
	return changed
end

local function ResortAndRefresh(browseFrame)
	if SortBrowseResults(browseFrame) then
		browseFrame.ItemList:DirtyScrollFrame()
	end
end

-- Owner object for the iLvl column header. AuctionHouseTableHeaderStringMixin
-- only calls owner:RegisterHeader / SetSortOrder / GetSortOrderState, so giving
-- the header this owner instead of the browse frame lets it use Blizzard's
-- header button (arrow, highlight) without touching the server sort.
local ILVL_SORT_ORDER = "AuctionItemLevel"
local ilvlHeaderOwner = {}

-- While the item level sort is active, hide the arrows of Blizzard's headers
-- (their sort still applies server side, but it is not what the list shows).
local function UpdateBlizzardArrows(browseFrame)
	if not ilvlSort or not browseFrame.headers then return end
	for _, header in ipairs(browseFrame.headers) do
		if header.owner == browseFrame and header.Arrow then
			header.Arrow:Hide()
		end
	end
end

function ilvlHeaderOwner:RegisterHeader(header)
	self.header = header
end

function ilvlHeaderOwner:GetSortOrderState()
	if ilvlSort == "asc" then
		return AuctionHouseSortOrderState.PrimarySorted
	elseif ilvlSort == "desc" then
		return AuctionHouseSortOrderState.PrimaryReversed
	end
	return AuctionHouseSortOrderState.None
end

function ilvlHeaderOwner:UpdateArrow()
	-- Headers are pooled; only touch ours while it still belongs to us.
	local header = self.header
	if header and header.owner == self then
		header:UpdateArrow()
	end
end

function ilvlHeaderOwner:SetSortOrder()
	-- First click sorts highest first, further clicks toggle.
	ilvlSort = (ilvlSort == "desc") and "asc" or "desc"

	local browseFrame = AuctionHouseFrame.BrowseResultsFrame
	UpdateBlizzardArrows(browseFrame)
	if SortBrowseResults(browseFrame) then
		browseFrame.ItemList:RefreshScrollFrame()
	end
end

-------------------------------------------------------------------------------
-- Browse list layout with the extra column
-------------------------------------------------------------------------------

-- Mirrors AuctionHouseTableBuilder.GetBrowseListLayout from Blizzard_AuctionHouseUI,
-- with an item level column inserted after the name / detail column. Padding
-- constants are file-local in Blizzard's code, so they are repeated here.
local PRICE_DISPLAY_PADDING = 0
local STANDARD_PADDING = 10
local ITEM_LEVEL_COLUMN_WIDTH = 50

-- Set from the auction house's CategorySelected callback.
local equipmentCategorySelected = false

local function ShouldShowItemLevelColumn(extraInfoColumnText)
	if not extraInfoColumnText then
		return true -- plain search / favorites
	end
	-- Weapons and armor carry a required level column since 1.60.1; show item
	-- level next to it. Other categories with a detail column (consumables,
	-- containers, recipes) are not equipment, so item level is meaningless there.
	return equipmentCategorySelected
end

local function AddItemLevelColumn(tableBuilder, owner)
	local column = tableBuilder:AddColumn()
	column:ConstructHeader("BUTTON", "AuctionHouseTableHeaderStringTemplate", ilvlHeaderOwner,
		ITEM_LEVEL_ABBR or "iLvl", ILVL_SORT_ORDER)
	column:ConstructCells("FRAME", "AmityAuctionItemLevelCellTemplate", owner)
	column:SetFixedConstraints(ITEM_LEVEL_COLUMN_WIDTH, 0)
	column:SetCellPadding(STANDARD_PADDING, 0)
	return column
end

local function GetBrowseListLayoutWithItemLevel(owner, itemList, extraInfoColumnText)
	local showItemLevel = ShouldShowItemLevelColumn(extraInfoColumnText)

	local function Layout(tableBuilder)
		tableBuilder:SetColumnHeaderOverlap(2)
		tableBuilder:SetHeaderContainer(itemList:GetHeaderContainer())

		local priceWidth = 146
		local quantityWidth = 83
		if C_AuctionHouse.SupportsCopperValues and C_AuctionHouse.SupportsCopperValues() then
			priceWidth = 168
			quantityWidth = 60
		end

		tableBuilder:AddFixedWidthColumn(owner, PRICE_DISPLAY_PADDING, priceWidth, 0, 14,
			Enum.AuctionHouseSortOrder.Price, "AuctionHouseTableCellMinPriceTemplate")

		local restrictQualityToFilter = true
		local hideItemLevel = showItemLevel or extraInfoColumnText ~= nil -- our own column shows it
		local nameColumn = tableBuilder:AddFillColumn(owner, 0, 1.0, STANDARD_PADDING, 0,
			Enum.AuctionHouseSortOrder.Name, "AuctionHouseTableCellItemDisplayTemplate", restrictQualityToFilter, hideItemLevel)
		nameColumn:GetHeaderFrame():SetText(AUCTION_HOUSE_BROWSE_HEADER_NAME)

		if extraInfoColumnText then
			-- Blizzard's detail column (required level, slots, skill), sorted server side.
			local extraInfoColumn = tableBuilder:AddFixedWidthColumn(owner, 0, 55, STANDARD_PADDING, 0,
				Enum.AuctionHouseSortOrder.Level, "AuctionHouseTableCellLevelTemplate")
			extraInfoColumn:GetHeaderFrame():SetText(extraInfoColumnText)
		end

		if showItemLevel then
			AddItemLevelColumn(tableBuilder, owner)
		end

		local quantityHeaderText = AuctionHouseUtil.GetHeaderNameFromSortOrder(Enum.AuctionHouseSortOrder.Quantity)
		tableBuilder:AddUnsortableFixedWidthColumn(owner, 0, quantityWidth, STANDARD_PADDING, 0,
			quantityHeaderText, "AuctionHouseTableCellQuantityTemplate")
		tableBuilder:AddFixedWidthColumn(owner, 0, 29, STANDARD_PADDING, 5, nil, "AuctionHouseTableCellFavoriteTemplate")

		-- Freshly built Blizzard headers show their arrow; hide it while we sort.
		UpdateBlizzardArrows(owner)
	end

	return Layout
end

-------------------------------------------------------------------------------
-- Hooking into the auction house
-------------------------------------------------------------------------------

local hooked = false

local function OnCategorySelected(_, selectedCategoryIndex)
	local category = selectedCategoryIndex and AuctionCategories and AuctionCategories[selectedCategoryIndex]
	local name = category and category.name
	equipmentCategorySelected = name ~= nil and (name == AUCTION_CATEGORY_WEAPONS or name == AUCTION_CATEGORY_ARMOR)
end

local function HookAuctionHouse()
	if hooked then return end
	if not AuctionHouseTableBuilder or not AuctionHouseFrame then return end
	hooked = true

	-- 1. Layout with our column.
	AuctionHouseTableBuilder.GetBrowseListLayout = GetBrowseListLayoutWithItemLevel

	-- 2. Track whether a weapons / armor category is selected. Our own owner key
	--    keeps this independent from the browse frame's registration.
	if AuctionHouseFrameMixin and AuctionHouseFrameMixin.Event and AuctionHouseFrameMixin.Event.CategorySelected then
		AuctionHouseFrame:RegisterCallback(AuctionHouseFrameMixin.Event.CategorySelected, OnCategorySelected, ilvlHeaderOwner)
	end

	-- 3. The browse frame already built its layout in OnLoad; rebuild it.
	local browseFrame = AuctionHouseFrame.BrowseResultsFrame
	if browseFrame and browseFrame.SetupTableBuilder then
		browseFrame:SetupTableBuilder(browseFrame.pendingExtraColumnInfo)
	end

	if browseFrame then
		-- 4. Client-side re-sort whenever results arrive.
		hooksecurefunc(browseFrame, "UpdateBrowseResults", function(self)
			ResortAndRefresh(self)
		end)

		-- 5. Clicking one of Blizzard's headers ends the item level sort.
		hooksecurefunc(browseFrame, "SetSortOrder", function(self)
			if ilvlSort then
				ilvlSort = nil
				ilvlHeaderOwner:UpdateArrow()
				self:UpdateHeaders()
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local OnOff, ParseBool = Amity.OnOff, Amity.ParseBool

function M:Slash(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, arg = msg:match("^(%S+)%s*(.*)$")

	if cmd == "all" then
		local v = ParseBool(arg)
		if v == nil then v = db.equipmentOnly end -- toggle
		db.equipmentOnly = not v
		Print("item level for all items " .. OnOff(not db.equipmentOnly))
	else
		Print(("show item level for all items %s"):format(OnOff(not db.equipmentOnly)))
		Print("  /ail all on|off   - show item level for non-equipment too")
		return
	end

	-- Redraw with the new setting.
	local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
	if browseFrame and browseFrame.ItemList then
		ResortAndRefresh(browseFrame)
		browseFrame.ItemList:DirtyScrollFrame()
	end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function M:Init(settings)
	db = settings
	-- Blizzard_AuctionHouseUI is load-on-demand; it may or may not be loaded yet.
	HookAuctionHouse()

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:SetScript("OnEvent", function(self, event, arg1)
		if event == "ADDON_LOADED" then
			if arg1 == "Blizzard_AuctionHouseUI" then
				HookAuctionHouse()
			end
		elseif event == "GET_ITEM_INFO_RECEIVED" then
			-- An item we were waiting on is now cached: re-sort if sorting by level.
			if hooked and pendingItems[arg1] then
				pendingItems[arg1] = nil
				local browseFrame = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
				if browseFrame and browseFrame:IsShown() then
					ResortAndRefresh(browseFrame)
				end
			end
		end
	end)
end
