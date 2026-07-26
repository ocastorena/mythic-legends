-- StarterGui/MainGui/HudController
-- Owns every widget in MainGui: the always-on-screen HUD.
--
-- The inventory open button lives in MainGui but used to be hooked by InventoryController
-- reaching across into another ScreenGui. MainGui owns its own button now and asks for the
-- inventory by toggling that ScreenGui's Enabled property, which is the contract
-- InventoryController already reacts to.
--
-- Layout follows the HUD design's top cluster: a row of round dark discs centered under
-- the Roblox topbar, with the coin pill of §08 pinned to the right. The widgets are built
-- here rather than authored in the place file so the tokens in ThemeUtil stay the only
-- source of colour and size.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Util = ReplicatedStorage:WaitForChild("Util")
local ButtonUtil = require(Util:WaitForChild("ButtonUtil"))
local ThemeUtil = require(Util:WaitForChild("ThemeUtil"))
local PanelUtil = require(Util:WaitForChild("PanelUtil"))
local CurrencyUtil = require(Util:WaitForChild("CurrencyUtil"))

-- Art already in the place file; the design only specifies the frame around it.
local INVENTORY_ICON = "rbxassetid://135273755533681"
local RUNIES_ICON = "rbxassetid://112895221053745"

-- The design's cluster discs, and the gap between them.
local BUTTON_SIZE = 36
local BUTTON_GAP = 8

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screenGui = script.Parent

local camera = workspace.CurrentCamera
local root = ThemeUtil.root(camera and camera.ViewportSize or Vector2.new(1280, 720))

-- The authored MainFrame predates the design system. Replacing it wholesale keeps one
-- definition of the HUD rather than a styled copy fighting an unstyled one.
local authored = screenGui:FindFirstChild("MainFrame")
if authored then
	authored:Destroy()
end

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Size = UDim2.new(1, 0, 0, BUTTON_SIZE)
mainFrame.Position = UDim2.new(0, 0, 0, 10)
mainFrame.Parent = screenGui

--------------------------------------------------------------------------------
-- Top-center cluster
--------------------------------------------------------------------------------

local cluster = Instance.new("Frame")
cluster.Name = "Cluster"
cluster.AnchorPoint = Vector2.new(0.5, 0)
cluster.Position = UDim2.fromScale(0.5, 0)
cluster.Size = UDim2.fromOffset(0, BUTTON_SIZE)
cluster.AutomaticSize = Enum.AutomaticSize.X
cluster.BackgroundTransparency = 1
cluster.BorderSizePixel = 0
cluster.Parent = mainFrame

local clusterLayout = Instance.new("UIListLayout")
clusterLayout.FillDirection = Enum.FillDirection.Horizontal
clusterLayout.Padding = UDim.new(0, BUTTON_GAP)
clusterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
clusterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
clusterLayout.SortOrder = Enum.SortOrder.LayoutOrder
clusterLayout.Parent = cluster

--- One disc in the cluster: `rgba(20,20,22,0.6)`, fully round, tinted glyph inside.
local function clusterButton(name: string, icon: string, tint: Color3, order: number): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = name
	button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	button.BackgroundTransparency = 0.4
	button.Image = icon
	button.ImageColor3 = tint
	button.ScaleType = Enum.ScaleType.Fit
	button.LayoutOrder = order
	button.Parent = cluster
	ThemeUtil.pill(button)
	ThemeUtil.padding(button, 7, 7, 7, 7)

	-- §07's press feedback: the disc darkens on hover.
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0.25
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 0.4
	end)

	return button
end

-- Only the inventory disc is wired. The design's Settings and Shop discs have no feature
-- behind them in this game yet, and a button that does nothing is worse than no button.
local openButton = clusterButton("OpenButton", INVENTORY_ICON, ThemeUtil.Accent.gold, 1)

--------------------------------------------------------------------------------
-- Coin pill (§08)
--------------------------------------------------------------------------------

local runiesFrame = Instance.new("Frame")
runiesFrame.Name = "RuniesFrame"
runiesFrame.AnchorPoint = Vector2.new(1, 0)
runiesFrame.Position = UDim2.new(1, -12, 0, 0)
runiesFrame.Size = UDim2.fromOffset(0, BUTTON_SIZE)
runiesFrame.AutomaticSize = Enum.AutomaticSize.X
runiesFrame.BackgroundTransparency = 1
runiesFrame.BorderSizePixel = 0
runiesFrame.Parent = mainFrame

local pill, runiesTotalLabel = PanelUtil.coinPill(runiesFrame, RUNIES_ICON, root)
pill.Name = "Pill"
pill.AnchorPoint = Vector2.new(1, 0.5)
pill.Position = UDim2.fromScale(1, 0.5)
runiesTotalLabel.Name = "RuniesTotalLabel"

CurrencyUtil.OnRuniesChanged(function(amount)
	runiesTotalLabel.Text = CurrencyUtil.format(amount)
end)

ButtonUtil.hookClick(openButton, function()
	local inventoryGui = playerGui:FindFirstChild("InventoryGui")
	if inventoryGui and inventoryGui:IsA("ScreenGui") then
		inventoryGui.Enabled = not inventoryGui.Enabled
	end
end)
