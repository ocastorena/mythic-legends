-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/ShopController

local ShopController = {}

function ShopController.Start(_context: any)
--
-- The Shop shares the Inventory panel anatomy: identity and tabs in the header, a
-- two-thirds catalog grid, and a one-third offer details pane. Exact launch offers and
-- prices are intentionally not defined yet, so this controller presents the finished
-- shell in a safe unavailable state rather than inventing client-side economy data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PANEL_NAME = "Shop"
local SHOP_ICON = "rbxassetid://9405933217"
local RUNIES_ICON = "rbxassetid://112895221053745"
local SHOP_TEXT_SCALE = 1.15
local SHOP_CONTENT_SCALE = 1.15

local Client = script:FindFirstAncestor("ClientModules")
local Ui = Client:WaitForChild("UI")
local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
local ModalUtil = require(Ui:WaitForChild("ModalUtil"))
local PanelUtil = require(Ui:WaitForChild("PanelUtil"))
local ThemeUtil = require(Ui:WaitForChild("ThemeUtil"))

local shopGui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("ShopGui")
shopGui.DisplayOrder = ThemeUtil.Layer.panel

local function contentScale(viewport: Vector2): number
	return ThemeUtil.isPhone(viewport) and 1 or SHOP_CONTENT_SCALE
end

local function panelSize(viewport: Vector2): UDim2
	if ThemeUtil.isPhone(viewport) then
		return ThemeUtil.panelSize(viewport)
	end

	local scale = contentScale(viewport)
	local width = math.min(math.floor(viewport.X * 0.9), 1240)
	local height = math.min(600, ThemeUtil.usableHeight(viewport) - 16)
	return UDim2.fromOffset(math.floor(width / scale), math.floor(height / scale))
end

for _, child in ipairs(shopGui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

local panel = PanelUtil.panel({
	parent = shopGui,
	title = "Shop",
	titleIcon = SHOP_ICON,
	tabs = { "Featured", "Upgrades" },
	size = panelSize,
	accent = ThemeUtil.Accent.green,
	onClose = function()
		shopGui.Enabled = false
	end,
})

local responsiveScale = Instance.new("UIScale")
responsiveScale.Name = "ResponsiveContentScale"
responsiveScale.Scale = contentScale(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720))
responsiveScale.Parent = panel.Card

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		responsiveScale.Scale = contentScale(workspace.CurrentCamera.ViewportSize)
	end)
end

--------------------------------------------------------------------------------
-- Empty catalog
--------------------------------------------------------------------------------

local catalog = Instance.new("Frame")
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
emptyTitle.FontFace = ThemeUtil.Font.extraBold
emptyTitle.Text = "New offers are on the way"
emptyTitle.TextColor3 = ThemeUtil.Text.strong
emptyTitle:SetAttribute("Em", ThemeUtil.Em.itemName)
emptyTitle.TextSize = ThemeUtil.text(ThemeUtil.Em.itemName, panel.Root)
emptyTitle.TextXAlignment = Enum.TextXAlignment.Center
emptyTitle.Parent = emptyState

local emptyBody = Instance.new("TextLabel")
emptyBody.Name = "Body"
emptyBody.Position = UDim2.fromOffset(0, 38)
emptyBody.Size = UDim2.new(1, 0, 0, 44)
emptyBody.BackgroundTransparency = 1
emptyBody.FontFace = ThemeUtil.Font.bold
emptyBody.Text = "Featured purchases will appear here when the shop catalog is configured."
emptyBody.TextColor3 = ThemeUtil.Text.dim
emptyBody:SetAttribute("Em", ThemeUtil.Em.body)
emptyBody.TextSize = ThemeUtil.text(ThemeUtil.Em.body, panel.Root)
emptyBody.TextWrapped = true
emptyBody.TextXAlignment = Enum.TextXAlignment.Center
emptyBody.TextYAlignment = Enum.TextYAlignment.Top
emptyBody.Parent = emptyState

local offerInfo = PanelUtil.details({
	parent = panel.Details,
	root = panel.Root,
	accent = ThemeUtil.Accent.green,
	stats = 2,
	primary = "Purchase",
})
offerInfo.NameLabel.Text = "No offer selected"
offerInfo.RarityLabel.Text = "Catalog unavailable"
offerInfo.RarityLabel.TextColor3 = ThemeUtil.Text.dim
offerInfo.Art.Image = SHOP_ICON
offerInfo.Art.ImageColor3 = ThemeUtil.Accent.green
offerInfo.ElementIcon.BackgroundColor3 = ThemeUtil.Accent.gold
offerInfo.ElementIcon.Image = RUNIES_ICON
offerInfo.Stats[1].Value.Text = "—"
offerInfo.Stats[1].Label.Text = "Price"
offerInfo.Stats[2].Value.Text = "—"
offerInfo.Stats[2].Label.Text = "Availability"

if offerInfo.PrimaryButton then
	PanelUtil.setButtonEnabled(offerInfo.PrimaryButton, false, ThemeUtil.Accent.green)
end

--------------------------------------------------------------------------------
-- Tabs and lifecycle
--------------------------------------------------------------------------------

local selectedTab: TextButton? = nil

local function selectTab(tab: TextButton)
	if selectedTab == tab then
		return
	end
	if selectedTab then
		PanelUtil.setTabActive(selectedTab, false, panel.Accent)
	end
	selectedTab = tab
	PanelUtil.setTabActive(tab, true, panel.Accent)

	if tab == panel.Tabs.Upgrades then
		emptyTitle.Text = "Inventory upgrades are on the way"
		emptyBody.Text = "Capacity upgrades will appear here when their prices and eligibility are configured."
	else
		emptyTitle.Text = "New offers are on the way"
		emptyBody.Text = "Featured purchases will appear here when the shop catalog is configured."
	end
end

ButtonUtil.hookClick(panel.Tabs.Featured, function()
	selectTab(panel.Tabs.Featured)
end)
ButtonUtil.hookClick(panel.Tabs.Upgrades, function()
	selectTab(panel.Tabs.Upgrades)
end)

for _, descendant in ipairs(shopGui:GetDescendants()) do
	if descendant:GetAttribute("Em") then
		descendant:SetAttribute("EmScale", (descendant:GetAttribute("EmScale") or 1) * SHOP_TEXT_SCALE)
	end
end
PanelUtil.rescaleText(shopGui, panel.Root)

shopGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if shopGui.Enabled then
		selectTab(panel.Tabs.Featured)
		ModalUtil.Open(PANEL_NAME)
	else
		ModalUtil.Close(PANEL_NAME)
	end
end)

if shopGui.Enabled then
	selectTab(panel.Tabs.Featured)
	ModalUtil.Open(PANEL_NAME)
end
end

function ShopController.Destroy()
end

return ShopController
