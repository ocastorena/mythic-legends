-- StarterPlayer/StarterPlayerScripts/Controllers/HUDController

local HUDController = {}
local stopImpl: (() -> ())?
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Context: Types.ClientContext

function HUDController.Init(context: Types.ClientContext)
	Context = context
end

function HUDController.Start()
local connections: { RBXScriptConnection } = {}
-- Owns every widget in HUDGui: the always-on-screen HUD.
--
-- The inventory open button lives in HUDGui but used to be hooked by InventoryController
-- reaching across into another ScreenGui. HUDGui owns its own button now and asks for the
-- inventory by toggling that ScreenGui's Enabled property, which is the contract
-- InventoryController already reacts to.
--
-- Layout follows the HUD design's top cluster: a row of round dark discs centered under
-- the Roblox topbar, with the coin pill of §08 pinned to the right. The widgets are built
-- here rather than authored in the place file so the tokens in ThemeUtil stay the only
-- source of colour and size.

-- Services
local Players = game:GetService("Players")

local Client = script:FindFirstAncestor("Controllers").Parent
local Ui = Client:WaitForChild("UI")
local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
local ThemeUtil = require(Ui:WaitForChild("ThemeUtil"))
local PanelUtil = require(Ui:WaitForChild("PanelUtil"))
local LocalData = Context.LocalData

-- Art already in the place file; the design only specifies the frame around it.
local INVENTORY_ICON = "rbxassetid://135273755533681"
local RUNIES_ICON = "rbxassetid://112895221053745"

-- Creator Store decal 9405933234 ("Shop Icon") resolves to this GUI image texture.
local SHOP_ICON = "rbxassetid://9405933217"
local SHOP_TINT = Color3.fromHex("00ff69")

-- Gap between cluster discs. Their diameter is not a constant: it is measured off
-- Roblox's own top bar so the HUD reads as part of the same strip on every device.
local BUTTON_GAP = 8

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUDGui")

-- The topbar layout uses physical-screen coordinates from GuiService. Keep this explicit
-- in code because a Rojo-created ScreenGui otherwise defaults to respecting the inset and
-- applies the topbar offset a second time.
screenGui.IgnoreGuiInset = true
pcall(function()
	screenGui.ScreenInsets = Enum.ScreenInsets.None
end)

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

-- Occupies exactly Roblox's top bar row. HUDGui ignores the GUI inset, so its coordinate
-- space is screen space and the row can be placed where the platform's own bar sits;
-- anything centred in here lands level with Roblox's buttons.
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.BackgroundTransparency = 1
mainFrame.BorderSizePixel = 0
mainFrame.Size = UDim2.new(1, 0, 0, topbar.rowHeight)
mainFrame.Position = UDim2.new(0, 0, 0, topbar.rowTop)
mainFrame.Parent = screenGui

-- A ScreenGui with ScreenInsets.None uses the entire physical display, while the camera
-- viewport may be narrowed by a phone's side safe areas. The HUD is positioned in the
-- ScreenGui's coordinate space, so use MainFrame's resolved width once it is available.
local function screenWidth(): number
	local width = mainFrame.AbsoluteSize.X
	return width > 0 and width or viewportSize().X
end

local function topbarEdgePadding(width: number): number
	local sideSafeInset = math.max(0, (width - viewportSize().X) / 2)
	return math.round(sideSafeInset) + ThemeUtil.Platform.topbarEdgePadding
end

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
local function clusterButton(
	name: string,
	icon: string,
	tint: Color3?,
	order: number,
	iconInsetScale: number?
): ImageButton
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
	button:SetAttribute("IconInsetScale", iconInsetScale or 0.2)
	button.Parent = cluster
	ThemeUtil.pill(button)
	-- Glyph inset keeps its proportion if the button size ever changes.
	local inset = math.round(buttonSize * (iconInsetScale or 0.2))
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

local function addButtonIcon(button: ImageButton, image: string, tint: Color3, sizeScale: number): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(sizeScale, sizeScale)
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.ImageColor3 = tint
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = button
	return icon
end

-- Cluster order follows the design: Settings · Inventory · Shop. Settings is left out
-- because nothing in this game answers it yet.
local openButton = clusterButton("OpenButton", "", nil, 1, 0.09)
addButtonIcon(openButton, INVENTORY_ICON, ThemeUtil.Accent.gold, 1)

