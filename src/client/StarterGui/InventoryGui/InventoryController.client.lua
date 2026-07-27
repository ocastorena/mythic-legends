-- StarterGui/InventoryGui/InventoryController
--
-- The inventory is the panel the design system was derived from, so it composes the shell
-- verbatim: header (identity · 88px tabs · coin pill + ✕), body split grid 2/3 · details
-- 1/3, and a details column of hero art, hero stats and a footer button.
--
-- Two things moved out of the panel to follow the doc. Flavour text used to sit inline in
-- the info pane; §06 and §08 both say lore belongs behind the [ i ] button, so it lives in
-- a modal now. And the Delete action used to be a button floating below the card in a
-- separate `Bottom` frame; §07 puts panel actions in the details footer, so that is where
-- it is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Identifies this panel to ModalUtil, which owns the backdrop and input guard.
local PANEL_NAME = "Inventory"

-- Modules
local Ui = ReplicatedStorage:WaitForChild("Client"):WaitForChild("Ui")
local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
local CardListUtil = require(Ui:WaitForChild("CardListUtil"))
local ModalUtil = require(Ui:WaitForChild("ModalUtil"))
local ThemeUtil = require(Ui:WaitForChild("ThemeUtil"))
local PanelUtil = require(Ui:WaitForChild("PanelUtil"))
local MythlingsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))
local ResourcesMeta = require(ReplicatedStorage.Metadata.Resources)

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MythlingsEvent = Remotes.MythlingsEvent
local MythlingsRequest = Remotes.MythlingsRequest
local ResourcesRequest = Remotes.ResourcesRequest

-- Art already in the place file.
local INVENTORY_ICON = "rbxassetid://135273755533681"

local inventoryGui = script.Parent
inventoryGui.DisplayOrder = ThemeUtil.Layer.panel

--- Resource categories are stored lowercase ("currency"), but every other label in the
--- panel is title case, so they are capitalised for display rather than in the metadata.
local function titleCase(value: string): string
	return (value:gsub("^%l", string.upper))
end

--------------------------------------------------------------------------------
-- Shell
--------------------------------------------------------------------------------

-- The authored frames predate the design system; the shell replaces them outright so
-- there is only one definition of the panel.
for _, name in ipairs({ "Main", "Bottom", "ConfirmDeleteModal" }) do
	local authored = inventoryGui:FindFirstChild(name)
	if authored then
		authored:Destroy()
	end
end

local panel = PanelUtil.panel({
	parent = inventoryGui,
	title = "Inventory",
	titleIcon = INVENTORY_ICON,
	tabs = { "Mythlings", "Resources" },
	-- No coin pill here. §08 puts one in every panel header, but the HUD's pill stays lit
	-- and on top while a panel is open, so a second one would just repeat itself.
	accent = ThemeUtil.Accent.gold,
	onClose = function()
		inventoryGui.Enabled = false
	end,
})

local mythlingsTab = panel.Tabs.Mythlings
local resourcesTab = panel.Tabs.Resources

--------------------------------------------------------------------------------
-- Grids
--------------------------------------------------------------------------------

--- Each tab owns a grid; only the selected one is visible, so the 2/3 column always holds
--- exactly one set of cells.
local function newGridColumn(name: string): ScrollingFrame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.Parent = panel.Grid
	return PanelUtil.grid(holder)
end

local mythlingsFrame = newGridColumn("MythlingsFrame")
local resourcesFrame = newGridColumn("ResourcesFrame")

local mythlingCardTemplate = PanelUtil.cellTemplate({
	parent = mythlingsFrame,
	check = true,
	root = panel.Root,
})
local resourcesCardTemplate = PanelUtil.cellTemplate({
	parent = resourcesFrame,
	quantity = true,
	root = panel.Root,
})

--------------------------------------------------------------------------------
-- Details panes
--------------------------------------------------------------------------------

--- Both tabs get their own details column inside the shell's details slot, toggled with
--- the grid so tab switching swaps the whole 1/3 column at once.
local function newDetailsColumn(name: string): Frame
	local column = Instance.new("Frame")
	column.Name = name
	column.Size = UDim2.fromScale(1, 1)
	column.BackgroundTransparency = 1
	column.BorderSizePixel = 0
	column.Visible = false
	column.Parent = panel.Details
	return column
end

local mythlingInfo = PanelUtil.details({
	parent = newDetailsColumn("MythlingInfo"),
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 3,
	info = true,
	primary = "Delete",
})
local resourceInfo = PanelUtil.details({
	parent = newDetailsColumn("ResourceInfo"),
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 2,
	info = true,
})

-- Delete is destructive, so the footer button carries the danger accent of §01.
if mythlingInfo.PrimaryButton then
	PanelUtil.setButtonEnabled(mythlingInfo.PrimaryButton, true, ThemeUtil.Accent.red)
end

--------------------------------------------------------------------------------
-- Lore + confirm modals (§08)
--------------------------------------------------------------------------------

local loreModal = PanelUtil.modal({
	parent = inventoryGui,
	root = panel.Root,
	name = "LoreModal",
	subtitle = true,
	body = true,
})

