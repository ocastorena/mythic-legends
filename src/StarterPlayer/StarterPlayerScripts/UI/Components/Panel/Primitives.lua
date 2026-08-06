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
	label.FontFace = Theme.Font.extraBold
	label.TextColor3 = Theme.Text.strong
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = false
	label.Parent = parent
	return label
end

function Primitives.NewList(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
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

function Primitives.SetText(instance: TextLabel | TextButton, em: number, root: number, scale: number?)
	instance:SetAttribute("Em", em)
	instance:SetAttribute("EmScale", scale)
	instance.TextSize = Theme.text(em, root) * (scale or 1)
end

function Primitives.RescaleText(container: Instance, root: number)
	for _, descendant in ipairs(container:GetDescendants()) do
		local em = descendant:GetAttribute("Em")
		if em and (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
			local scale = descendant:GetAttribute("EmScale") or 1
			descendant.TextSize = Theme.text(em, root) * scale

			local heightPadding = descendant:GetAttribute("TextHeightPadding")
			if heightPadding then
				descendant.Size = UDim2.new(
					descendant.Size.X.Scale,
					descendant.Size.X.Offset,
					descendant.Size.Y.Scale,
					math.ceil(descendant.TextSize) + heightPadding
				)
			end
		end
	end
end

--- Applies a menu-wide text multiplier without compounding it when responsive layout code
--- re-applies the scale. Any component-specific EmScale remains the stable base value.
function Primitives.ApplyTextScale(container: Instance, root: number, scale: number)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:GetAttribute("Em") then
			local baseScale = descendant:GetAttribute("BaseEmScale")
			if not baseScale then
				baseScale = descendant:GetAttribute("EmScale") or 1
				descendant:SetAttribute("BaseEmScale", baseScale)
			end
			descendant:SetAttribute("EmScale", baseScale * scale)
		end
	end
	Primitives.RescaleText(container, root)
end

return Primitives
