-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/EmptyState

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)

local EmptyState = {}

local Metric = Theme.Metric
local Em = Theme.Em

export type Config = {
	parent: Instance,
	root: number,
}

export type View = {
	Root: Frame,
	IconDisc: Frame,
	Icon: ImageLabel,
	TitleLabel: TextLabel,
	BodyLabel: TextLabel,
}

function EmptyState.Create(config: Config): View
	local root = Primitives.NewFrame("EmptyState", config.parent)
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.ZIndex = 10

	local content = Primitives.NewFrame("Content", root)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.new(1, -32, 0, Metric.emptyStateHeight)
	content.ZIndex = 11
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(Metric.emptyStateMaxWidth, Metric.emptyStateHeight)
	sizeConstraint.Parent = content
	local layout = Primitives.NewList(content, Enum.FillDirection.Vertical, Metric.emptyStateGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local iconDisc = Primitives.NewFrame("IconDisc", content)
	iconDisc.Size = UDim2.fromOffset(Metric.emptyStateIconDiscSize, Metric.emptyStateIconDiscSize)
	iconDisc.BackgroundTransparency = 0.88
	iconDisc.LayoutOrder = 1
	iconDisc.ZIndex = 11
	Theme.pill(iconDisc)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(Metric.emptyStateIconSize, Metric.emptyStateIconSize)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 12
	icon.Parent = iconDisc

	local title = Primitives.NewLabel("Title", content)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.FontFace = Theme.Font.extraBold
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 2
	title.ZIndex = 11
	Primitives.SetText(title, Em.itemName, config.root)

	local body = Primitives.NewLabel("Body", content)
	body.Size = UDim2.new(1, 0, 0, 44)
	body.FontFace = Theme.Font.bold
	body.TextColor3 = Theme.Text.muted
	body.TextTransparency = Theme.Text.mutedTransparency
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LayoutOrder = 3
	body.ZIndex = 11
	Primitives.SetText(body, Em.body, config.root)

	return {
		Root = root,
		IconDisc = iconDisc,
		Icon = icon,
		TitleLabel = title,
		BodyLabel = body,
	}
end

return EmptyState
