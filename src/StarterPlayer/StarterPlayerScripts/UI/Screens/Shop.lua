--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Shop

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local Players = game:GetService("Players")

local Ui = script.Parent.Parent
local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
local MenuState = require(Ui:WaitForChild("State"):WaitForChild("MenuState"))
local Motion = require(Ui:WaitForChild("Motion"))
local Panel = require(Ui:WaitForChild("Components"):WaitForChild("Panel"))
local Theme = require(Ui:WaitForChild("Theme"))

local PANEL_NAME = "Shop"
local SHOP_ICON = "rbxassetid://9405933217"
local GOLD_ICON = "rbxassetid://112895221053745"
local SHOP_CONTENT_SCALE = 1.15

local function contentScale(viewport: Vector2): number
	return if Theme.IsPhone(viewport) then 1 else SHOP_CONTENT_SCALE
end

local function panelSize(viewport: Vector2): UDim2
	if Theme.IsPhone(viewport) then
		return Theme.PanelSize(viewport)
	end

	local scale = contentScale(viewport)
	local width = math.min(math.floor(viewport.X * 0.9), 1240)
	local height = math.min(600, Theme.UsableHeight(viewport) - 16)
	return UDim2.fromOffset(math.floor(width / scale), math.floor(height / scale))
end

local function Shop(scope: Fusion.Scope<typeof(Fusion)>): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local shopGui = scope:New("ScreenGui")({
		Name = "ShopGui",
		Enabled = false,
		DisplayOrder = Theme.layer.panel,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local panel = Panel.Create({
		parent = shopGui,
		title = "Shop",
		titleTextEm = Theme.em.panelTitleLarge,
		tabs = {
			{
				name = "Featured",
				icon = "rbxassetid://15909461117",
				color = Theme.tabIcon.featured,
			},
			{
				name = "Upgrades",
				icon = "rbxassetid://12338897538",
				color = Theme.tabIcon.upgrades,
			},
		},
		size = panelSize,
		accent = Theme.accent.green,
	})

	local camera = workspace.CurrentCamera
	local initialViewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local responsiveScale = Instance.new("UIScale")
	responsiveScale.Name = "ResponsiveContentScale"
	responsiveScale.Scale = contentScale(initialViewport)
	responsiveScale.Parent = panel.Card
	if camera then
		table.insert(
			scope,
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				responsiveScale.Scale = contentScale(camera.ViewportSize)
			end)
		)
	end

	local offerInfoColumn = Instance.new("CanvasGroup")
	offerInfoColumn.Name = "OfferInfo"
	offerInfoColumn.Size = UDim2.fromScale(1, 1)
	offerInfoColumn.BackgroundTransparency = 1
	offerInfoColumn.BorderSizePixel = 0
	offerInfoColumn.Parent = panel.Details
	local offerInfo = Panel.CreateDetails({
		parent = offerInfoColumn,
		root = panel.rootScale,
		accent = Theme.accent.green,
		stats = 2,
		primary = "Purchase",
	})
	offerInfo.NameLabel.Text = "No offer selected"
	offerInfo.RarityLabel.Text = "Catalog unavailable"
	offerInfo.RarityLabel.TextColor3 = Theme.textColors.dim
	offerInfo.Art.Image = SHOP_ICON
	offerInfo.Art.ImageColor3 = Theme.accent.green
	offerInfo.ElementIcon.BackgroundColor3 = Theme.accent.gold
	offerInfo.ElementIcon.Image = GOLD_ICON
	offerInfo.Stats[1].Value.Text = "—"
	offerInfo.Stats[1].Label.Text = "Price"
	offerInfo.Stats[2].Value.Text = "—"
	offerInfo.Stats[2].Label.Text = "Availability"
	if offerInfo.PrimaryButton then
		offerInfo.PrimaryButton:SetAttribute("ServerAction", "PurchaseOffer")
		Panel.SetButtonEnabled(offerInfo.PrimaryButton, false, Theme.tabIcon.featured)
	end
	Panel.SetDetailsVisible(panel, false)

	local selectedTab: TextButton? = nil
	local function newEmptyTabConfig(category, icon, color, title, body, primary, action)
		local emptyState = Panel.CreateEmptyState({
			parent = panel.Content,
			root = panel.rootScale,
		})
		emptyState.Root.Name = `{category}EmptyState`
		emptyState.Root:SetAttribute("ShopCategory", category)
		emptyState.IconDisc.BackgroundColor3 = color
		emptyState.Icon.Image = icon
		emptyState.Icon.ImageColor3 = color
		emptyState.TitleLabel.Text = title
		emptyState.BodyLabel.Text = body

		return {
			emptyState = emptyState,
			primary = primary,
			action = action,
			color = color,
		}
	end

	local emptyStateByTab = {
		[panel.Tabs.Featured] = newEmptyTabConfig(
			"Featured",
			"rbxassetid://15909461117",
			Theme.tabIcon.featured,
			"No Featured offers yet",
			"Check back later for new Shop offers.",
			"Purchase",
			"PurchaseOffer"
		),
		[panel.Tabs.Upgrades] = newEmptyTabConfig(
			"Upgrades",
			"rbxassetid://12338897538",
			Theme.tabIcon.upgrades,
			"No Upgrades available",
			"Check back later for new Inventory upgrades.",
			"Upgrade",
			"PurchaseUpgrade"
		),
	}

	local function applyAction(tab: TextButton)
		local config = emptyStateByTab[tab]
		if not config then
			return
		end

		Panel.SetDetailsVisible(panel, false)
		if offerInfo.PrimaryButton then
			offerInfo.PrimaryButton.Text = config.primary
			offerInfo.PrimaryButton:SetAttribute("ServerAction", config.action)
			Panel.SetButtonEnabled(offerInfo.PrimaryButton, false, config.color)
		end
	end

	local cancelTabTransition: (() -> ())? = nil
	local function cancelTab()
		if cancelTabTransition then
			cancelTabTransition()
			cancelTabTransition = nil
		end
	end
	table.insert(scope, cancelTab)
	local function selectTab(tab: TextButton, skipAnimation: boolean?)
		if selectedTab == tab then
			applyAction(tab)
			return
		end
		cancelTab()
		local previousTab = selectedTab
		local previousConfig = previousTab and emptyStateByTab[previousTab]
		local nextConfig = emptyStateByTab[tab]
		if not nextConfig then
			return
		end
		if selectedTab then
			Panel.SetTabActive(selectedTab, false, panel.accent)
		end
		selectedTab = tab
		Panel.SetTabActive(tab, true, panel.accent)
		applyAction(tab)

		if previousTab and previousConfig and not skipAnimation then
			local direction = if previousTab.LayoutOrder < tab.LayoutOrder then 1 else -1
			cancelTabTransition = Motion.TransitionTab(
				{ previousConfig.emptyState.Root },
				{ nextConfig.emptyState.Root },
				direction
			)
		else
			for _, config in pairs(emptyStateByTab) do
				config.emptyState.Root.Visible = false
			end
			nextConfig.emptyState.Root.Visible = true
		end
	end

	ButtonUtil.HookClick(panel.Tabs.Featured, function()
		selectTab(panel.Tabs.Featured)
	end)
	ButtonUtil.HookClick(panel.Tabs.Upgrades, function()
		selectTab(panel.Tabs.Upgrades)
	end)

	Panel.ApplyTextScale(shopGui, panel.rootScale, Theme.menuTextScale)

	local menuTransition = Motion.CreateMenuTransition({
		screenGui = shopGui,
		motionRoot = panel.MotionRoot,
		panelName = PANEL_NAME,
		onOpen = function()
			selectTab(panel.Tabs.Featured, true)
		end,
	})
	local unregisterMenu = MenuState.Register(PANEL_NAME, menuTransition)
	table.insert(scope, unregisterMenu)
	table.insert(scope, menuTransition.Destroy)

	return shopGui
end

return Shop
