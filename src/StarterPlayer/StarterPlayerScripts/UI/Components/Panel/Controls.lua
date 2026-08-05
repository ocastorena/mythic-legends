-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Controls

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)

local Controls = {}

local Metric = Theme.Metric
local Radius = Theme.Radius
local Surface = Theme.Surface
local Em = Theme.Em

function Controls.SetTabActive(button: TextButton, active: boolean, accent: Color3?)
	local tint = accent or Theme.Accent.gold
	if active then
		button.BackgroundColor3 = tint
		button.BackgroundTransparency = 0
		button.TextColor3 = Theme.Ink.onGold
		button.TextTransparency = 0
		button.FontFace = Theme.Font.extraBold
	else
		Theme.paint(button, Surface.chip)
		button.TextColor3 = tint
		button.TextTransparency = 0.4
		button.FontFace = Theme.Font.bold
	end
end

function Controls.Tab(parent: Instance, text: string, accent: Color3?, root: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.fromOffset(Metric.tabWidth, Metric.tabHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = text
	button.FontFace = Theme.Font.extraBold
	Primitives.SetText(button, Em.tab, root)
	button.Parent = parent
	Theme.corner(button, Radius.tab)
	Controls.SetTabActive(button, false, accent)
	return button
end

function Controls.SetButtonEnabled(button: TextButton, enabled: boolean, accent: Color3?)
	if accent then
		button:SetAttribute("Accent", accent)
	end
	local tint = button:GetAttribute("Accent") or Theme.Accent.gold
	button.Active = enabled
	button.Selectable = enabled

	if enabled then
		button.BackgroundColor3 = tint
		button.BackgroundTransparency = 0
		button.TextColor3 = if tint == Theme.Accent.green
			then Theme.Ink.onGreen
			elseif tint == Theme.Accent.red then Theme.Ink.onRed
			else Theme.Ink.onGold
		button.TextTransparency = 0
	else
		Theme.paint(button, Surface.chip)
		button.TextColor3 = Theme.Text.dim
		button.TextTransparency = 0.6
	end
end

function Controls.PrimaryButton(parent: Instance, text: string, root: number, accent: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "PrimaryButton"
	button.Size = UDim2.new(1, 0, 0, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = text
	button.FontFace = Theme.Font.extraBold
	Primitives.SetText(button, Em.body, root)
	button.Parent = parent
	Theme.corner(button, Radius.button)
	Controls.SetButtonEnabled(button, true, accent)
	return button
end

function Controls.SquareButton(parent: Instance, icon: string, tint: Color3?): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = "SquareButton"
	button.Size = UDim2.fromOffset(Metric.squareButton, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = tint or Theme.Accent.gold
	button.BackgroundTransparency = 0.88
	button.Image = icon
	button.ImageColor3 = tint or Theme.Accent.gold
	button.ScaleType = Enum.ScaleType.Fit
	button.Parent = parent
	Theme.corner(button, Radius.buttonSmall)
	Theme.padding(button, 9, 9, 9, 9)
	return button
end

function Controls.SquareTextButton(parent: Instance, glyph: string, root: number, tint: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "SquareButton"
	button.Size = UDim2.fromOffset(Metric.squareButton, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = tint or Theme.Accent.gold
	button.BackgroundTransparency = 0.88
	button.Text = glyph
	button.FontFace = Theme.Font.heavy
	Primitives.SetText(button, Em.panelTitle, root)
	button.TextColor3 = tint or Theme.Accent.gold
	button.Parent = parent
	Theme.corner(button, Radius.buttonSmall)
	return button
end

function Controls.CloseButton(parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = "CloseButton"
	button.Size = UDim2.fromOffset(Metric.closeSize, Metric.closeSize)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = parent
	Theme.paint(button, Surface.chip)
	button.BackgroundTransparency = 0.9
	Theme.pill(button)

	for _, angle in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(13, 2)
		bar.Rotation = angle
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Theme.Text.strong
		bar.BackgroundTransparency = 0.15
		bar.Parent = button
		Theme.pill(bar)
	end

	return button
end

function Controls.CoinPill(parent: Instance, icon: string, root: number, height: number?): (Frame, TextLabel)
	local pillHeight = height or 26
	local scale = pillHeight / 26
	local pill = Primitives.NewFrame("CoinPill", parent)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, pillHeight)
	Theme.paint(pill, Surface.chip)
	Theme.pill(pill)
	Theme.padding(pill, 0, math.round(11 * scale), 0, math.round(8 * scale))
	Primitives.NewList(pill, Enum.FillDirection.Horizontal, math.round(5 * scale))

	local iconSize = math.round(15 * scale)
	local coin = Instance.new("ImageLabel")
	coin.Name = "Icon"
	coin.BackgroundTransparency = 1
	coin.Size = UDim2.fromOffset(iconSize, iconSize)
	coin.Image = icon
	coin.ScaleType = Enum.ScaleType.Fit
	coin.LayoutOrder = 1
	coin.Parent = pill

	local label = Primitives.NewLabel("Amount", pill)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, pillHeight)
	Primitives.SetText(label, Em.sectionLabel, root, scale)
	label.TextColor3 = Theme.Text.coin
	label.LayoutOrder = 2
	label.Text = "0"
	return pill, label
end

function Controls.LevelPill(parent: Instance, root: number, accent: Color3?): TextLabel
	local tint = accent or Theme.Accent.gold
	local label = Primitives.NewLabel("LevelPill", parent)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 22)
	label.BackgroundColor3 = tint
	label.BackgroundTransparency = 0.84
	label.TextColor3 = tint
	label.FontFace = Theme.Font.heavy
	Primitives.SetText(label, Em.caption, root)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = ""
	Theme.pill(label)
	Theme.padding(label, 0, 10, 0, 10)
	return label
end

return Controls
