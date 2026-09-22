--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Proximity

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)

local Proximity = {}
local metric = Theme.metric
local surfaces = Theme.surface
local em = Theme.em
local newFrame = Primitives.NewFrame
local newLabel = Primitives.NewLabel
local newList = Primitives.NewList
local setText = Primitives.SetText
function Proximity.CreateProximityButton(
	parent: Instance,
	icon: string,
	caption: string,
	tint: Color3,
	root: number
): (Frame, ImageButton)
	local group = newFrame("Proximity" .. caption, parent)
	group.Size = UDim2.fromOffset(metric.proximitySize, metric.proximitySize + 18)
	local groupLayout = newList(group, Enum.FillDirection.Vertical, 3)
	groupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	groupLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local button = Instance.new("ImageButton")
	button.Name = "Button"
	button.Size = UDim2.fromOffset(metric.proximitySize, metric.proximitySize)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	button.BackgroundTransparency = 0.38
	button.Image = icon
	button.ImageColor3 = tint
	button.ScaleType = Enum.ScaleType.Fit
	button.LayoutOrder = 1
	button.Parent = group
	Theme.Pill(button)
	Theme.Padding(button, 13, 13, 13, 13)
	Theme.Ring(button, tint, 2).Transparency = 0.45

	local label = newLabel("Caption", group)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 15)
	setText(label, em.statLabel, root)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = caption
	label.LayoutOrder = 2
	Theme.Paint(label, surfaces.badge)
	Theme.Pill(label)
	Theme.Padding(label, 0, 7, 0, 7)

	return group, button
end

return Proximity
