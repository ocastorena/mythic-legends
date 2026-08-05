-- StarterPlayer/StarterPlayerScripts/UI/Screens/Hotbar

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local ThemeUtil = require(script.Parent.Parent:WaitForChild("ThemeUtil"))

local SLOT_COUNT = 6
local BOTTOM_MARGIN = ThemeUtil.Platform.topbarEdgePadding

export type Props = {
	hotbarController: Types.HotbarControllerApi,
}

local function createSlot(tray: Frame, index: number): Types.HotbarSlotView
	local size = ThemeUtil.Metric.hotbarSlot
	local button = Instance.new("ImageButton")
	button.Name = `Slot{index}`
	button.Size = UDim2.fromOffset(size, size)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = ThemeUtil.Platform.topbarButtonFill
	button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonEmptyTransparency
	button.Image = ""
	button.LayoutOrder = index
	button.Parent = tray
	ThemeUtil.corner(button, ThemeUtil.Radius.hotbarSlot)

	local ring = ThemeUtil.ring(button, ThemeUtil.Accent.gold, 2)
	ring.Transparency = 1

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.82, 0.5)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = ThemeUtil.Font.extraBold
	label.TextColor3 = ThemeUtil.Text.strong
	label.TextScaled = true
	label.TextWrapped = false
	label.Visible = false
	label.Parent = button

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.AnchorPoint = Vector2.new(0.5, 1)
	keyLabel.Position = UDim2.new(0.5, 0, 1, -3)
	keyLabel.Size = UDim2.fromOffset(size, 10)
	keyLabel.BackgroundTransparency = 1
	keyLabel.BorderSizePixel = 0
	keyLabel.FontFace = ThemeUtil.Font.bold
	keyLabel.Text = tostring(index)
	keyLabel.TextColor3 = ThemeUtil.Text.dim
	keyLabel.TextTransparency = ThemeUtil.Text.dimTransparency
	keyLabel.TextSize = 10
	keyLabel.Visible = not UserInputService.TouchEnabled
	keyLabel.Parent = button

	return {
		button = button,
		icon = icon,
		label = label,
		keyLabel = keyLabel,
		ring = ring,
	}
end

local function Hotbar(scope: any, props: Props): ScreenGui
	local screenGui = scope:New "ScreenGui" {
		Name = "HotbarGui",
		Enabled = true,
		DisplayOrder = ThemeUtil.Layer.hotbar,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	} :: ScreenGui

	local tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.AnchorPoint = Vector2.new(0.5, 1)
	tray.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
	tray.Size = UDim2.fromOffset(0, 0)
	tray.AutomaticSize = Enum.AutomaticSize.XY
	tray.BackgroundTransparency = 1
	tray.BorderSizePixel = 0
	tray.Visible = false
	tray.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, ThemeUtil.Metric.hotbarGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tray

	local slots: { Types.HotbarSlotView } = {}
	for index = 1, SLOT_COUNT do
		table.insert(slots, createSlot(tray, index))
	end

	local unbind = props.hotbarController.BindView({
		screenGui = screenGui,
		tray = tray,
		slots = slots,
	})
	table.insert(scope, unbind)
	return screenGui
end

return Hotbar