local confirmModal = PanelUtil.modal({
	parent = inventoryGui,
	root = panel.Root,
	name = "ConfirmModal",
	title = "",
	body = true,
	confirm = "Delete",
	cancel = "Cancel",
	confirmTint = ThemeUtil.Accent.red,
})
confirmModal.IconDisc.BackgroundColor3 = ThemeUtil.Accent.red
if confirmModal.BodyLabel then
	confirmModal.BodyLabel.Text = "This cannot be undone."
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local selectedTab = nil
local selectedFrame = nil
local selectedInfo = nil

local pendingDeleteId = nil
local mythlingButtonsConnected = false
local resourceButtonsConnected = false

--- §05's ring rules do the highlighting now: the rarity colour is always on the cell, and
--- selection is the difference between a 3px ring and a dimmed 2px one. The old yellow
--- stroke told the player nothing about the card.
---
--- Resources have no rarity, so their cells carry a RingColor instead and keep their own
--- identity colour when selected.
local function setRingHighlight(card, selected: boolean)
	PanelUtil.setCellRing(card, card:GetAttribute("Rarity"), selected, card:GetAttribute("RingColor"))
end

local function closeConfirmDeleteModal()
	confirmModal:Close()
end

local function openConfirmDeleteModal(displayName)
	confirmModal.TitleLabel.Text = `Delete {displayName}?`
	confirmModal:Open()
end

--------------------------------------------------------------------------------
-- Mythlings
--------------------------------------------------------------------------------

local function clearMythlingInfo()
	mythlingInfo.NameLabel.Text = ""
	mythlingInfo.RarityLabel.Text = ""
	mythlingInfo.Art.Image = ""
	for _, stat in ipairs(mythlingInfo.Stats) do
		stat.Value.Text = "—"
		stat.Label.Text = ""
	end
end

local mythlingList = CardListUtil.new({
	template = mythlingCardTemplate,
	parent = mythlingsFrame,
	setHighlight = setRingHighlight,
	decorate = function(card, _id, entry)
		local metadata = MythlingsData[entry.typeId]
		card:WaitForChild("2dPreview").Image = metadata.variants[entry.variantId].thumbnail
		-- Read back by setRingHighlight, which only receives the card.
		card:SetAttribute("Rarity", metadata.rarity)
		PanelUtil.setCellRing(card, metadata.rarity, false)

		-- §05's green ✓ marks a mythling already working a stand.
		local check = card:FindFirstChild("EquippedCheck")
		if check then
			check.Visible = entry.standId ~= nil
		end
	end,
	onSelect = function(_id, entry)
		local metadata = MythlingsData[entry.typeId]
		local resource = ResourcesMeta[metadata.production.resourceId]

		mythlingInfo.NameLabel.Text = metadata.displayName
		mythlingInfo.Art.Image = metadata.variants[entry.variantId].thumbnail
		PanelUtil.setHeroRarity(mythlingInfo, metadata.rarity)

		-- This game has no elements; a mythling's identity colour is the resource it
		-- produces, which is the nearest thing the metadata actually carries.
		mythlingInfo.ElementIcon.BackgroundColor3 = Color3.fromHex(resource.guiColor)
		mythlingInfo.ElementIcon.Image = resource.thumbnail

		mythlingInfo.Stats[1].Value.Text = string.format("%.2g/min", metadata.production.baseRate)
		mythlingInfo.Stats[1].Label.Text = resource.displayName
		mythlingInfo.Stats[2].Value.Text = tostring(metadata.production.baseCapacity)
		mythlingInfo.Stats[2].Label.Text = "Max Storage"
		mythlingInfo.Stats[3].Value.Text = entry.standId and `#{entry.standId}` or "—"
		mythlingInfo.Stats[3].Label.Text = "Stationed At"
	end,
})

local resourceList = CardListUtil.new({
	template = resourcesCardTemplate,
	parent = resourcesFrame,
	setHighlight = setRingHighlight,
	decorate = function(card, id, entry)
		local metadata = ResourcesMeta[id]
		card:WaitForChild("2dPreview").Image = metadata.thumbnail
		card.QuantityLabel.Text = `x{entry.total}`
		-- Resources have no rarity, so the ring carries their gui colour instead. Read back
		-- by setRingHighlight, which only receives the card.
		card:SetAttribute("RingColor", Color3.fromHex(metadata.guiColor))
		PanelUtil.setCellRing(card, nil, false, Color3.fromHex(metadata.guiColor))
	end,
	onSelect = function(id, entry)
		local metadata = ResourcesMeta[id]
		local tint = Color3.fromHex(metadata.guiColor)

		resourceInfo.NameLabel.Text = metadata.displayName
		resourceInfo.Art.Image = metadata.thumbnail
		resourceInfo.ElementIcon.BackgroundColor3 = tint
		resourceInfo.ElementIcon.Image = metadata.thumbnail
		resourceInfo.RarityLabel.Text = titleCase(metadata.category)
		resourceInfo.RarityLabel.TextColor3 = tint
		ThemeUtil.ring(resourceInfo.Hero, tint, 3)

		resourceInfo.Stats[1].Value.Text = tostring(entry.total)
		resourceInfo.Stats[1].Label.Text = "Owned"
		resourceInfo.Stats[2].Value.Text = titleCase(metadata.category)
		resourceInfo.Stats[2].Label.Text = "Category"
	end,
})

