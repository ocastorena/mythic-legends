-- StarterPlayer/StarterPlayerScripts/UI/Screens/HUD

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local HudButton = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("HudButton"))
local LocalDataValue = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("LocalDataValue"))
local MenuState = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("MenuState"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local INVENTORY_ICON = "rbxassetid://6870729295"
local GOLD_ICON = "rbxassetid://112895221053745"
local SHOP_ICON = "rbxassetid://13429538917"
local SHOP_TINT = Color3.fromHex("00ff69")
local BUTTON_GAP = 8
local HOTBAR_WIDTH = 6 * Theme.Metric.hotbarSlot + 5 * Theme.Metric.hotbarGap

export type Props = {
	localData: Types.LocalDataApi,
	combatController: Types.CombatControllerApi,
}

local function formatGold(amount: number): string
	local formatted = tostring(math.floor(amount))
	while true do
		local replacements
		formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replacements == 0 then
			return formatted
		end
	end
end

local function HUD(scope: any, props: Props): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera
	local initialViewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local initialTopbar = Theme.topbar(initialViewport)
	local rowTop = scope:Value(initialTopbar.rowTop)
	local rowHeight = scope:Value(initialTopbar.rowHeight)
	local buttonSize = scope:Value(initialTopbar.buttonSize)
	local screenWidth = scope:Value(initialViewport.X)
	local viewportSize = scope:Value(initialViewport)
	local textRoot = scope:Value(Theme.root(initialViewport))
	local inventoryOpen = scope:Value(false)
	local shopOpen = scope:Value(false)
	local unsubscribeMenuState = MenuState.Subscribe(function(activeName)
		inventoryOpen:set(activeName == "Inventory")
		shopOpen:set(activeName == "Shop")
	end)
	table.insert(scope, unsubscribeMenuState)
	local currency = LocalDataValue.observe(scope, props.localData, "currency", {})
	local staminaFill = scope:New("Frame")({
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 255, 90),
		BorderSizePixel = 0,
		[scope.Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		},
	}) :: Frame
	local staminaMeter = scope:New("Frame")({
		Name = "StaminaMeter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -68),
		Size = UDim2.fromOffset(HOTBAR_WIDTH, 8),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		[scope.Children] = {
			staminaFill,
			scope:New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		},
	}) :: Frame
	local unbindStamina = props.combatController.BindStaminaView({
		container = staminaMeter,
		fill = staminaFill,
	})
	table.insert(scope, unbindStamina)

	local cluster = scope:New("Frame")({
		Name = "Cluster",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = scope:Computed(function(use)
			return UDim2.new(0, use(screenWidth) / 2, 0.5, 0)
		end),
		Size = scope:Computed(function(use)
			return UDim2.fromOffset(0, use(buttonSize))
		end),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		[scope.Children] = {
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, BUTTON_GAP),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			HudButton(scope, {
				name = "OpenButton",
				icon = INVENTORY_ICON,
				iconColor = Theme.Accent.gold,
				isOpen = inventoryOpen,
				layoutOrder = 1,
				buttonSize = buttonSize,
				onActivated = function()
					MenuState.Toggle("Inventory")
				end,
			}),
			HudButton(scope, {
				name = "ShopButton",
				icon = SHOP_ICON,
				iconColor = SHOP_TINT,
				isOpen = shopOpen,
				layoutOrder = 2,
				buttonSize = buttonSize,
				onActivated = function()
					MenuState.Toggle("Shop")
				end,
			}),
		},
	}) :: Frame

	local goldText = scope:Computed(function(use)
		local payload = use(currency)
		local amount = if type(payload) == "table" then tonumber(payload.gold) or 0 else 0
		return formatGold(amount)
	end)
	local scale = scope:Computed(function(use)
		return use(buttonSize) / 26
	end)

	local goldFrame = scope:New("Frame")({
		Name = "GoldFrame",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = scope:Computed(function(use)
			local width = use(screenWidth)
			local viewport = use(viewportSize)
			local safeInset = math.max(0, (width - viewport.X) / 2)
			local edgePadding = math.round(safeInset) + Theme.Platform.topbarEdgePadding
			return UDim2.new(0, width - edgePadding, 0.5, 0)
		end),
		Size = scope:Computed(function(use)
			return UDim2.fromOffset(0, use(buttonSize))
		end),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		[scope.Children] = {
			scope:New("Frame")({
				Name = "Pill",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = scope:Computed(function(use)
					return UDim2.fromOffset(0, use(buttonSize))
				end),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Platform.topbarButtonFill,
				BackgroundTransparency = Theme.Platform.topbarButtonTransparency,
				BorderSizePixel = 0,
				[scope.Children] = {
					scope:New("UICorner")({
						CornerRadius = UDim.new(1, 0),
					}),
					scope:New("UIPadding")({
						PaddingLeft = scope:Computed(function(use)
							return UDim.new(0, math.round(8 * use(scale)))
						end),
						PaddingRight = scope:Computed(function(use)
							return UDim.new(0, math.round(11 * use(scale)))
						end),
					}),
					scope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = scope:Computed(function(use)
							return UDim.new(0, math.round(5 * use(scale)))
						end),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					scope:New("ImageLabel")({
						Name = "Icon",
						Size = scope:Computed(function(use)
							local iconSize = math.round(15 * use(scale))
							return UDim2.fromOffset(iconSize, iconSize)
						end),
						BackgroundTransparency = 1,
						Image = GOLD_ICON,
						ScaleType = Enum.ScaleType.Fit,
						LayoutOrder = 1,
					}),
					scope:New("TextLabel")({
						Name = "GoldTotalLabel",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = scope:Computed(function(use)
							return UDim2.fromOffset(0, use(buttonSize))
						end),
						BackgroundTransparency = 1,
						FontFace = Theme.Font.extraBold,
						Text = goldText,
						TextColor3 = Theme.Text.coin,
						TextSize = scope:Computed(function(use)
							return Theme.text(Theme.Em.sectionLabel, use(textRoot)) * use(scale)
						end),
						LayoutOrder = 2,
					}),
				},
			}),
		},
	}) :: Frame

	local mainFrame: Frame
	mainFrame = scope:New("Frame")({
		Name = "MainFrame",
		Size = scope:Computed(function(use)
			return UDim2.new(1, 0, 0, use(rowHeight))
		end),
		Position = scope:Computed(function(use)
			return UDim2.fromOffset(0, use(rowTop))
		end),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		[scope.Children] = { cluster, goldFrame },
	}) :: Frame

	local function refreshLayout()
		local viewport = camera and camera.ViewportSize or initialViewport
		local topbar = Theme.topbar(viewport)
		rowTop:set(topbar.rowTop)
		rowHeight:set(topbar.rowHeight)
		buttonSize:set(topbar.buttonSize)
		viewportSize:set(viewport)
		textRoot:set(Theme.root(viewport))
		local resolvedWidth = mainFrame.AbsoluteSize.X
		screenWidth:set(if resolvedWidth > 0 then resolvedWidth else viewport.X)
	end

	table.insert(scope, mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshLayout))
	if camera then
		table.insert(scope, camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshLayout))
	end
	local insetOk, insetConnection = pcall(function()
		return GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refreshLayout)
	end)
	if insetOk then
		table.insert(scope, insetConnection)
	end

	local screenGui = scope:New("ScreenGui")({
		Name = "HUDGui",
		DisplayOrder = Theme.Layer.hud,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.None,
		Parent = playerGui,
		[scope.Children] = { mainFrame, staminaMeter },
	}) :: ScreenGui

	refreshLayout()
	task.defer(function()
		if screenGui.Parent then
			refreshLayout()
		end
	end)
	return screenGui
end

return HUD
