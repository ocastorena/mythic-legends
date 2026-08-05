-- StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

export type Props = {
	localData: Types.LocalDataApi,
	inventoryController: Types.InventoryControllerApi,
}

local function Inventory(scope: any, props: Props): ScreenGui
	local connections: { RBXScriptConnection } = scope
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

	local Players = game:GetService("Players")
	local LocalData = props.localData

	-- Identifies this panel to ModalState, which owns the backdrop and input guard.
	local PANEL_NAME = "Inventory"

	-- Modules
	local Ui = script.Parent.Parent
	local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
	local CardList = require(Ui:WaitForChild("Components"):WaitForChild("CardList"))
	local ModalState = require(Ui:WaitForChild("State"):WaitForChild("ModalState"))
	local MythlingThumbnailUtil = require(Ui:WaitForChild("MythlingThumbnailUtil"))
	local Theme = require(Ui:WaitForChild("Theme"))
	local Panel = require(Ui:WaitForChild("Components"):WaitForChild("Panel"))
	local EquipmentPreviewUtil = require(Ui:WaitForChild("EquipmentPreviewUtil"))
	local MythlingsData =
		require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configurations"):WaitForChild("Mythlings"))
	local MaterialsMeta = require(ReplicatedStorage.Shared.Configurations.Materials)
	local EquipmentMeta = require(ReplicatedStorage.Shared.Configurations.Equipment)
	local ConsumablesMeta = require(ReplicatedStorage.Shared.Configurations.Consumables)

	-- Art already in the place file.
	local INVENTORY_ICON = "rbxassetid://135273755533681"
	local INVENTORY_TEXT_SCALE = 1.15
	local INVENTORY_CONTENT_SCALE = 1.15

	local inventoryGui = scope:New("ScreenGui")({
		Name = "InventoryGui",
		Enabled = false,
		DisplayOrder = Theme.Layer.panel,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	--- Material categories are stored lowercase, but every other label in the
	--- panel is title case, so they are capitalised for display rather than in the metadata.
	local function titleCase(value: string): string
		return (value:gsub("^%l", string.upper))
	end

	local function inventoryContentScale(viewport: Vector2): number
		return Theme.isPhone(viewport) and 1 or INVENTORY_CONTENT_SCALE
	end

	local function inventoryPanelSize(viewport: Vector2): UDim2
		if Theme.isPhone(viewport) then
			return Theme.panelSize(viewport)
		end

		-- UIScale enlarges the complete composition. Give the card its logical dimensions
		-- here so its rendered footprint still lands at the intended responsive target.
		local scale = inventoryContentScale(viewport)
		local width = math.min(math.floor(viewport.X * 0.9), 1240)
		local height = math.min(600, Theme.usableHeight(viewport) - 16)
		return UDim2.fromOffset(math.floor(width / scale), math.floor(height / scale))
	end

	--------------------------------------------------------------------------------
	-- Shell
	--------------------------------------------------------------------------------

	local panel = Panel.Create({
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
		accent = Theme.Accent.gold,
		onClose = function()
			inventoryGui.Enabled = false
		end,
	})

	local inventoryScale = Instance.new("UIScale")
	inventoryScale.Name = "ResponsiveContentScale"
	inventoryScale.Scale = inventoryContentScale(
		workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	)
	inventoryScale.Parent = panel.Card

	if workspace.CurrentCamera then
		table.insert(
			connections,
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				inventoryScale.Scale = inventoryContentScale(workspace.CurrentCamera.ViewportSize)
			end)
		)
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
		return Panel.CreateGrid(holder)
	end

	local mythlingsFrame = newGridColumn("MythlingsFrame")
	local equipmentFrame = newGridColumn("EquipmentFrame")
	local consumablesFrame = newGridColumn("ConsumablesFrame")
	local materialsFrame = newGridColumn("MaterialsFrame")

	local mythlingCardTemplate = Panel.CreateCellTemplate({
		parent = mythlingsFrame,
		check = true,
		root = panel.Root,
	})
	local materialsCardTemplate = Panel.CreateCellTemplate({
		parent = materialsFrame,
		quantity = true,
		root = panel.Root,
	})
	local equipmentCardTemplate = Panel.CreateCellTemplate({
		parent = equipmentFrame,
		quantity = true,
		check = true,
		root = panel.Root,
	})
	local consumablesCardTemplate = Panel.CreateCellTemplate({
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

	local mythlingInfo = Panel.CreateDetails({
		parent = newDetailsColumn("MythlingInfo"),
		root = panel.Root,
		accent = Theme.Accent.gold,
		stats = 3,
		info = true,
		primary = "Delete",
	})
	local materialInfo = Panel.CreateDetails({
		parent = newDetailsColumn("MaterialInfo"),
		root = panel.Root,
		accent = Theme.Accent.gold,
		stats = 2,
		info = true,
	})
	local equipmentInfo = Panel.CreateDetails({
		parent = newDetailsColumn("EquipmentInfo"),
		root = panel.Root,
		accent = Theme.Accent.gold,
		stats = 3,
		info = true,
		primary = "Equip",
	})
	local consumableInfo = Panel.CreateDetails({
		parent = newDetailsColumn("ConsumableInfo"),
		root = panel.Root,
		accent = Theme.Accent.gold,
		stats = 3,
		info = true,
	})

	-- Delete is destructive, so the footer button carries the danger accent of §01.
	if mythlingInfo.PrimaryButton then
		Panel.SetButtonEnabled(mythlingInfo.PrimaryButton, true, Theme.Accent.red)
	end

	--------------------------------------------------------------------------------
	-- Lore + confirm modals (§08)
	--------------------------------------------------------------------------------

	local loreModal = Panel.CreateModal({
		parent = inventoryGui,
		root = panel.Root,
		name = "LoreModal",
		subtitle = true,
		body = true,
	})

	local confirmModal = Panel.CreateModal({
		parent = inventoryGui,
		root = panel.Root,
		name = "ConfirmModal",
		title = "",
		body = true,
		confirm = "Delete",
		cancel = "Cancel",
		confirmTint = Theme.Accent.red,
	})
	confirmModal.IconDisc.BackgroundColor3 = Theme.Accent.red
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

	--- §05's ring rules do the highlighting now: the rarity colour is always on the cell, and
	--- selection is the difference between a 3px ring and a dimmed 2px one. The old yellow
	--- stroke told the player nothing about the card.
	---
	--- Materials have no rarity, so their cells carry a RingColor instead and keep their own
	--- identity colour when selected.
	local function setRingHighlight(card, selected: boolean)
		Panel.SetCellRing(card, card:GetAttribute("Rarity"), selected, card:GetAttribute("RingColor"))
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
		MythlingThumbnailUtil.Clear(mythlingInfo.Art)
		for _, stat in ipairs(mythlingInfo.Stats) do
			stat.Value.Text = "—"
			stat.Label.Text = ""
		end
	end

	local mythlingList = CardList.new({
		template = mythlingCardTemplate,
		parent = mythlingsFrame,
		setHighlight = setRingHighlight,
		decorate = function(card, _id, entry)
			local metadata = MythlingsData[entry.typeId]
			local variant = metadata.variants[entry.variantId]
			local preview = card:WaitForChild("2dPreview")
			MythlingThumbnailUtil.Render(preview, variant.thumbnail)
			-- Read back by setRingHighlight, which only receives the card.
			card:SetAttribute("Rarity", metadata.rarity)
			Panel.SetCellRing(card, metadata.rarity, false)

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
			MythlingThumbnailUtil.Render(mythlingInfo.Art, variant.thumbnail)
			Panel.SetHeroRarity(mythlingInfo, metadata.rarity)

			-- Current Mythling metadata does not yet expose elementId, so the produced Material's
			-- configured colour is the available identity colour for this view.
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

	local materialList = CardList.new({
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
			Panel.SetCellRing(card, nil, false, Color3.fromHex(metadata.guiColor))
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
			Theme.ring(materialInfo.Hero, tint, 3)

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

	local equipmentList = CardList.new({
		template = equipmentCardTemplate,
		parent = equipmentFrame,
		setHighlight = setRingHighlight,
		decorate = function(card, id, entry)
			local profile = EquipmentMeta.Profiles[id]
			setEquipmentPreview(card:WaitForChild("2dPreview"), profile, entry)
			card.QuantityLabel.Text = entry.quantity > 1 and `x{entry.quantity}` or ""
			card:SetAttribute("Rarity", profile.rarity or "Common")
			Panel.SetCellRing(card, profile.rarity or "Common", false)
			card.EquippedCheck.Visible = entry.equipped
		end,
		onSelect = function(id, entry)
			local profile = EquipmentMeta.Profiles[id]
			local rarity = profile.rarity or "Common"
			equipmentInfo.NameLabel.Text = profile.displayName or titleCase(id)
			setEquipmentPreview(equipmentInfo.Art, profile, entry)
			equipmentInfo.ElementIcon.BackgroundColor3 = Theme.rarityColor(rarity)
			setEquipmentPreview(equipmentInfo.ElementIcon, profile, entry)
			Panel.SetHeroRarity(equipmentInfo, rarity)

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

	local consumableList = CardList.new({
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
			Panel.SetCellRing(card, rarity, false)
		end,
		onSelect = function(id, entry)
			local metadata = getConsumableMetadata(entry.consumableId or id)
			local rarity = metadata.rarity or "Common"
			local consumableType = metadata.category or "Consumable"
			consumableInfo.NameLabel.Text = metadata.displayName or titleCase(entry.consumableId or id)
			consumableInfo.Art.Image = metadata.thumbnail or ""
			consumableInfo.ElementIcon.BackgroundColor3 = Theme.rarityColor(rarity)
			consumableInfo.ElementIcon.Image = metadata.thumbnail or ""
			Panel.SetHeroRarity(consumableInfo, rarity)
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
				`{Theme.tier(metadata.rarity)} · {material.displayName}`,
				metadata.description,
				Theme.rarityColor(metadata.rarity),
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
				`{Theme.tier(rarity)} · {profile.kind}`,
				profile.description or "Equipment used in Arena combat.",
				Theme.rarityColor(rarity),
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
				`{Theme.tier(rarity)} · {metadata.category or "Consumable"}`,
				metadata.description or "A Consumable used in the Arena.",
				Theme.rarityColor(rarity),
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

				if props.inventoryController.DeleteMythling(pendingDeleteId) then
					clearMythlingInfo()
					pendingDeleteId = nil
					closeConfirmDeleteModal()
				end
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
			Panel.SetTabActive(selectedTab, false, panel.Accent)
			selectedFrame.Parent.Visible = false
			selectedInfo.Visible = false
		end

		if tab == mythlingsTab then
			setMythlingButtons()
			Panel.SetTabActive(tab, true, panel.Accent)
			mythlingsFrame.Parent.Visible = true
			mythlingInfo.Root.Visible = true
			selectedTab = tab
			selectedFrame = mythlingsFrame
			selectedInfo = mythlingInfo.Root
		end

		if tab == materialsTab then
			setMaterialButtons()
			Panel.SetTabActive(tab, true, panel.Accent)
			materialsFrame.Parent.Visible = true
			materialInfo.Root.Visible = true
			selectedTab = tab
			selectedFrame = materialsFrame
			selectedInfo = materialInfo.Root
		end

		if tab == equipmentTab then
			Panel.SetTabActive(tab, true, panel.Accent)
			equipmentFrame.Parent.Visible = true
			equipmentInfo.Root.Visible = true
			selectedTab = tab
			selectedFrame = equipmentFrame
			selectedInfo = equipmentInfo.Root
		end

		if tab == consumablesTab then
			Panel.SetTabActive(tab, true, panel.Accent)
			consumablesFrame.Parent.Visible = true
			consumableInfo.Root.Visible = true
			selectedTab = tab
			selectedFrame = consumablesFrame
			selectedInfo = consumableInfo.Root
		end
	end

	table.insert(
		connections,
		LocalData.OnStateChanged:Connect(function(key, value)
			if key == "mythlings" then
				mythlingList:Replace(value or {})
			elseif key == "consumables" then
				consumableList:Replace(value or {})
			elseif key == "materials" then
				materialList:Replace(value or {})
			end
		end)
	)

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

	local function collectEquipment(): Types.InventoryEquipmentMap
		return props.inventoryController.RequestEquipmentSnapshot()
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

	table.insert(connections, props.inventoryController.OnEquipmentChanged:Connect(queueEquipmentRefresh))

	if equipmentInfo.PrimaryButton then
		ButtonUtil.hookClick(equipmentInfo.PrimaryButton, function()
			local id = equipmentList:GetSelectedId()
			local entry = id and equipmentList:GetData(id)
			if not entry or type(entry.instanceId) ~= "string" then
				return
			end
			if props.inventoryController.Equip(entry.instanceId) then
				equipmentList:Replace(collectEquipment())
			end
		end)
	end

	-- Inventory carries denser labels than the other panels, especially across four tabs and
	-- three-column stat rows. Increase only this menu's em-stamped typography; cloned card
	-- templates inherit the scale attribute, and Panel keeps it when device roots change.
	for _, descendant in ipairs(inventoryGui:GetDescendants()) do
		if descendant:GetAttribute("Em") then
			descendant:SetAttribute("EmScale", (descendant:GetAttribute("EmScale") or 1) * INVENTORY_TEXT_SCALE)
		end
	end
	Panel.RescaleText(inventoryGui, panel.Root)

	-- The root's Enabled property remains the open/close contract while screens move into the
	-- shared application one at a time. The HUD toggles this Rojo-owned root directly.
	table.insert(
		connections,
		inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if inventoryGui.Enabled then
				-- Claim the shared backdrop before any yielding server requests. During a direct
				-- Shop -> Inventory handoff, delaying this until after data refresh briefly left
				-- ModalState with no owners and flashed the world for one frame.
				ModalState.Open(PANEL_NAME)
				mythlingList:Replace(LocalData.Peek("mythlings") or {})
				equipmentList:Replace(collectEquipment())
				consumableList:Replace(LocalData.Peek("consumables") or {})
				materialList:Replace(LocalData.Peek("materials") or {})
				selectTab(mythlingsTab)
			else
				loreModal:Close()
				closeConfirmDeleteModal()
				ModalState.Close(PANEL_NAME)
			end
		end)
	)
	table.insert(scope, function()
		ModalState.Close(PANEL_NAME)
	end)

	return inventoryGui
end

return Inventory
