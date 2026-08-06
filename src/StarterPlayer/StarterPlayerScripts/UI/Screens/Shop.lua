-- StarterPlayer/StarterPlayerScripts/UI/Screens/Shop

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
	return if Theme.isPhone(viewport) then 1 else SHOP_CONTENT_SCALE
end

local function panelSize(viewport: Vector2): UDim2
	if Theme.isPhone(viewport) then
		return Theme.panelSize(viewport)
	end

	local scale = contentScale(viewport)
	local width = math.min(math.floor(viewport.X * 0.9), 1240)
	local height = math.min(600, Theme.usableHeight(viewport) - 16)
	return UDim2.fromOffset(math.floor(width / scale), math.floor(height / scale))
end

local function Shop(scope: any): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local shopGui = scope:New("ScreenGui")({
		Name = "ShopGui",
		Enabled = false,
		DisplayOrder = Theme.Layer.panel,
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
		titleTextEm = Theme.Em.panelTitleLarge,
		tabs = {
			{ name = "Featured", icon = "rbxassetid://15909461117", color = Theme.TabIcon.featured },
			{ name = "Upgrades", icon = "rbxassetid://12338897538", color = Theme.TabIcon.upgrades },
		},
		size = panelSize,
		accent = Theme.Accent.green,
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

	local emptyState = Panel.CreateEmptyState({
		parent = panel.Grid,
		root = panel.Root,
	})

	local offerInfoColumn = Instance.new("CanvasGroup")
	offerInfoColumn.Name = "OfferInfo"
	offerInfoColumn.Size = UDim2.fromScale(1, 1)
	offerInfoColumn.BackgroundTransparency = 1
	offerInfoColumn.BorderSizePixel = 0
	offerInfoColumn.Parent = panel.Details
	local offerInfo = Panel.CreateDetails({
		parent = offerInfoColumn,
		root = panel.Root,
		accent = Theme.Accent.green,
		stats = 2,
		primary = "Purchase",
	})
	offerInfo.NameLabel.Text = "No offer selected"
	offerInfo.RarityLabel.Text = "Catalog unavailable"
	offerInfo.RarityLabel.TextColor3 = Theme.Text.dim
	offerInfo.Art.Image = SHOP_ICON
	offerInfo.Art.ImageColor3 = Theme.Accent.green
	offerInfo.ElementIcon.BackgroundColor3 = Theme.Accent.gold
	offerInfo.ElementIcon.Image = GOLD_ICON
	offerInfo.Stats[1].Value.Text = "—"
	offerInfo.Stats[1].Label.Text = "Price"
	offerInfo.Stats[2].Value.Text = "—"
	offerInfo.Stats[2].Label.Text = "Availability"
	if offerInfo.PrimaryButton then
		offerInfo.PrimaryButton:SetAttribute("ServerAction", "PurchaseOffer")
		Panel.SetButtonEnabled(offerInfo.PrimaryButton, false, Theme.TabIcon.featured)
	end
	Panel.SetDetailsVisible(panel, false)

	local selectedTab: TextButton? = nil
	local emptyStateByTab = {
		[panel.Tabs.Featured] = {
			category = "Featured",
			icon = "rbxassetid://15909461117",
			color = Theme.TabIcon.featured,
			title = "No Featured offers yet",
			body = "Check back later for new Shop offers.",
			primary = "Purchase",
			action = "PurchaseOffer",
		},
		[panel.Tabs.Upgrades] = {
			category = "Upgrades",
			icon = "rbxassetid://12338897538",
			color = Theme.TabIcon.upgrades,
			title = "No Upgrades available",
			body = "Check back later for new Inventory upgrades.",
			primary = "Upgrade",
			action = "PurchaseUpgrade",
		},
	}

	local function replaceContent(tab: TextButton)
		local config = emptyStateByTab[tab]
		if not config then
			return
		end

		emptyState.Root.Visible = true
		emptyState.Root:SetAttribute("ShopCategory", config.category)
		emptyState.IconDisc.BackgroundColor3 = config.color
		emptyState.Icon.Image = config.icon
		emptyState.Icon.ImageColor3 = config.color
		emptyState.TitleLabel.Text = config.title
		emptyState.BodyLabel.Text = config.body
		Panel.SetDetailsVisible(panel, false)
		if offerInfo.PrimaryButton then
			offerInfo.PrimaryButton.Text = config.primary
			offerInfo.PrimaryButton:SetAttribute("ServerAction", config.action)
			Panel.SetButtonEnabled(offerInfo.PrimaryButton, false, config.color)
		end
	end

	local function selectTab(tab: TextButton, skipAnimation: boolean?)
		if selectedTab == tab then
			replaceContent(tab)
			return
		end
		local previousTab = selectedTab
		if selectedTab then
			Panel.SetTabActive(selectedTab, false, panel.Accent)
		end
		selectedTab = tab
		Panel.SetTabActive(tab, true, panel.Accent)

		if previousTab and not skipAnimation then
			local direction = if previousTab.LayoutOrder < tab.LayoutOrder then 1 else -1
			Motion.ReplaceTabContent({ emptyState.Root }, direction, function()
				replaceContent(tab)
			end)
		else
			replaceContent(tab)
		end
	end

	ButtonUtil.hookClick(panel.Tabs.Featured, function()
		selectTab(panel.Tabs.Featured)
	end)
	ButtonUtil.hookClick(panel.Tabs.Upgrades, function()
		selectTab(panel.Tabs.Upgrades)
	end)

	Panel.ApplyTextScale(shopGui, panel.Root, Theme.MenuTextScale)

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
