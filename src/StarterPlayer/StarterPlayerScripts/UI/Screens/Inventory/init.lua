--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(script.Parent.Parent.Parent.Types)

local Mythlings = require(script.Mythlings)
local Materials = require(script.Materials)
local Equipment = require(script.Equipment)
local Consumables = require(script.Consumables)

export type Props = {
	localData: Types.LocalDataApi,
	inventoryController: Types.InventoryControllerApi,
}

local function Inventory(scope: Fusion.Scope<typeof(Fusion)>, props: Props): ScreenGui
	local connections = scope
	--
	-- The inventory is the panel the design system was derived from, so it composes the shell
	-- verbatim: header (identity · 88px tabs · coin pill + ✕), body split grid 2/3 · details
	-- 1/3, and a details column of hero art, hero stats and a footer button.
	--
	-- Flavour text lives behind the [ i ] button, while each selected item exposes its primary
	-- action in the details footer and secondary actions through the adjacent overflow menu.

	local Players = game:GetService("Players")
	local LocalData = props.localData

	-- Identifies this panel to ModalState, which owns the backdrop and input guard.
	local PANEL_NAME = "Inventory"

	-- Modules
	local Ui = script.Parent.Parent
	local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
	local CardList = require(Ui:WaitForChild("Components"):WaitForChild("CardList"))
	local MenuState = require(Ui:WaitForChild("State"):WaitForChild("MenuState"))
	local Motion = require(Ui:WaitForChild("Motion"))
	local Theme = require(Ui:WaitForChild("Theme"))
	local ViewportUtil = require(Ui.ViewportUtil)
	local Panel = require(Ui:WaitForChild("Components"):WaitForChild("Panel"))
	local MythlingsData = require(
		ReplicatedStorage:WaitForChild("Shared")
			:WaitForChild("Configurations")
			:WaitForChild("Mythlings")
	)
	local MaterialsMeta = require(ReplicatedStorage.Shared.Configurations.Materials)
	local EquipmentMeta = require(ReplicatedStorage.Shared.Configurations.Equipment)

	local SELL_ICON = "rbxassetid://112895221053745"
	local INVENTORY_CONTENT_SCALE = 1.15

	local inventoryGui = scope:New("ScreenGui")({
		Name = "InventoryGui",
		Enabled = false,
		DisplayOrder = Theme.layer.panel,
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
		return Theme.IsPhone(viewport) and 1 or INVENTORY_CONTENT_SCALE
	end

	local function inventoryPanelSize(viewport: Vector2): UDim2
		if Theme.IsPhone(viewport) then
			return Theme.PanelSize(viewport)
		end

		-- UIScale enlarges the complete composition. Give the card its logical dimensions
		-- here so its rendered footprint still lands at the intended responsive target.
		local scale = inventoryContentScale(viewport)
		local width = math.min(math.floor(viewport.X * 0.9), 1240)
		local height = math.min(600, Theme.UsableHeight(viewport) - 16)
		return UDim2.fromOffset(math.floor(width / scale), math.floor(height / scale))
	end

	--------------------------------------------------------------------------------
	-- Shell
	--------------------------------------------------------------------------------

	local panel = Panel.Create({
		parent = inventoryGui,
		title = "Inventory",
		titleTextEm = Theme.em.panelTitleLarge,
		tabs = {
			{
				name = "Mythlings",
				icon = "rbxassetid://15909461117",
				color = Theme.tabIcon.mythlings,
			},
			{
				name = "Equipment",
				icon = "rbxassetid://16181366859",
				color = Theme.tabIcon.equipment,
			},
			{
				name = "Consumables",
				icon = "rbxassetid://16181402439",
				color = Theme.tabIcon.consumables,
			},
			{
				name = "Materials",
				icon = "rbxassetid://15562720000",
				color = Theme.tabIcon.materials,
			},
		},
		size = inventoryPanelSize,
		-- The HUD coin pill stays visible
		-- above open panels, so there is no duplicate currency display here.
		accent = Theme.accent.gold,
	})

	local inventoryScale = Instance.new("UIScale")
	inventoryScale.Name = "ResponsiveContentScale"
	inventoryScale.Scale = inventoryContentScale(
		workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	)
	inventoryScale.Parent = panel.Card

	table.insert(
		connections,
		ViewportUtil.Observe(inventoryGui, function(viewport)
			inventoryScale.Scale = inventoryContentScale(viewport)
		end)
	)

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
		local holder = Instance.new("CanvasGroup")
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
		root = panel.rootScale,
	})
	local materialsCardTemplate = Panel.CreateCellTemplate({
		parent = materialsFrame,
		quantity = true,
		root = panel.rootScale,
	})
	local equipmentCardTemplate = Panel.CreateCellTemplate({
		parent = equipmentFrame,
		quantity = true,
		check = true,
		root = panel.rootScale,
	})
	local consumablesCardTemplate = Panel.CreateCellTemplate({
		parent = consumablesFrame,
		quantity = true,
		root = panel.rootScale,
	})

	--------------------------------------------------------------------------------
	-- Details panes
	--------------------------------------------------------------------------------

	--- Both tabs get their own details column inside the shell's details slot, toggled with
	--- the grid so tab switching swaps the whole 1/3 column at once.
	local function newDetailsColumn(name: string): CanvasGroup
		local column = Instance.new("CanvasGroup")
		column.Name = name
		column.Size = UDim2.fromScale(1, 1)
		column.BackgroundTransparency = 1
		column.BorderSizePixel = 0
		column.Visible = false
		column.Parent = panel.Details
		return column
	end

	local mythlingInfoColumn = newDetailsColumn("MythlingInfo")
	local materialInfoColumn = newDetailsColumn("MaterialInfo")
	local equipmentInfoColumn = newDetailsColumn("EquipmentInfo")
	local consumableInfoColumn = newDetailsColumn("ConsumableInfo")
	local mythlingInfo = Panel.CreateDetails({
		parent = mythlingInfoColumn,
		root = panel.rootScale,
		accent = Theme.accent.gold,
		stats = 3,
		info = true,
		primary = "Evolve",
		overflow = true,
	})
	local materialInfo = Panel.CreateDetails({
		parent = materialInfoColumn,
		root = panel.rootScale,
		accent = Theme.accent.gold,
		stats = 2,
		info = true,
		overflow = true,
	})
	local equipmentInfo = Panel.CreateDetails({
		parent = equipmentInfoColumn,
		root = panel.rootScale,
		accent = Theme.accent.gold,
		stats = 3,
		info = true,
		primary = "Equip",
		overflow = true,
	})
	local consumableInfo = Panel.CreateDetails({
		parent = consumableInfoColumn,
		root = panel.rootScale,
		accent = Theme.accent.gold,
		stats = 3,
		info = true,
		primary = "Add to Hotbar",
		overflow = true,
	})

	-- These primary actions are present now so the hierarchy is stable while their
	-- server-authoritative endpoints are added later. Equipment already has a live endpoint.
	if mythlingInfo.PrimaryButton then
		mythlingInfo.PrimaryButton:SetAttribute("ServerAction", "Evolve")
		Panel.SetButtonEnabled(mythlingInfo.PrimaryButton, false, Theme.tabIcon.mythlings)
	end
	if equipmentInfo.PrimaryButton then
		equipmentInfo.PrimaryButton:SetAttribute("ServerAction", "EquipOrUnequip")
	end
	if consumableInfo.PrimaryButton then
		consumableInfo.PrimaryButton:SetAttribute("ServerAction", "AddToHotbar")
		Panel.SetButtonEnabled(consumableInfo.PrimaryButton, false, Theme.tabIcon.consumables)
	end

	local actionMenu = Panel.CreateActionMenu({
		parent = panel.Details,
		root = panel.rootScale,
		items = {
			{
				id = "Sell",
				label = "Sell",
				icon = SELL_ICON,
				iconColor = Theme.accent.gold,
				enabled = false,
			},
		},
	})
	actionMenu.Options.Sell:SetAttribute("ServerAction", "Sell")

	local function connectOverflow(details: Panel.Details, category: string)
		local button = details.SecondaryButton
		if not button then
			return
		end
		button:SetAttribute("InventoryCategory", category)
		ButtonUtil.HookClick(button, function()
			actionMenu.Root:SetAttribute("InventoryCategory", category)
			actionMenu.Toggle(button)
		end)
	end

	connectOverflow(mythlingInfo, "Mythlings")
	connectOverflow(equipmentInfo, "Equipment")
	connectOverflow(consumableInfo, "Consumables")
	connectOverflow(materialInfo, "Materials")

	for _, details in ipairs({ mythlingInfo, equipmentInfo, consumableInfo, materialInfo }) do
		if details.Footer then
			details.Footer.Visible = false
		end
	end

	local function showActions(details: Panel.Details)
		if details.Footer then
			details.Footer.Visible = true
		end
		actionMenu.Close()
	end

	--------------------------------------------------------------------------------
	-- Lore modal
	--------------------------------------------------------------------------------

	local loreModal = Panel.CreateModal({
		parent = inventoryGui,
		root = panel.rootScale,
		name = "LoreModal",
		subtitle = true,
		body = true,
	})

	--------------------------------------------------------------------------------
	-- State
	--------------------------------------------------------------------------------

	local selectedTab: TextButton? = nil

	--- Rarity colour is always visible on the cell, and
	--- selection is the difference between a 3px ring and a dimmed 2px one. The old yellow
	--- stroke told the player nothing about the card.
	---
	--- Materials have no rarity, so their cells carry a RingColor instead and keep their own
	--- identity colour when selected.
	local mythlingList = Mythlings.Create({
		template = mythlingCardTemplate,
		parent = mythlingsFrame,
		details = mythlingInfo,
		onSelected = showActions,
	})

	local materialList = Materials.Create({
		template = materialsCardTemplate,
		parent = materialsFrame,
		details = materialInfo,
		onSelected = showActions,
	})

	local equipmentList = Equipment.Create({
		template = equipmentCardTemplate,
		parent = equipmentFrame,
		details = equipmentInfo,
		onSelected = showActions,
	})

	local consumableList = Consumables.Create({
		template = consumablesCardTemplate,
		parent = consumablesFrame,
		details = consumableInfo,
		onSelected = showActions,
	})

	local function newTabConfig<T>(
		list: CardList.List<T>,
		gridPage: GuiObject,
		detailsPage: GuiObject,
		category: string,
		icon: string,
		color: Color3,
		title: string,
		body: string
	)
		local emptyState = Panel.CreateEmptyState({
			parent = panel.Content,
			root = panel.rootScale,
		})
		emptyState.Root.Name = `{category}EmptyState`
		emptyState.Root:SetAttribute("InventoryCategory", category)
		emptyState.IconDisc.BackgroundColor3 = color
		emptyState.Icon.Image = icon
		emptyState.Icon.ImageColor3 = color
		emptyState.TitleLabel.Text = title
		emptyState.BodyLabel.Text = body

		return {
			isEmpty = function()
				return list:GetSelectedId() == nil
			end,
			gridPage = gridPage,
			detailsPage = detailsPage,
			emptyState = emptyState,
		}
	end

	type TabConfig = {
		isEmpty: () -> boolean,
		gridPage: GuiObject,
		detailsPage: GuiObject,
		emptyState: Panel.EmptyStateView,
	}
	local emptyStateByTab: { [TextButton]: TabConfig } = {
		[mythlingsTab] = newTabConfig(
			mythlingList,
			mythlingsFrame.Parent :: GuiObject,
			mythlingInfoColumn,
			"Mythlings",
			"rbxassetid://15909461117",
			Theme.tabIcon.mythlings,
			"No Mythlings yet",
			"Capture Mythlings in the Arena."
		),
		[equipmentTab] = newTabConfig(
			equipmentList,
			equipmentFrame.Parent :: GuiObject,
			equipmentInfoColumn,
			"Equipment",
			"rbxassetid://16181366859",
			Theme.tabIcon.equipment,
			"No Equipment yet",
			"Craft Equipment at a Crafting Station."
		),
		[consumablesTab] = newTabConfig(
			consumableList,
			consumablesFrame.Parent :: GuiObject,
			consumableInfoColumn,
			"Consumables",
			"rbxassetid://16181402439",
			Theme.tabIcon.consumables,
			"No Consumables yet",
			"Craft Consumables at a Crafting Station."
		),
		[materialsTab] = newTabConfig(
			materialList,
			materialsFrame.Parent :: GuiObject,
			materialInfoColumn,
			"Materials",
			"rbxassetid://15562720000",
			Theme.tabIcon.materials,
			"No Materials yet",
			"Assign Mythlings to Shrines and collect their output."
		),
	}

	local transitionGeneration = 0
	local cancelTabTransition: (() -> ())? = nil
	local function cancelTab()
		if cancelTabTransition then
			cancelTabTransition()
			cancelTabTransition = nil
		end
	end
	table.insert(scope, cancelTab)

	local function isEmpty(config: TabConfig): boolean
		return config.isEmpty()
	end

	local function tabObjects(config: TabConfig): { GuiObject }
		if isEmpty(config) then
			return { config.emptyState.Root }
		end
		return { config.gridPage, config.detailsPage }
	end

	local function refreshEmptyState()
		cancelTab()
		transitionGeneration += 1
		for _, config in pairs(emptyStateByTab) do
			config.gridPage.Visible = false
			config.detailsPage.Visible = false
			config.emptyState.Root.Visible = false
		end

		local config = selectedTab and emptyStateByTab[selectedTab]
		if not config then
			Panel.SetDetailsVisible(panel, true)
			return
		end

		local empty = isEmpty(config)
		Panel.SetDetailsVisible(panel, not empty)
		if empty then
			actionMenu.Close()
			config.emptyState.Root.Visible = true
		else
			config.gridPage.Visible = true
			config.detailsPage.Visible = true
		end
	end

	--- The [ i ] button on each hero frame opens the lore modal, which is the only place
	--- flavour text appears.
	local function openLore(
		title: string,
		subtitle: string,
		body: string,
		tint: Color3,
		icon: string
	)
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
		ButtonUtil.HookClick(mythlingInfo.InfoButton, function()
			local id = mythlingList:GetSelectedId()
			local entry = id and mythlingList:GetData(id)
			if not entry then
				return
			end
			local metadata = MythlingsData[entry.typeId]
			local material = MaterialsMeta[metadata.production.materialId]
			openLore(
				metadata.displayName,
				`{Theme.Tier(metadata.rarity)} · {material.displayName}`,
				metadata.description,
				Theme.RarityColor(metadata.rarity),
				metadata.variants[entry.variantId].thumbnail
			)
		end)
	end

	if materialInfo.InfoButton then
		ButtonUtil.HookClick(materialInfo.InfoButton, function()
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
		ButtonUtil.HookClick(equipmentInfo.InfoButton, function()
			local id = equipmentList:GetSelectedId()
			local entry = id and equipmentList:GetData(id)
			local profile = id and EquipmentMeta.profiles[id]
			if not id or not profile or not entry then
				return
			end
			local rarity = profile.rarity or "Common"
			openLore(
				profile.displayName or titleCase(id),
				`{Theme.Tier(rarity)} · {profile.kind}`,
				profile.description or "Equipment used in Arena combat.",
				Theme.RarityColor(rarity),
				Equipment.Thumbnail(profile, entry)
			)
		end)
	end

	if consumableInfo.InfoButton then
		ButtonUtil.HookClick(consumableInfo.InfoButton, function()
			local id = consumableList:GetSelectedId()
			local entry = id and consumableList:GetData(id)
			if not id or not entry then
				return
			end
			local metadata = entry and Consumables.GetMetadata(entry.consumableId or id)
			if not metadata then
				return
			end
			local rarity = metadata.rarity or "Common"
			openLore(
				metadata.displayName or titleCase(entry.consumableId or id),
				`{Theme.Tier(rarity)} · {metadata.category or "Consumable"}`,
				metadata.description or "A Consumable used in the Arena.",
				Theme.RarityColor(rarity),
				metadata.thumbnail or ""
			)
		end)
	end

	--------------------------------------------------------------------------------
	-- Tabs
	--------------------------------------------------------------------------------

	local function selectTab(tab: TextButton, skipAnimation: boolean?)
		if selectedTab == tab then
			refreshEmptyState()
			return
		end

		local nextConfig = emptyStateByTab[tab]
		if not nextConfig then
			return
		end

		cancelTab()
		local previousTab = selectedTab
		local previousConfig = previousTab and emptyStateByTab[previousTab]
		if previousTab then
			Panel.SetTabActive(previousTab, false, panel.accent)
		end

		actionMenu.Close()
		Panel.SetTabActive(tab, true, panel.accent)
		selectedTab = tab
		transitionGeneration += 1
		local generation = transitionGeneration

		if previousTab and previousConfig and not skipAnimation then
			local nextIsEmpty = isEmpty(nextConfig)
			if not nextIsEmpty then
				Panel.SetDetailsVisible(panel, true)
			end

			local direction = if previousTab.LayoutOrder < tab.LayoutOrder then 1 else -1
			cancelTabTransition = Motion.TransitionTab(
				tabObjects(previousConfig),
				tabObjects(nextConfig),
				direction,
				function()
					if transitionGeneration == generation and selectedTab == tab then
						Panel.SetDetailsVisible(panel, not nextIsEmpty)
					end
				end
			)
		else
			refreshEmptyState()
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
			else
				return
			end
			refreshEmptyState()
		end)
	)

	ButtonUtil.HookClick(mythlingsTab, function()
		selectTab(mythlingsTab)
	end)

	ButtonUtil.HookClick(materialsTab, function()
		selectTab(materialsTab)
	end)

	ButtonUtil.HookClick(equipmentTab, function()
		selectTab(equipmentTab)
	end)

	ButtonUtil.HookClick(consumablesTab, function()
		selectTab(consumablesTab)
	end)

	local equipmentSession = props.inventoryController.BindEquipmentView({
		isVisible = function()
			return inventoryGui.Enabled
		end,
		onSnapshot = function(equipment)
			equipmentList:Replace(equipment)
			refreshEmptyState()
		end,
	})
	table.insert(scope, equipmentSession.Destroy)

	if equipmentInfo.PrimaryButton then
		ButtonUtil.HookClick(equipmentInfo.PrimaryButton, function()
			local id = equipmentList:GetSelectedId()
			local entry = if id then equipmentList:GetData(id) else nil
			if entry and not entry.equipped and entry.instanceId then
				equipmentSession.Equip(entry.instanceId)
			end
		end)
	end
	-- Cloned card templates inherit the shared scale attributes, and Panel preserves them
	-- when a viewport change supplies a new device text root.
	Panel.ApplyTextScale(inventoryGui, panel.rootScale, Theme.menuTextScale)

	local menuTransition = Motion.CreateMenuTransition({
		screenGui = inventoryGui,
		motionRoot = panel.MotionRoot,
		panelName = PANEL_NAME,
		onOpen = function()
			mythlingList:Replace(LocalData.Peek("mythlings") or {})
			equipmentSession.Refresh()
			consumableList:Replace(LocalData.Peek("consumables") or {})
			materialList:Replace(LocalData.Peek("materials") or {})
			selectTab(mythlingsTab, true)
		end,
		onCloseStart = function()
			equipmentSession.Close()
			cancelTab()
			loreModal:Close()
			actionMenu.Close()
		end,
	})
	local unregisterMenu = MenuState.Register(PANEL_NAME, menuTransition)
	table.insert(scope, unregisterMenu)
	table.insert(scope, menuTransition.Destroy)

	return inventoryGui
end

return Inventory
