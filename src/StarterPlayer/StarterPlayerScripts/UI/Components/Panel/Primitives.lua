--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Primitives

local Theme = require(script.Parent.Parent.Parent.Theme)

local Primitives = {}

function Primitives.NewFrame(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

function Primitives.NewLabel(name: string, parent: Instance?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = Theme.font.extraBold
	label.TextColor3 = Theme.textColors.strong
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = false
	label.Parent = parent
	return label
end

function Primitives.NewList(
	parent: Instance,
	direction: Enum.FillDirection,
	gap: number
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = parent
	return layout
end

function Primitives.FlexFill(instance: GuiObject): UIFlexItem
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = instance
	return flex
end

local function setTextSize(instance: TextLabel | TextButton, size: number)
	if instance:IsA("TextLabel") then
		instance.TextSize = size
		return
	end
	instance.TextSize = size
end

function Primitives.SetText(
	instance: TextLabel | TextButton,
	em: number,
	root: number,
	scale: number?
)
	instance:SetAttribute("Em", em)
	instance:SetAttribute("EmScale", scale)
	local size = Theme.Text(em, root) * (scale or 1)
	setTextSize(instance, size)
end

local function rescaleLabel(label: TextLabel | TextButton, root: number)
	local em = label:GetAttribute("Em")
	if type(em) ~= "number" then
		return
	end
	local attributeScale = label:GetAttribute("EmScale")
	local scale = if type(attributeScale) == "number" then attributeScale else 1
	local size = Theme.Text(em, root) * scale
	setTextSize(label, size)
	local heightPadding = label:GetAttribute("TextHeightPadding")
	if type(heightPadding) == "number" then
		local oldSize = label.Size
		local newSize = UDim2.new(
			oldSize.X.Scale,
			oldSize.X.Offset,
			oldSize.Y.Scale,
			math.ceil(size) + heightPadding
		)
		local guiObject: GuiObject = label
		guiObject.Size = newSize
	end
end

function Primitives.RescaleText(container: Instance, root: number)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			rescaleLabel(descendant, root)
		end
	end
end

--- Applies a menu-wide text multiplier without compounding it when responsive layout code
--- re-applies the scale. Any component-specific EmScale remains the stable base value.
function Primitives.ApplyTextScale(container: Instance, root: number, scale: number)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:GetAttribute("Em") then
			local savedScale = descendant:GetAttribute("BaseEmScale")
			local baseScale = if type(savedScale) == "number" then savedScale else 1
			if type(savedScale) ~= "number" then
				local attributeScale = descendant:GetAttribute("EmScale")
				baseScale = if type(attributeScale) == "number" then attributeScale else 1
				descendant:SetAttribute("BaseEmScale", baseScale)
			end
			descendant:SetAttribute("EmScale", baseScale * scale)
		end
	end
	Primitives.RescaleText(container, root)
end

return Primitives
