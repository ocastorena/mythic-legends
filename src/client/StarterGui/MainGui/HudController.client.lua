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

-- Awaiting an image asset. Creator Store icons are all published as *Decal* assets, which
-- ImageLabel.Image will not render -- ten free shopping-bag decals were tried and every one
-- came back blank while this place's own uploaded icons load fine. A GUI needs an Image
-- asset, which in practice means uploading the art to this account.
--
-- Whatever goes here must be a flat white glyph, since ImageColor3 multiplies and a black
-- or multi-tone icon would ignore SHOP_TINT.
local SHOP_ICON = ""

-- Fill colour for the shop glyph, from the HUD design's shop button. Change this one line
-- to recolour the icon; nothing else reads it.
local SHOP_TINT = Color3.fromHex("00ff69")

-- Gap between cluster discs. Their diameter is not a constant: it is measured off
-- Roblox's own top bar so the HUD reads as part of the same strip on every device.
local BUTTON_GAP = 8

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screenGui = script.Parent

-- Above the modal scrim, so the inventory, shop and coin pill stay fully lit and clickable
-- whenever a menu is open. The HUD lives in the top bar strip, which no panel reaches.
screenGui.DisplayOrder = ThemeUtil.Layer.hud

local camera = workspace.CurrentCamera

local function viewportSize(): Vector2
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local topbar = ThemeUtil.topbar(viewportSize())
local buttonSize = topbar.buttonSize
local root = ThemeUtil.root(viewportSize())

-- The authored MainFrame predates the design system. Replacing it wholesale keeps one
-- definition of the HUD rather than a styled copy fighting an unstyled one.
local authored = screenGui:FindFirstChild("MainFrame")
if authored then
	authored:Destroy()
end

-- Occupies exactly Roblox's top bar row. MainGui ignores the GUI inset, so its coordinate
-- space is screen space and the row can be placed where the platform's own bar sits;
-- anything centred in here lands level with Roblox's buttons.
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Size = UDim2.new(1, 0, 0, topbar.rowHeight)
mainFrame.Position = UDim2.new(0, 0, 0, topbar.rowTop)
mainFrame.Parent = screenGui

--------------------------------------------------------------------------------
-- Top-center cluster
--------------------------------------------------------------------------------

local cluster = Instance.new("Frame")
cluster.Name = "Cluster"
cluster.AnchorPoint = Vector2.new(0.5, 0.5)
cluster.Position = UDim2.fromScale(0.5, 0.5)
cluster.Size = UDim2.fromOffset(0, buttonSize)
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

--- One disc in the cluster: platform fill, fully round, glyph inside.
---
--- `tint` recolours a single-colour glyph. Pass nil for artwork that already carries its
--- own colours, like the design's two-tone shop bag, which a tint would flatten.
local function clusterButton(name: string, icon: string, tint: Color3?, order: number): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = name
	button.Size = UDim2.fromOffset(buttonSize, buttonSize)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	-- Platform fill rather than the design's own `rgba(20,20,22,0.6)`: this disc sits in
	-- the same strip as Roblox's buttons, so it has to read as one of them.
	button.BackgroundColor3 = ThemeUtil.Platform.topbarButtonFill
	button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonTransparency
	button.Image = icon
	button.ImageColor3 = tint or Color3.fromRGB(255, 255, 255)
	button.ScaleType = Enum.ScaleType.Fit
	button.LayoutOrder = order
	button.Parent = cluster
	ThemeUtil.pill(button)
	-- Glyph inset keeps its proportion if the button size ever changes.
	local inset = math.round(buttonSize * 0.2)
	ThemeUtil.padding(button, inset, inset, inset, inset)

	-- §07's press feedback, standing in for Roblox's own state overlay.
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonHoverTransparency
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonTransparency
	end)

	return button
end

-- Cluster order follows the design: Settings · Inventory · Shop. Settings is left out
-- because nothing in this game answers it yet.
local openButton = clusterButton("OpenButton", INVENTORY_ICON, ThemeUtil.Accent.gold, 1)
local shopButton = clusterButton("ShopButton", SHOP_ICON, SHOP_TINT, 2)

--------------------------------------------------------------------------------
-- Coin pill (§08)
--------------------------------------------------------------------------------

-- Pinned to the right edge of the span Roblox leaves free, not the raw screen edge, so it
-- can never slide under the platform's own right-hand chrome.
local runiesFrame = Instance.new("Frame")
runiesFrame.Name = "RuniesFrame"
runiesFrame.AnchorPoint = Vector2.new(1, 0.5)
runiesFrame.Position = UDim2.new(0, topbar.maxX - 12, 0.5, 0)
runiesFrame.Size = UDim2.fromOffset(0, buttonSize)
runiesFrame.AutomaticSize = Enum.AutomaticSize.X
runiesFrame.BackgroundTransparency = 1
runiesFrame.BorderSizePixel = 0
runiesFrame.Parent = mainFrame

