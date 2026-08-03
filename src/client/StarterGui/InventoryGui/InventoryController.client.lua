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
local MythlingPreviewUtil = require(Ui:WaitForChild("MythlingPreviewUtil"))
local ThemeUtil = require(Ui:WaitForChild("ThemeUtil"))
local PanelUtil = require(Ui:WaitForChild("PanelUtil"))
local EquipmentPreviewUtil = require(Ui:WaitForChild("EquipmentPreviewUtil"))
local MythlingsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))
local MaterialsMeta = require(ReplicatedStorage.Metadata.Materials)
local EquipmentMeta = require(ReplicatedStorage.Metadata.Equipment)
local ConsumablesMeta = require(ReplicatedStorage.Metadata.Consumables)
-- The authored Studio folder keeps its existing name so Rojo does not orphan its models.
local EquipmentAssets = ReplicatedStorage:WaitForChild("WeaponAssets")
local CombatLoadoutRequest = ReplicatedStorage:WaitForChild("CombatLoadoutRequest") :: RemoteFunction

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MythlingsEvent = Remotes.MythlingsEvent
local MythlingsRequest = Remotes.MythlingsRequest
local MaterialsRequest = Remotes.MaterialsRequest
local ConsumablesRequest = Remotes.ConsumablesRequest

-- Art already in the place file.
local INVENTORY_ICON = "rbxassetid://135273755533681"
local INVENTORY_TEXT_SCALE = 1.15
local INVENTORY_CONTENT_SCALE = 1.15

local inventoryGui = script.Parent
inventoryGui.DisplayOrder = ThemeUtil.Layer.panel

--- Material categories are stored lowercase, but every other label in the
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
	-- This asset contains more transparent margin than the Shop icon, so its image box
	-- must be larger for both header glyphs to have the same apparent size.
	titleIconSize = 34,
	tabs = { "Mythlings", "Equipment", "Consumables", "Materials" },
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
local equipmentTab = panel.Tabs.Equipment
local consumablesTab = panel.Tabs.Consumables
local materialsTab = panel.Tabs.Materials

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
local equipmentFrame = newGridColumn("EquipmentFrame")
local consumablesFrame = newGridColumn("ConsumablesFrame")
local materialsFrame = newGridColumn("MaterialsFrame")

