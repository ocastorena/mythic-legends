-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/ActionMenu

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)

local ActionMenu = {}

local Metric = Theme.Metric
local Radius = Theme.Radius
local Surface = Theme.Surface
local Em = Theme.Em

export type Item = {
	id: string,
	label: string,
	icon: string?,
	iconColor: Color3?,
	enabled: boolean?,
}

export type Config = {
	parent: Instance,
	root: number,
	items: { Item },
}

export type Menu = {
	Root: Frame,
	Options: { [string]: TextButton },
	Open: (GuiButton) -> (),
	Close: () -> (),
	Toggle: (GuiButton) -> (),
}

local function containsPoint(gui: GuiObject, point: Vector2): boolean
	local position = gui.AbsolutePosition
	local size = gui.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

function ActionMenu.Create(config: Config): Menu
	local itemCount = #config.items
	local menuHeight = 2 * Metric.actionMenuPadding
		+ itemCount * Metric.actionMenuItemHeight
		+ math.max(0, itemCount - 1) * Metric.actionMenuGap

	local popup = Primitives.NewFrame("ActionMenu", config.parent)
	popup.AnchorPoint = Vector2.new(1, 1)
	popup.Position = UDim2.new(1, 0, 1, -(Metric.buttonHeight + Metric.actionMenuOffset))
	popup.Size = UDim2.fromOffset(Metric.actionMenuWidth, menuHeight)
	popup.BackgroundColor3 = Surface.modal.color
	popup.BackgroundTransparency = Surface.modal.transparency
	popup.ClipsDescendants = true
	popup.Visible = false
	popup.ZIndex = 20
	Theme.corner(popup, Radius.button)
	Theme.padding(
		popup,
		Metric.actionMenuPadding,
		Metric.actionMenuPadding,
		Metric.actionMenuPadding,
		Metric.actionMenuPadding
	)
	local stroke = Theme.ring(popup, Theme.Text.strong, 1)
	stroke.Transparency = 0.82

	local layout = Primitives.NewList(popup, Enum.FillDirection.Vertical, Metric.actionMenuGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	local options: { [string]: TextButton } = {}
	for index, item in ipairs(config.items) do
		local enabled = item.enabled ~= false
		local button = Instance.new("TextButton")
		button.Name = item.id
		button.Size = UDim2.new(1, 0, 0, Metric.actionMenuItemHeight)
		button.AutoButtonColor = false
		button.Active = enabled
		button.Selectable = enabled
		button.BorderSizePixel = 0
		button.BackgroundColor3 = Surface.chipStrong.color
		button.BackgroundTransparency = 1
		button.Text = ""
		button.LayoutOrder = index
		button.ZIndex = 21
		button.Parent = popup
		Theme.corner(button, Radius.buttonSmall)

		local row = Primitives.NewFrame("Content", button)
		row.Size = UDim2.fromScale(1, 1)
		row.ZIndex = 22
		Theme.padding(row, 0, 12, 0, 12)
		local rowLayout = Primitives.NewList(row, Enum.FillDirection.Horizontal, 10)
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		if item.icon then
			local icon = Instance.new("ImageLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.fromOffset(Metric.actionMenuIconSize, Metric.actionMenuIconSize)
			icon.BackgroundTransparency = 1
			icon.BorderSizePixel = 0
			icon.Image = item.icon
			icon.ImageColor3 = item.iconColor or Theme.Text.strong
			icon.ImageTransparency = if enabled then 0 else Theme.Text.dimTransparency
			icon.ScaleType = Enum.ScaleType.Fit
			icon.LayoutOrder = 1
			icon.ZIndex = 22
			icon.Parent = row
		end

		local label = Primitives.NewLabel("Label", row)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.new(1, -(Metric.actionMenuIconSize + 10), 1, 0)
		label.FontFace = Theme.Font.bold
		label.Text = item.label
		label.TextColor3 = if enabled then Theme.Text.strong else Theme.Text.dim
		label.TextTransparency = if enabled then 0 else Theme.Text.dimTransparency
		label.LayoutOrder = 2
		label.ZIndex = 22
		Primitives.SetText(label, Em.body, config.root)

		if enabled then
			button.MouseEnter:Connect(function()
				button.BackgroundTransparency = Surface.chipStrong.transparency
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundTransparency = 1
			end)
		end

		options[item.id] = button
	end

	local activeAnchor: GuiButton? = nil
	local function close()
		activeAnchor = nil
		popup.Visible = false
	end

	local function open(anchor: GuiButton)
		activeAnchor = anchor
		popup.Visible = true
	end

	local function toggle(anchor: GuiButton)
		if popup.Visible and activeAnchor == anchor then
			close()
		else
			open(anchor)
		end
	end

	local outsideConnection = UserInputService.InputBegan:Connect(function(input)
		if not popup.Visible then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local point = Vector2.new(input.Position.X, input.Position.Y)
		if containsPoint(popup, point) or (activeAnchor and containsPoint(activeAnchor, point)) then
			return
		end
		close()
	end)

	popup.Destroying:Once(function()
		outsideConnection:Disconnect()
	end)

	return {
		Root = popup,
		Options = options,
		Open = open,
		Close = close,
		Toggle = toggle,
	}
end

return ActionMenu