-- Matched to the cluster discs, which are themselves matched to Roblox's chrome. The
-- design's §08 pill is a white 8% chip, which is right inside a panel but wrong here: on
-- the top bar it has to be the same fill as the platform's own pill beside it.
local pill, runiesTotalLabel = PanelUtil.coinPill(runiesFrame, RUNIES_ICON, root, buttonSize)
pill.Name = "Pill"
pill.AnchorPoint = Vector2.new(1, 0.5)
pill.Position = UDim2.fromScale(1, 0.5)
pill.BackgroundColor3 = ThemeUtil.Platform.topbarButtonFill
pill.BackgroundTransparency = ThemeUtil.Platform.topbarButtonTransparency
runiesTotalLabel.Name = "RuniesTotalLabel"

--------------------------------------------------------------------------------
-- Responsive layout
--------------------------------------------------------------------------------

--- Re-measures the top bar and resizes the HUD to match.
---
--- Roblox scales its own chrome by device, and the free span it leaves changes as that
--- chrome grows and shrinks, so this runs on every viewport change rather than only at
--- startup: rotating a phone, resizing a window, or the platform showing an extra top bar
--- control all land here.
local function relayout()
	topbar = ThemeUtil.topbar(viewportSize())
	buttonSize = topbar.buttonSize
	root = ThemeUtil.root(viewportSize())

	mainFrame.Size = UDim2.new(1, 0, 0, topbar.rowHeight)
	mainFrame.Position = UDim2.new(0, 0, 0, topbar.rowTop)
	cluster.Size = UDim2.fromOffset(0, buttonSize)

	local inset = math.round(buttonSize * 0.2)
	local count = 0
	for _, button in ipairs(cluster:GetChildren()) do
		if button:IsA("ImageButton") then
			count += 1
			button.Size = UDim2.fromOffset(buttonSize, buttonSize)
			local padding = button:FindFirstChildOfClass("UIPadding")
			if padding then
				padding.PaddingTop = UDim.new(0, inset)
				padding.PaddingBottom = UDim.new(0, inset)
				padding.PaddingLeft = UDim.new(0, inset)
				padding.PaddingRight = UDim.new(0, inset)
			end
		end
	end

	-- Screen-centred as the design shows, but never allowed to slide under Roblox's own
	-- chrome. On a phone that chrome is wide enough to reach the middle of a short screen.
	--
	-- Width is derived rather than read off AbsoluteSize, which is still zero on the frame
	-- the HUD is built and would put the clamp in the wrong place exactly once.
	local half = (count * buttonSize + math.max(count - 1, 0) * BUTTON_GAP) / 2
	local centre = viewportSize().X / 2
	local earliest = topbar.minX + BUTTON_GAP + half
	cluster.Position = UDim2.new(0, math.max(centre, earliest), 0.5, 0)

	runiesFrame.Position = UDim2.new(0, topbar.maxX - 12, 0.5, 0)
	runiesFrame.Size = UDim2.fromOffset(0, buttonSize)

	local scale = buttonSize / 26
	pill.Size = UDim2.fromOffset(0, buttonSize)
	runiesTotalLabel.Size = UDim2.fromOffset(0, buttonSize)
	runiesTotalLabel.TextSize = ThemeUtil.text(ThemeUtil.Em.sectionLabel, root) * scale
	local coinIcon = pill:FindFirstChild("Icon")
	if coinIcon then
		local iconSize = math.round(15 * scale)
		coinIcon.Size = UDim2.fromOffset(iconSize, iconSize)
	end
	local coinPadding = pill:FindFirstChildOfClass("UIPadding")
	if coinPadding then
		coinPadding.PaddingRight = UDim.new(0, math.round(11 * scale))
		coinPadding.PaddingLeft = UDim.new(0, math.round(8 * scale))
	end
end

relayout()

if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end
-- The free span changes independently of the viewport when Roblox adds or removes a top
-- bar control, so the inset itself is watched too.
pcall(function()
	game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(relayout)
end)

CurrencyUtil.OnRuniesChanged(function(amount)
	runiesTotalLabel.Text = CurrencyUtil.format(amount)
end)

--- Panels are opened by toggling their ScreenGui's Enabled flag; that is the contract
--- every panel controller already listens on, so the HUD never reaches inside another GUI.
local function togglePanel(guiName: string)
	local gui = playerGui:FindFirstChild(guiName)
	if gui and gui:IsA("ScreenGui") then
		gui.Enabled = not gui.Enabled
	end
end

ButtonUtil.hookClick(openButton, function()
	togglePanel("InventoryGui")
end)

-- There is no ShopGui in the game yet, so this is inert until one exists. It is wired to
-- the same contract as the inventory rather than left unhooked, so adding a ShopGui is the
-- only step needed to bring it to life -- no change here.
ButtonUtil.hookClick(shopButton, function()
	togglePanel("ShopGui")
end)