local shopButton = clusterButton("ShopButton", "", nil, 2)

-- Unlike the inventory artwork, the Creator Store shop texture has no transparent margin.
-- Render it as a child so its visible size can match the inventory glyph without shrinking
-- the button's touch target.
addButtonIcon(shopButton, SHOP_ICON, SHOP_TINT, 0.78)

--------------------------------------------------------------------------------
-- Coin pill (§08)
--------------------------------------------------------------------------------

-- Pinned to the physical right edge with the same device-safe gap as Roblox's first
-- control has on the left.
local runiesFrame = Instance.new("Frame")
runiesFrame.Name = "RuniesFrame"
runiesFrame.AnchorPoint = Vector2.new(1, 0.5)
local initialWidth = screenWidth()
runiesFrame.Position = UDim2.new(0, initialWidth - topbarEdgePadding(initialWidth), 0.5, 0)
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

	for _, button in ipairs(cluster:GetChildren()) do
		if button:IsA("ImageButton") then
			button.Size = UDim2.fromOffset(buttonSize, buttonSize)
			local padding = button:FindFirstChildOfClass("UIPadding")
			if padding then
				local insetScale = button:GetAttribute("IconInsetScale") or 0.2
				local inset = math.round(buttonSize * insetScale)
				padding.PaddingTop = UDim.new(0, inset)
				padding.PaddingBottom = UDim.new(0, inset)
				padding.PaddingLeft = UDim.new(0, inset)
				padding.PaddingRight = UDim.new(0, inset)
			end
		end
	end

	-- Centre against the full physical display, not the camera viewport. On phones those
	-- differ because the latter excludes side safe areas, which was pulling the cluster
	-- left of the actual screen centre.
	local width = screenWidth()
	cluster.Position = UDim2.new(0, width / 2, 0.5, 0)

	-- Mirror the Roblox button's edge treatment: device-safe inset plus the platform's
	-- standard 12px topbar padding.
	runiesFrame.Position = UDim2.new(0, width - topbarEdgePadding(width), 0.5, 0)
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

table.insert(connections, mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))

relayout()
-- The ScreenGui's physical size can settle one frame after the controller starts.
-- Re-layout once more so first spawn receives the same centring as later resizes.
task.defer(relayout)

if camera then
	table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout))
end
-- Roblox can change its Core UI inset independently of the viewport, so keep the row
-- vertically aligned when the top bar changes.
local insetOk, insetConnection = pcall(function()
	return game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(relayout)
end)
if insetOk then table.insert(connections, insetConnection) end

local function formatRunies(amount: number): string
	local formatted = tostring(math.floor(amount))
	while true do
		local replacements
		formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replacements == 0 then
			return formatted
		end
	end
end

local function updateCurrency(payload: unknown)
	local amount = if type(payload) == "table" then tonumber(payload.runies) or 0 else 0
	runiesTotalLabel.Text = formatRunies(amount)
end

updateCurrency(LocalData.Peek("currency"))
table.insert(connections, LocalData.OnStateChanged:Connect(function(key, payload)
	if key == "currency" then
		updateCurrency(payload)
	end
end))

--- Panels are opened by toggling their ScreenGui's Enabled flag; that is the contract
--- every panel controller already listens on, so the HUD never reaches inside another GUI.
local function togglePanel(guiName: string)
	local gui = playerGui:FindFirstChild(guiName)
	if gui and gui:IsA("ScreenGui") then
		local shouldOpen = not gui.Enabled
		if shouldOpen then
			-- Acquire the destination panel's modal ownership before releasing the current
			-- panel. Reversing this order briefly dropped the shared backdrop and input
			-- guard between menus, producing a one-frame world flash.
			gui.Enabled = true
			for _, otherName in ipairs({ "InventoryGui", "ShopGui" }) do
				if otherName ~= guiName then
					local otherGui = playerGui:FindFirstChild(otherName)
					if otherGui and otherGui:IsA("ScreenGui") then
						otherGui.Enabled = false
					end
				end
			end
		else
			gui.Enabled = false
		end
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
stopImpl = function()
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
end
end

function HUDController.Stop()
	if stopImpl then stopImpl(); stopImpl = nil end
end

return HUDController
