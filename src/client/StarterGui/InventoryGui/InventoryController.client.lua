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
local Players = game:GetService("Players")

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
local WeaponsMeta = require(ReplicatedStorage.Metadata.Weapons)
local ItemsMeta = require(ReplicatedStorage.Metadata.Items)

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MythlingsEvent = Remotes.MythlingsEvent
local MythlingsRequest = Remotes.MythlingsRequest
local ResourcesRequest = Remotes.ResourcesRequest
local InventoryRequest = Remotes.InventoryRequest

-- Art already in the place file.
local INVENTORY_ICON = "rbxassetid://135273755533681"
local INVENTORY_TEXT_SCALE = 1.15
local INVENTORY_CONTENT_SCALE = 1.15

local inventoryGui = script.Parent
inventoryGui.DisplayOrder = ThemeUtil.Layer.panel

--- Resource categories are stored lowercase ("currency"), but every other label in the
--- panel is title case, so they are capitalised for display rather than in the metadata.
local function titleCase(value: string): string
	return (value:gsub("^%l", string.upper))
end

local function inventoryContentScale(viewport: Vector2): number
	return ThemeUtil.isPhone(viewport) and 1 or INVENTORY_CONTENT_SCALE
end

local function inventoryPanelSize(viewport: Vector2): UDim2
	if ThemeUtil.isPhone(viewport) then
		return ThemeUtil.panelSize(viewport)
	end

	-- UIScale enlarges the complete composition. Give the card its logical dimensions
	-- here so its rendered footprint still lands at the intended responsive target.
	local scale = inventoryContentScale(viewport)
	local width = math.min(math.floor(viewport.X * 0.9), 1240)
	local height = math.min(600, ThemeUtil.usableHeight(viewport) - 16)
	return UDim2.fromOffset(math.floor(width / scale), math.floor(height / scale))
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
	tabs = { "Mythlings", "Weapons", "Items", "Resources" },
	size = inventoryPanelSize,
	-- No coin pill here. §08 puts one in every panel header, but the HUD's pill stays lit
	-- and on top while a panel is open, so a second one would just repeat itself.
	accent = ThemeUtil.Accent.gold,
	onClose = function()
		inventoryGui.Enabled = false
	end,
})

local inventoryScale = Instance.new("UIScale")
inventoryScale.Name = "ResponsiveContentScale"
inventoryScale.Scale = inventoryContentScale(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720))
inventoryScale.Parent = panel.Card

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		inventoryScale.Scale = inventoryContentScale(workspace.CurrentCamera.ViewportSize)
	end)
end

