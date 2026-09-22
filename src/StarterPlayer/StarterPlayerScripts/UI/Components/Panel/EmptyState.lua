--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/EmptyState

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)

local EmptyState = {}

local metric = Theme.metric
local em = Theme.em

export type Config = {
	parent: Instance,
	root: number,
}

export type View = {
	Root: CanvasGroup,
	IconDisc: Frame,
	Icon: ImageLabel,
	TitleLabel: TextLabel,
	BodyLabel: TextLabel,
}

function EmptyState.Create(config: Config): View
	local root = Instance.new("CanvasGroup")
	root.Name = "EmptyState"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = 10
	root.Parent = config.parent

	local content = Primitives.NewFrame("Content", root)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.new(1, -32, 0, metric.emptyStateHeight)
	content.ZIndex = 11
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(metric.emptyStateMaxWidth, metric.emptyStateHeight)
	sizeConstraint.Parent = content
	local layout = Primitives.NewList(content, Enum.FillDirection.Vertical, metric.emptyStateGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	local iconDisc = Primitives.NewFrame("IconDisc", content)
	iconDisc.Size = UDim2.fromOffset(metric.emptyStateIconDiscSize, metric.emptyStateIconDiscSize)
	iconDisc.BackgroundTransparency = 0.88
	iconDisc.LayoutOrder = 1
	iconDisc.ZIndex = 11
	Theme.Pill(iconDisc)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(metric.emptyStateIconSize, metric.emptyStateIconSize)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 12
	icon.Parent = iconDisc

	local title = Primitives.NewLabel("Title", content)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.FontFace = Theme.font.extraBold
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.LayoutOrder = 2
	title.ZIndex = 11
	Primitives.SetText(title, em.itemName, config.root)

	local body = Primitives.NewLabel("Body", content)
	body.Size = UDim2.new(1, 0, 0, 44)
	body.FontFace = Theme.font.bold
	body.TextColor3 = Theme.textColors.muted
	body.TextTransparency = Theme.textColors.mutedTransparency
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.LayoutOrder = 3
	body.ZIndex = 11
	Primitives.SetText(body, em.body, config.root)

	return {
		Root = root,
		IconDisc = iconDisc,
		Icon = icon,
		TitleLabel = title,
		BodyLabel = body,
	}
end

return EmptyState
