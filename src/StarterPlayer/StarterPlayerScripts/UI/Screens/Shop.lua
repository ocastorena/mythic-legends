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
local SHOP_TEXT_SCALE = 1.15
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
		titleIcon = SHOP_ICON,
		tabs = {
			{ name = "Featured", glyph = "★" },
			{ name = "Upgrades", glyph = "↑" },
		},
		size = panelSize,
		accent = Theme.Accent.green,
		onClose = function()
			MenuState.Close(PANEL_NAME)
		end,
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

	local catalog = Instance.new("CanvasGroup")
	catalog.Name = "Catalog"
	catalog.Size = UDim2.fromScale(1, 1)
	catalog.BackgroundTransparency = 1
	catalog.Parent = panel.Grid

	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyState.Position = UDim2.fromScale(0.5, 0.5)
	emptyState.Size = UDim2.new(1, -32, 0, 96)
	emptyState.BackgroundTransparency = 1
	emptyState.Parent = catalog

	local emptyTitle = Instance.new("TextLabel")
	emptyTitle.Name = "Title"
	emptyTitle.Size = UDim2.new(1, 0, 0, 34)
	emptyTitle.BackgroundTransparency = 1
	emptyTitle.FontFace = Theme.Font.extraBold
	emptyTitle.Text = "New offers are on the way"
	emptyTitle.TextColor3 = Theme.Text.strong
	emptyTitle:SetAttribute("Em", Theme.Em.itemName)
	emptyTitle.TextSize = Theme.text(Theme.Em.itemName, panel.Root)
	emptyTitle.TextXAlignment = Enum.TextXAlignment.Center
	emptyTitle.Parent = emptyState

	local emptyBody = Instance.new("TextLabel")
	emptyBody.Name = "Body"
	emptyBody.Position = UDim2.fromOffset(0, 38)
	emptyBody.Size = UDim2.new(1, 0, 0, 44)
	emptyBody.BackgroundTransparency = 1
	emptyBody.FontFace = Theme.Font.bold
	emptyBody.Text = "Featured purchases will appear here when the shop catalog is configured."
	emptyBody.TextColor3 = Theme.Text.dim
	emptyBody:SetAttribute("Em", Theme.Em.body)
	emptyBody.TextSize = Theme.text(Theme.Em.body, panel.Root)
	emptyBody.TextWrapped = true
	emptyBody.TextXAlignment = Enum.TextXAlignment.Center
	emptyBody.TextYAlignment = Enum.TextYAlignment.Top
	emptyBody.Parent = emptyState

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
		Panel.SetButtonEnabled(offerInfo.PrimaryButton, false, Theme.Accent.green)
	end

	local selectedTab: TextButton? = nil
	local function selectTab(tab: TextButton, skipAnimation: boolean?)
		if selectedTab == tab then
			return
		end
		local previousTab = selectedTab
		if selectedTab then
			Panel.SetTabActive(selectedTab, false, panel.Accent)
		end
		selectedTab = tab
		Panel.SetTabActive(tab, true, panel.Accent)

		local function replaceContent()
			if tab == panel.Tabs.Upgrades then
				emptyTitle.Text = "Inventory upgrades are on the way"
				emptyBody.Text = "Capacity upgrades will appear here when their prices and eligibility are configured."
			else
				emptyTitle.Text = "New offers are on the way"
				emptyBody.Text = "Featured purchases will appear here when the shop catalog is configured."
			end
		end

		if previousTab and not skipAnimation then
			local direction = if previousTab.LayoutOrder < tab.LayoutOrder then 1 else -1
			Motion.ReplaceTabContent({ catalog, offerInfoColumn }, direction, replaceContent)
		else
			replaceContent()
		end
	end

	ButtonUtil.hookClick(panel.Tabs.Featured, function()
		selectTab(panel.Tabs.Featured)
	end)
	ButtonUtil.hookClick(panel.Tabs.Upgrades, function()
		selectTab(panel.Tabs.Upgrades)
	end)

	for _, descendant in shopGui:GetDescendants() do
		if descendant:GetAttribute("Em") then
			descendant:SetAttribute("EmScale", (descendant:GetAttribute("EmScale") or 1) * SHOP_TEXT_SCALE)
		end
	end
	Panel.RescaleText(shopGui, panel.Root)

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