local mythlingsTab = panel.Tabs.Mythlings
local weaponsTab = panel.Tabs.Weapons
local itemsTab = panel.Tabs.Items
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
local weaponsFrame = newGridColumn("WeaponsFrame")
local itemsFrame = newGridColumn("ItemsFrame")
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
local weaponsCardTemplate = PanelUtil.cellTemplate({
	parent = weaponsFrame,
	quantity = true,
	check = true,
	root = panel.Root,
})
local itemsCardTemplate = PanelUtil.cellTemplate({
	parent = itemsFrame,
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
local weaponInfo = PanelUtil.details({
	parent = newDetailsColumn("WeaponInfo"),
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 3,
	info = true,
})
local itemInfo = PanelUtil.details({
	parent = newDetailsColumn("ItemInfo"),
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 3,
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
local localPlayer = Players.LocalPlayer

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

local function weaponThumbnail(profile, entry): string
	if profile.thumbnail and profile.thumbnail ~= "" then
		return profile.thumbnail
	end
	return entry.textureId or ""
end

local weaponList = CardListUtil.new({
	template = weaponsCardTemplate,
	parent = weaponsFrame,
	setHighlight = setRingHighlight,
	decorate = function(card, id, entry)
		local profile = WeaponsMeta.Profiles[id]
		card:WaitForChild("2dPreview").Image = weaponThumbnail(profile, entry)
		card.QuantityLabel.Text = entry.quantity > 1 and `x{entry.quantity}` or ""
		card:SetAttribute("Rarity", profile.rarity or "Common")
		PanelUtil.setCellRing(card, profile.rarity or "Common", false)
		card.EquippedCheck.Visible = entry.equipped
	end,
	onSelect = function(id, entry)
		local profile = WeaponsMeta.Profiles[id]
		local rarity = profile.rarity or "Common"
		weaponInfo.NameLabel.Text = profile.displayName or titleCase(id)
		weaponInfo.Art.Image = weaponThumbnail(profile, entry)
		weaponInfo.ElementIcon.BackgroundColor3 = ThemeUtil.rarityColor(rarity)
		weaponInfo.ElementIcon.Image = weaponThumbnail(profile, entry)
		PanelUtil.setHeroRarity(weaponInfo, rarity)
		weaponInfo.Stats[1].Value.Text = string.format("%.2fs", profile.swing.cooldownSeconds)
		weaponInfo.Stats[1].Label.Text = "Swing Cooldown"
		weaponInfo.Stats[2].Value.Text = string.format("%.2f", profile.target.reachStuds)
		weaponInfo.Stats[2].Label.Text = "Reach (studs)"
		weaponInfo.Stats[3].Value.Text = tostring(profile.impact.planarDeltaV)
		weaponInfo.Stats[3].Label.Text = "Knockback"
	end,
})

local function getItemMetadata(itemId: string)
	local direct = ItemsMeta[itemId]
	if direct then
		return direct
	end
	for metadataId, metadata in pairs(ItemsMeta) do
		if string.lower(metadataId) == string.lower(itemId) then
			return metadata
		end
	end
	return nil
end

local itemList = CardListUtil.new({
	template = itemsCardTemplate,
	parent = itemsFrame,
	setHighlight = setRingHighlight,
	filter = function(id, entry)
		return getItemMetadata(entry.itemId or id) ~= nil
	end,
	decorate = function(card, id, entry)
		local metadata = getItemMetadata(entry.itemId or id)
		local rarity = metadata.rarity or metadata.Rarity or "Common"
		card:WaitForChild("2dPreview").Image = metadata.thumbnail or ""
		card.QuantityLabel.Text = `x{entry.quantity or entry.total or 1}`
		card:SetAttribute("Rarity", rarity)
		PanelUtil.setCellRing(card, rarity, false)
	end,
	onSelect = function(id, entry)
		local metadata = getItemMetadata(entry.itemId or id)
		local rarity = metadata.rarity or metadata.Rarity or "Common"
		local itemType = metadata.Type or "Item"
		itemInfo.NameLabel.Text = metadata.displayName or titleCase(entry.itemId or id)
		itemInfo.Art.Image = metadata.thumbnail or ""
		itemInfo.ElementIcon.BackgroundColor3 = ThemeUtil.rarityColor(rarity)
		itemInfo.ElementIcon.Image = metadata.thumbnail or ""
		PanelUtil.setHeroRarity(itemInfo, rarity)
		itemInfo.Stats[1].Value.Text = tostring(entry.quantity or entry.total or 1)
		itemInfo.Stats[1].Label.Text = "Owned"
		itemInfo.Stats[2].Value.Text = itemType
		itemInfo.Stats[2].Label.Text = "Type"
		itemInfo.Stats[3].Value.Text = metadata.Value and `+{metadata.Value}` or "—"
		itemInfo.Stats[3].Label.Text = metadata.Effect or "Effect"
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

if weaponInfo.InfoButton then
	ButtonUtil.hookClick(weaponInfo.InfoButton, function()
		local id = weaponList:GetSelectedId()
		local entry = id and weaponList:GetData(id)
		local profile = id and WeaponsMeta.Profiles[id]
		if not profile or not entry then
			return
		end
		local rarity = profile.rarity or "Common"
		openLore(
			profile.displayName or titleCase(id),
			`{ThemeUtil.tier(rarity)} · {profile.weaponFamily}`,
			profile.description or "A weapon used in arena combat.",
			ThemeUtil.rarityColor(rarity),
			weaponThumbnail(profile, entry)
		)
	end)
end

if itemInfo.InfoButton then
	ButtonUtil.hookClick(itemInfo.InfoButton, function()
		local id = itemList:GetSelectedId()
		local entry = id and itemList:GetData(id)
		local metadata = entry and getItemMetadata(entry.itemId or id)
		if not metadata then
			return
		end
		local rarity = metadata.rarity or metadata.Rarity or "Common"
		openLore(
			metadata.displayName or titleCase(entry.itemId or id),
			`{ThemeUtil.tier(rarity)} · {metadata.Type or "Item"}`,
			metadata.description or "An item found in the Mythic realm.",
			ThemeUtil.rarityColor(rarity),
			metadata.thumbnail or ""
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

	if tab == weaponsTab then
		PanelUtil.setTabActive(tab, true, panel.Accent)
		weaponsFrame.Parent.Visible = true
		weaponInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = weaponsFrame
		selectedInfo = weaponInfo.Root
	end

	if tab == itemsTab then
		PanelUtil.setTabActive(tab, true, panel.Accent)
		itemsFrame.Parent.Visible = true
		itemInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = itemsFrame
		selectedInfo = itemInfo.Root
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

ButtonUtil.hookClick(weaponsTab, function()
	selectTab(weaponsTab)
end)

ButtonUtil.hookClick(itemsTab, function()
	selectTab(itemsTab)
end)

local function collectWeapons()
	local weapons = {}
	local function collect(container: Instance?, equipped: boolean)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local id, profile = WeaponsMeta.GetProfile(child)
				if id and profile then
					local entry = weapons[id]
					if not entry then
						entry = {
							quantity = 0,
							equipped = false,
							textureId = child.TextureId,
						}
						weapons[id] = entry
					end
					entry.quantity += 1
					entry.equipped = entry.equipped or equipped
					if entry.textureId == "" then
						entry.textureId = child.TextureId
					end
				end
			end
		end
	end
	collect(localPlayer:FindFirstChildOfClass("Backpack"), false)
	collect(localPlayer.Character, true)
	return weapons
end

local weaponRefreshQueued = false
local function queueWeaponRefresh()
	if weaponRefreshQueued then
		return
	end
	weaponRefreshQueued = true
	task.defer(function()
		weaponRefreshQueued = false
		if inventoryGui.Enabled then
			weaponList:Replace(collectWeapons())
		end
	end)
end

local function watchTools(container: Instance)
	container.ChildAdded:Connect(queueWeaponRefresh)
	container.ChildRemoved:Connect(queueWeaponRefresh)
end

local backpack = localPlayer:FindFirstChildOfClass("Backpack")
if backpack then
	watchTools(backpack)
end
localPlayer.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watchTools(child)
		queueWeaponRefresh()
	end
end)
localPlayer.CharacterAdded:Connect(function(character)
	watchTools(character)
	queueWeaponRefresh()
end)
if localPlayer.Character then
	watchTools(localPlayer.Character)
end

-- Inventory carries denser labels than the other panels, especially across four tabs and
-- three-column stat rows. Increase only this menu's em-stamped typography; cloned card
-- templates inherit the scale attribute, and PanelUtil keeps it when device roots change.
for _, descendant in ipairs(inventoryGui:GetDescendants()) do
	if descendant:GetAttribute("Em") then
		descendant:SetAttribute(
			"EmScale",
			(descendant:GetAttribute("EmScale") or 1) * INVENTORY_TEXT_SCALE
		)
	end
end
PanelUtil.rescaleText(inventoryGui, panel.Root)

-- This ScreenGui's own Enabled property is the open/close contract. HUDController owns the
-- button in HUDGui that toggles it, so this controller no longer reaches across into
-- another GUI, and anything else that wants the inventory open just sets this flag.
inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if inventoryGui.Enabled then
		mythlingList:Replace(MythlingsRequest:InvokeServer("GetMythlings"))
		weaponList:Replace(collectWeapons())
		itemList:Replace(InventoryRequest:InvokeServer("GetItems"))
		resourceList:Replace(ResourcesRequest:InvokeServer("GetResources"))
		selectTab(mythlingsTab)
		ModalUtil.Open(PANEL_NAME)
	else
		loreModal:Close()
		closeConfirmDeleteModal()
		ModalUtil.Close(PANEL_NAME)
	end
end)
