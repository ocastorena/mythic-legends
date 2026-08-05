-- StarterPlayer/StarterPlayerScripts/UI/Screens/HUD

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local HudButton = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("HudButton"))
local LocalDataValue = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("LocalDataValue"))
local ThemeUtil = require(script.Parent.Parent:WaitForChild("ThemeUtil"))

local INVENTORY_ICON = "rbxassetid://135273755533681"
local RUNIES_ICON = "rbxassetid://112895221053745"
local SHOP_ICON = "rbxassetid://9405933217"
local SHOP_TINT = Color3.fromHex("00ff69")
local BUTTON_GAP = 8

export type Props = {
	localData: Types.LocalDataApi,
}

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

local function HUD(scope: any, props: Props): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local camera = workspace.CurrentCamera
	local initialViewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local initialTopbar = ThemeUtil.topbar(initialViewport)
	local rowTop = scope:Value(initialTopbar.rowTop)
	local rowHeight = scope:Value(initialTopbar.rowHeight)
	local buttonSize = scope:Value(initialTopbar.buttonSize)
	local screenWidth = scope:Value(initialViewport.X)
	local viewportSize = scope:Value(initialViewport)
	local textRoot = scope:Value(ThemeUtil.root(initialViewport))
	local currency = LocalDataValue.observe(scope, props.localData, "currency", {})

	local function togglePanel(guiName: string)
		local gui = playerGui:FindFirstChild(guiName)
		if not (gui and gui:IsA("ScreenGui")) then
			return
		end
		local shouldOpen = not gui.Enabled
		gui.Enabled = shouldOpen
		if shouldOpen then
			for _, otherName in { "InventoryGui", "ShopGui" } do
				if otherName ~= guiName then
					local otherGui = playerGui:FindFirstChild(otherName)
					if otherGui and otherGui:IsA("ScreenGui") then
						otherGui.Enabled = false
					end
				end
			end
		end
	end

	local cluster = scope:New "Frame" {
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
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, BUTTON_GAP),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			HudButton(scope, {
				name = "OpenButton",
				icon = INVENTORY_ICON,
				iconColor = ThemeUtil.Accent.gold,
				iconScale = 1,
				layoutOrder = 1,
				buttonSize = buttonSize,
				onActivated = function()
					togglePanel("InventoryGui")
				end,
			}),
			HudButton(scope, {
				name = "ShopButton",
				icon = SHOP_ICON,
				iconColor = SHOP_TINT,
				iconScale = 0.78,
				layoutOrder = 2,
				buttonSize = buttonSize,
				onActivated = function()
					togglePanel("ShopGui")
				end,
			}),
		},
	} :: Frame

	local runiesText = scope:Computed(function(use)
		local payload = use(currency)
		local amount = if type(payload) == "table" then tonumber(payload.runies) or 0 else 0
		return formatRunies(amount)
	end)
	local scale = scope:Computed(function(use)
		return use(buttonSize) / 26
	end)

	local runiesFrame = scope:New "Frame" {
		Name = "RuniesFrame",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = scope:Computed(function(use)
			local width = use(screenWidth)
			local viewport = use(viewportSize)
			local safeInset = math.max(0, (width - viewport.X) / 2)
			local edgePadding = math.round(safeInset) + ThemeUtil.Platform.topbarEdgePadding
			return UDim2.new(0, width - edgePadding, 0.5, 0)
		end),
		Size = scope:Computed(function(use)
			return UDim2.fromOffset(0, use(buttonSize))
		end),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		[scope.Children] = {
			scope:New "Frame" {
				Name = "Pill",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = scope:Computed(function(use)
					return UDim2.fromOffset(0, use(buttonSize))
				end),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = ThemeUtil.Platform.topbarButtonFill,
				BackgroundTransparency = ThemeUtil.Platform.topbarButtonTransparency,
				BorderSizePixel = 0,
				[scope.Children] = {
					scope:New "UICorner" {
						CornerRadius = UDim.new(1, 0),
					},
					scope:New "UIPadding" {
						PaddingLeft = scope:Computed(function(use)
							return UDim.new(0, math.round(8 * use(scale)))
						end),
						PaddingRight = scope:Computed(function(use)
							return UDim.new(0, math.round(11 * use(scale)))
						end),
					},
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = scope:Computed(function(use)
							return UDim.new(0, math.round(5 * use(scale)))
						end),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:New "ImageLabel" {
						Name = "Icon",
						Size = scope:Computed(function(use)
							local iconSize = math.round(15 * use(scale))
							return UDim2.fromOffset(iconSize, iconSize)
						end),
						BackgroundTransparency = 1,
						Image = RUNIES_ICON,
						ScaleType = Enum.ScaleType.Fit,
						LayoutOrder = 1,
					},
					scope:New "TextLabel" {
						Name = "RuniesTotalLabel",
						AutomaticSize = Enum.AutomaticSize.X,
						Size = scope:Computed(function(use)
							return UDim2.fromOffset(0, use(buttonSize))
						end),
						BackgroundTransparency = 1,
						FontFace = ThemeUtil.Font.extraBold,
						Text = runiesText,
						TextColor3 = ThemeUtil.Text.coin,
						TextSize = scope:Computed(function(use)
							return ThemeUtil.text(ThemeUtil.Em.sectionLabel, use(textRoot)) * use(scale)
						end),
						LayoutOrder = 2,
					},
				},
			},
		},
	} :: Frame

	local mainFrame: Frame
	mainFrame = scope:New "Frame" {
		Name = "MainFrame",
		Size = scope:Computed(function(use)
			return UDim2.new(1, 0, 0, use(rowHeight))
		end),
		Position = scope:Computed(function(use)
			return UDim2.new(0, 0, 0, use(rowTop))
		end),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		[scope.Children] = { cluster, runiesFrame },
	} :: Frame

	local function refreshLayout()
		local viewport = camera and camera.ViewportSize or initialViewport
		local topbar = ThemeUtil.topbar(viewport)
		rowTop:set(topbar.rowTop)
		rowHeight:set(topbar.rowHeight)
		buttonSize:set(topbar.buttonSize)
		viewportSize:set(viewport)
		textRoot:set(ThemeUtil.root(viewport))
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

	local screenGui = scope:New "ScreenGui" {
		Name = "HUDGui",
		DisplayOrder = ThemeUtil.Layer.hud,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.None,
		Parent = playerGui,
		[scope.Children] = { mainFrame },
	} :: ScreenGui

	refreshLayout()
	task.defer(function()
		if screenGui.Parent then
			refreshLayout()
		end
	end)
	return screenGui
end

return HUD