local mythlingCardTemplate = PanelUtil.cellTemplate({
	parent = mythlingsFrame,
	check = true,
	root = panel.Root,
})
local materialsCardTemplate = PanelUtil.cellTemplate({
	parent = materialsFrame,
	quantity = true,
	root = panel.Root,
})
local equipmentCardTemplate = PanelUtil.cellTemplate({
	parent = equipmentFrame,
	quantity = true,
	check = true,
	root = panel.Root,
})
local consumablesCardTemplate = PanelUtil.cellTemplate({
	parent = consumablesFrame,
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
local materialInfo = PanelUtil.details({
	parent = newDetailsColumn("MaterialInfo"),
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 2,
	info = true,
})
local equipmentInfo = PanelUtil.details({
	parent = newDetailsColumn("EquipmentInfo"),
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 3,
	info = true,
	primary = "Equip",
})
local consumableInfo = PanelUtil.details({
	parent = newDetailsColumn("ConsumableInfo"),
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
local materialButtonsConnected = false
local localPlayer = Players.LocalPlayer

--- §05's ring rules do the highlighting now: the rarity colour is always on the cell, and
--- selection is the difference between a 3px ring and a dimmed 2px one. The old yellow
--- stroke told the player nothing about the card.
---
--- Materials have no rarity, so their cells carry a RingColor instead and keep their own
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
	MythlingPreviewUtil.Clear(mythlingInfo.Art)
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
		local variant = metadata.variants[entry.variantId]
		local preview = card:WaitForChild("2dPreview")
		preview.Image = ""
		MythlingPreviewUtil.Render(preview, variant.model, entry.variantId)
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
		local material = MaterialsMeta[metadata.production.materialId]
		local variant = metadata.variants[entry.variantId]

		mythlingInfo.NameLabel.Text = metadata.displayName
		mythlingInfo.Art.Image = ""
		MythlingPreviewUtil.Render(mythlingInfo.Art, variant.model, entry.variantId)
		PanelUtil.setHeroRarity(mythlingInfo, metadata.rarity)

		-- This game has no elements; a mythling's identity colour is the material it
		-- produces, which is the nearest thing the metadata actually carries.
		mythlingInfo.ElementIcon.BackgroundColor3 = Color3.fromHex(material.guiColor)
		mythlingInfo.ElementIcon.Image = material.thumbnail

		mythlingInfo.Stats[1].Value.Text = string.format("%.2g/min", metadata.production.baseRate)
		mythlingInfo.Stats[1].Label.Text = material.displayName
		mythlingInfo.Stats[2].Value.Text = tostring(metadata.production.baseCapacity)
		mythlingInfo.Stats[2].Label.Text = "Max Storage"
		mythlingInfo.Stats[3].Value.Text = entry.standId and `#{entry.standId}` or "—"
		mythlingInfo.Stats[3].Label.Text = "Stationed At"
	end,
})

local materialList = CardListUtil.new({
	template = materialsCardTemplate,
	parent = materialsFrame,
	setHighlight = setRingHighlight,
	filter = function(id)
		return MaterialsMeta[id] ~= nil
	end,
	decorate = function(card, id, entry)
		local metadata = MaterialsMeta[id]
		card:WaitForChild("2dPreview").Image = metadata.thumbnail
		card.QuantityLabel.Text = `x{entry.total}`
		-- Materials have no rarity, so the ring carries their gui colour instead. Read back
		-- by setRingHighlight, which only receives the card.
		card:SetAttribute("RingColor", Color3.fromHex(metadata.guiColor))
		PanelUtil.setCellRing(card, nil, false, Color3.fromHex(metadata.guiColor))
	end,
	onSelect = function(id, entry)
		local metadata = MaterialsMeta[id]
		local tint = Color3.fromHex(metadata.guiColor)

		materialInfo.NameLabel.Text = metadata.displayName
		materialInfo.Art.Image = metadata.thumbnail
		materialInfo.ElementIcon.BackgroundColor3 = tint
		materialInfo.ElementIcon.Image = metadata.thumbnail
		materialInfo.RarityLabel.Text = titleCase(metadata.category)
		materialInfo.RarityLabel.TextColor3 = tint
		ThemeUtil.ring(materialInfo.Hero, tint, 3)

		materialInfo.Stats[1].Value.Text = tostring(entry.total)
		materialInfo.Stats[1].Label.Text = "Owned"
		materialInfo.Stats[2].Value.Text = titleCase(metadata.category)
		materialInfo.Stats[2].Label.Text = "Category"
	end,
})

local function equipmentThumbnail(profile, entry): string
	if profile.thumbnail and profile.thumbnail ~= "" then
		return profile.thumbnail
	end
	return entry.textureId or ""
end

local function setEquipmentPreview(imageLabel: ImageLabel, profile, entry)
	local thumbnail = equipmentThumbnail(profile, entry)
	EquipmentPreviewUtil.Clear(imageLabel)
	imageLabel.Image = thumbnail
	if thumbnail == "" then
		EquipmentPreviewUtil.Render(imageLabel, entry.previewModel)
	end
end

local equipmentList = CardListUtil.new({
	template = equipmentCardTemplate,
	parent = equipmentFrame,
	setHighlight = setRingHighlight,
	decorate = function(card, id, entry)
		local profile = EquipmentMeta.Profiles[id]
		setEquipmentPreview(card:WaitForChild("2dPreview"), profile, entry)
		card.QuantityLabel.Text = entry.quantity > 1 and `x{entry.quantity}` or ""
		card:SetAttribute("Rarity", profile.rarity or "Common")
		PanelUtil.setCellRing(card, profile.rarity or "Common", false)
		card.EquippedCheck.Visible = entry.equipped
	end,
	onSelect = function(id, entry)
		local profile = EquipmentMeta.Profiles[id]
		local rarity = profile.rarity or "Common"
		equipmentInfo.NameLabel.Text = profile.displayName or titleCase(id)
		setEquipmentPreview(equipmentInfo.Art, profile, entry)
		equipmentInfo.ElementIcon.BackgroundColor3 = ThemeUtil.rarityColor(rarity)
		setEquipmentPreview(equipmentInfo.ElementIcon, profile, entry)
		PanelUtil.setHeroRarity(equipmentInfo, rarity)

		if profile.kind == "Shield" then
			equipmentInfo.Stats[1].Value.Text = string.format("%.2fs", profile.activationCooldownSeconds or 0)
			equipmentInfo.Stats[1].Label.Text = "Raise Cooldown"
			equipmentInfo.Stats[2].Value.Text = string.format("%.0f°", profile.blockArcDegrees or 0)
			equipmentInfo.Stats[2].Label.Text = "Block Arc"
			equipmentInfo.Stats[3].Value.Text = tostring(profile.slideKnockback or 0)
			equipmentInfo.Stats[3].Label.Text = "Block Slide"
		elseif profile.kind == "PrimaryWeapon" then
			equipmentInfo.Stats[1].Value.Text = string.format("%.2fs", profile.cooldownSeconds or 0)
			equipmentInfo.Stats[1].Label.Text = "Swing Cooldown"
			equipmentInfo.Stats[2].Value.Text = string.format("%.2f", profile.reachStuds or 0)
			equipmentInfo.Stats[2].Label.Text = "Reach (studs)"
			equipmentInfo.Stats[3].Value.Text = tostring(profile.planarKnockback or 0)
			equipmentInfo.Stats[3].Label.Text = "Knockback"
		else
			for _, stat in ipairs(equipmentInfo.Stats) do
				stat.Value.Text = "—"
				stat.Label.Text = ""
			end
		end
	end,
})

local function getConsumableMetadata(consumableId: string)
	local direct = ConsumablesMeta[consumableId]
	if direct then
		return direct
	end
	for metadataId, metadata in pairs(ConsumablesMeta) do
		if string.lower(metadataId) == string.lower(consumableId) then
			return metadata
		end
	end
	return nil
end

local consumableList = CardListUtil.new({
	template = consumablesCardTemplate,
	parent = consumablesFrame,
	setHighlight = setRingHighlight,
	filter = function(id, entry)
		return getConsumableMetadata(entry.consumableId or id) ~= nil
	end,
	decorate = function(card, id, entry)
		local metadata = getConsumableMetadata(entry.consumableId or id)
		local rarity = metadata.rarity or "Common"
		card:WaitForChild("2dPreview").Image = metadata.thumbnail or ""
		card.QuantityLabel.Text = `x{entry.quantity or entry.total or 1}`
		card:SetAttribute("Rarity", rarity)
		PanelUtil.setCellRing(card, rarity, false)
	end,
	onSelect = function(id, entry)
		local metadata = getConsumableMetadata(entry.consumableId or id)
		local rarity = metadata.rarity or "Common"
		local consumableType = metadata.category or "Consumable"
		consumableInfo.NameLabel.Text = metadata.displayName or titleCase(entry.consumableId or id)
		consumableInfo.Art.Image = metadata.thumbnail or ""
		consumableInfo.ElementIcon.BackgroundColor3 = ThemeUtil.rarityColor(rarity)
		consumableInfo.ElementIcon.Image = metadata.thumbnail or ""
		PanelUtil.setHeroRarity(consumableInfo, rarity)
		consumableInfo.Stats[1].Value.Text = tostring(entry.quantity or entry.total or 1)
		consumableInfo.Stats[1].Label.Text = "Owned"
		consumableInfo.Stats[2].Value.Text = consumableType
		consumableInfo.Stats[2].Label.Text = "Type"
		consumableInfo.Stats[3].Value.Text = metadata.value and `+{metadata.value}` or "—"
		consumableInfo.Stats[3].Label.Text = metadata.effect or "Effect"
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
		local material = MaterialsMeta[metadata.production.materialId]
		openLore(
			metadata.displayName,
			`{ThemeUtil.tier(metadata.rarity)} · {material.displayName}`,
			metadata.description,
			ThemeUtil.rarityColor(metadata.rarity),
			metadata.variants[entry.variantId].thumbnail
		)
	end)
end

if materialInfo.InfoButton then
	ButtonUtil.hookClick(materialInfo.InfoButton, function()
		local id = materialList:GetSelectedId()
		local metadata = id and MaterialsMeta[id]
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

if equipmentInfo.InfoButton then
	ButtonUtil.hookClick(equipmentInfo.InfoButton, function()
		local id = equipmentList:GetSelectedId()
		local entry = id and equipmentList:GetData(id)
		local profile = id and EquipmentMeta.Profiles[id]
		if not profile or not entry then
			return
		end
		local rarity = profile.rarity or "Common"
		openLore(
			profile.displayName or titleCase(id),
			`{ThemeUtil.tier(rarity)} · {profile.kind}`,
			profile.description or "Equipment used in Arena combat.",
			ThemeUtil.rarityColor(rarity),
			equipmentThumbnail(profile, entry)
		)
	end)
end

if consumableInfo.InfoButton then
	ButtonUtil.hookClick(consumableInfo.InfoButton, function()
		local id = consumableList:GetSelectedId()
		local entry = id and consumableList:GetData(id)
		local metadata = entry and getConsumableMetadata(entry.consumableId or id)
		if not metadata then
			return
		end
		local rarity = metadata.rarity or "Common"
		openLore(
			metadata.displayName or titleCase(entry.consumableId or id),
			`{ThemeUtil.tier(rarity)} · {metadata.category or "Consumable"}`,
			metadata.description or "A Consumable used in the Arena.",
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

local function setMaterialButtons()
	if materialButtonsConnected then
		return
	end
	materialButtonsConnected = true

	-- Materials have no actions yet, so their details column has no footer at all.
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

	if tab == materialsTab then
		setMaterialButtons()
		PanelUtil.setTabActive(tab, true, panel.Accent)
		materialsFrame.Parent.Visible = true
		materialInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = materialsFrame
		selectedInfo = materialInfo.Root
	end

	if tab == equipmentTab then
		PanelUtil.setTabActive(tab, true, panel.Accent)
		equipmentFrame.Parent.Visible = true
		equipmentInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = equipmentFrame
		selectedInfo = equipmentInfo.Root
	end

	if tab == consumablesTab then
		PanelUtil.setTabActive(tab, true, panel.Accent)
		consumablesFrame.Parent.Visible = true
		consumableInfo.Root.Visible = true
		selectedTab = tab
		selectedFrame = consumablesFrame
		selectedInfo = consumableInfo.Root
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

ButtonUtil.hookClick(materialsTab, function()
	selectTab(materialsTab)
end)

ButtonUtil.hookClick(equipmentTab, function()
	selectTab(equipmentTab)
end)

ButtonUtil.hookClick(consumablesTab, function()
	selectTab(consumablesTab)
end)

local function collectEquipment()
	local equipment = {}
	local success, response = pcall(CombatLoadoutRequest.InvokeServer, CombatLoadoutRequest, "Get")
	if not success or type(response) ~= "table" or response.ok ~= true or type(response.snapshot) ~= "table" then
		return equipment
	end
	local snapshot = response.snapshot
	for _, owned in snapshot.equipment or {} do
		local id = owned.definitionId
		local profile = type(id) == "string" and EquipmentMeta.Profiles[id]
		if profile then
			local entry = equipment[id]
			if not entry then
				entry = {
					quantity = 0,
					equipped = false,
					textureId = "",
					instanceId = owned.instanceId,
					previewModel = EquipmentAssets:FindFirstChild(profile.modelName),
				}
				equipment[id] = entry
			end
			entry.quantity += 1
			if owned.instanceId == snapshot.primaryWeaponInstanceId
				or owned.instanceId == snapshot.shieldInstanceId
			then
				entry.equipped = true
				entry.instanceId = owned.instanceId
			end
		end
	end
	return equipment
end

local equipmentRefreshQueued = false
local function queueEquipmentRefresh()
	if equipmentRefreshQueued then
		return
	end
	equipmentRefreshQueued = true
	task.defer(function()
		equipmentRefreshQueued = false
		if inventoryGui.Enabled then
			equipmentList:Replace(collectEquipment())
		end
	end)
end

localPlayer.CharacterAdded:Connect(function(character)
	character:GetAttributeChangedSignal("RightEquipped"):Connect(queueEquipmentRefresh)
	character:GetAttributeChangedSignal("LeftEquipped"):Connect(queueEquipmentRefresh)
	queueEquipmentRefresh()
end)
if localPlayer.Character then
	localPlayer.Character:GetAttributeChangedSignal("RightEquipped"):Connect(queueEquipmentRefresh)
	localPlayer.Character:GetAttributeChangedSignal("LeftEquipped"):Connect(queueEquipmentRefresh)
end

if equipmentInfo.PrimaryButton then
	ButtonUtil.hookClick(equipmentInfo.PrimaryButton, function()
		local id = equipmentList:GetSelectedId()
		local entry = id and equipmentList:GetData(id)
		if not entry or type(entry.instanceId) ~= "string" then
			return
		end
		local success, response = pcall(CombatLoadoutRequest.InvokeServer, CombatLoadoutRequest, "Equip", {
			instanceId = entry.instanceId,
		})
		if success and type(response) == "table" and response.ok == true then
			equipmentList:Replace(collectEquipment())
		end
	end)
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
		-- Claim the shared backdrop before any yielding server requests. During a direct
		-- Shop -> Inventory handoff, delaying this until after data refresh briefly left
		-- ModalUtil with no owners and flashed the world for one frame.
		ModalUtil.Open(PANEL_NAME)
		mythlingList:Replace(MythlingsRequest:InvokeServer("GetMythlings"))
		equipmentList:Replace(collectEquipment())
		consumableList:Replace(ConsumablesRequest:InvokeServer("GetConsumables"))
		materialList:Replace(MaterialsRequest:InvokeServer("GetMaterials"))
		selectTab(mythlingsTab)
	else
		loreModal:Close()
		closeConfirmDeleteModal()
		ModalUtil.Close(PANEL_NAME)
	end
end)