--- The [ i ] button on each hero frame opens the lore modal, which is the only place
--- flavour text appears.
local function openLore(title: string, subtitle: string, body: string, tint: Color3, icon: string)
	loreModal.TitleLabel.Text = title
	loreModal.IconDisc.BackgroundColor3 = tint
	loreModal.IconDisc.Image = icon
	if loreModal.SubtitleLabel then
		loreModal.SubtitleLabel.Text = subtitle
		loreModal.SubtitleLabel.TextColor3 = tint
	end
	if loreModal.BodyLabel then
		loreModal.BodyLabel.Text = body
	end
	loreModal:Open()
end

if mythlingInfo.InfoButton then
	ButtonUtil.hookClick(mythlingInfo.InfoButton, function()
		local id = mythlingList:GetSelectedId()
		local entry = id and mythlingList:GetData(id)
		if not entry then
			return
		end
		local metadata = MythlingsData[entry.typeId]
		local resource = ResourcesMeta[metadata.production.resourceId]
		openLore(
			metadata.displayName,
			`{ThemeUtil.tier(metadata.rarity)} · {resource.displayName}`,
			metadata.description,
			ThemeUtil.rarityColor(metadata.rarity),
			metadata.variants[entry.variantId].thumbnail
		)
	end)
end

if resourceInfo.InfoButton then
	ButtonUtil.hookClick(resourceInfo.InfoButton, function()
		local id = resourceList:GetSelectedId()
		local metadata = id and ResourcesMeta[id]
		if not metadata then
			return
		end
		openLore(
			metadata.displayName,
			titleCase(metadata.category),
			metadata.description,
			Color3.fromHex(metadata.guiColor),
			metadata.thumbnail
		)
	end)
end

local function setMythlingButtons()
	local deleteButton = mythlingInfo.PrimaryButton
	if not deleteButton then
		return
	end

	if mythlingButtonsConnected then
		return
	end
	mythlingButtonsConnected = true

	ButtonUtil.hookClick(deleteButton, function()
		local selectedId = mythlingList:GetSelectedId()
		if not selectedId then
			return
		end
		pendingDeleteId = selectedId
		openConfirmDeleteModal(mythlingInfo.NameLabel.Text)
	end)

	if confirmModal.ConfirmButton then
		ButtonUtil.hookClick(confirmModal.ConfirmButton, function()
			if not pendingDeleteId then
				closeConfirmDeleteModal()
				return
			end

			clearMythlingInfo()
			mythlingList:Remove(pendingDeleteId)

			MythlingsEvent:FireServer("Delete", pendingDeleteId)

			pendingDeleteId = nil
			closeConfirmDeleteModal()
		end)
	end

	if confirmModal.CancelButton then
		ButtonUtil.hookClick(confirmModal.CancelButton, function()
			pendingDeleteId = nil
			closeConfirmDeleteModal()
		end)
	end
end

local function setResourceButtons()
	if resourceButtonsConnected then
		return
	end
	resourceButtonsConnected = true

	-- Resources have no actions yet, so their details column has no footer at all.
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

local function selectTab(tab)
	if selectedTab == tab then
		return
	end
	if selectedTab then
		PanelUtil.setTabActive(selectedTab, false, panel.Accent)
		selectedFrame.Parent.Visible = false
		selectedInfo.Visible = false
	end

	if tab == mythlingsTab then
		setMythlingButtons()
		PanelUtil.setTabActive(tab, true, panel.Accent)
		mythlingsFrame.Parent.Visible = true
		mythlingInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = mythlingsFrame
		selectedInfo = mythlingInfo.Root
	end

	if tab == resourcesTab then
		setResourceButtons()
		PanelUtil.setTabActive(tab, true, panel.Accent)
		resourcesFrame.Parent.Visible = true
		resourceInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = resourcesFrame
		selectedInfo = resourceInfo.Root
	end
end

MythlingsEvent.OnClientEvent:Connect(function(event, list)
	if event == "Update" then
		mythlingList:Replace(list)
	end
end)

ButtonUtil.hookClick(mythlingsTab, function()
	selectTab(mythlingsTab)
end)

ButtonUtil.hookClick(resourcesTab, function()
	selectTab(resourcesTab)
end)

-- This ScreenGui's own Enabled property is the open/close contract. HUDController owns the
-- button in HUDGui that toggles it, so this controller no longer reaches across into
-- another GUI, and anything else that wants the inventory open just sets this flag.
inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if inventoryGui.Enabled then
		mythlingList:Replace(MythlingsRequest:InvokeServer("GetMythlings"))
		resourceList:Replace(ResourcesRequest:InvokeServer("GetResources"))
		selectTab(mythlingsTab)
		ModalUtil.Open(PANEL_NAME)
	else
		loreModal:Close()
		closeConfirmDeleteModal()
		ModalUtil.Close(PANEL_NAME)
	end
end)
