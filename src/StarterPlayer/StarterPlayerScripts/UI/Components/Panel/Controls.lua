-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Controls

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)

local Controls = {}

local Metric = Theme.Metric
local Radius = Theme.Radius
local Surface = Theme.Surface
local Em = Theme.Em

local function setTabIconTransparency(icon: Instance?, transparency: number)
	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		icon.ImageTransparency = transparency
	elseif icon and icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

function Controls.SetTabActive(button: TextButton, active: boolean, _accent: Color3?)
	button:SetAttribute("Active", active)
	local tabLabel = button:FindFirstChild("TabLabel")
	local title = tabLabel and tabLabel:FindFirstChild("Title")
	local icon = tabLabel and tabLabel:FindFirstChild("Icon")
	local selection = button:FindFirstChild("TabSelection")

	if title and title:IsA("TextLabel") then
		title.TextTransparency = if active then 0 else 0.5
	end
	setTabIconTransparency(icon, if active then 0 else 0.5)
	if selection and selection:IsA("Frame") then
		selection.Visible = active
	end
end

function Controls.Tab(
	parent: Instance,
	text: string,
	accent: Color3?,
	root: number,
	iconAsset: string?,
	iconColor: Color3?
): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.fromOffset(Metric.tabWidth, Metric.tabHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Parent = parent

	local tabLabel = Instance.new("Frame")
	tabLabel.Name = "TabLabel"
	tabLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	tabLabel.Position = UDim2.fromScale(0.5, 0.5)
	tabLabel.Size = UDim2.fromScale(1, 1)
	tabLabel.BackgroundTransparency = 1
	tabLabel.Parent = button
	local layout = Primitives.NewList(tabLabel, Enum.FillDirection.Horizontal, Metric.tabIconGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	if iconAsset then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.fromOffset(Metric.tabIconSize, Metric.tabIconSize)
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.Image = iconAsset
		icon.ImageColor3 = iconColor or Theme.Text.strong
		icon.ScaleType = Enum.ScaleType.Fit
		icon.LayoutOrder = 1
		icon.Parent = tabLabel
	end

	local title = Primitives.NewLabel("Title", tabLabel)
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.Size = UDim2.fromOffset(0, Metric.tabHeight)
	title.FontFace = Theme.Font.bold
	title.Text = text
	title.TextColor3 = Theme.Text.strong
	Primitives.SetText(title, Em.tab, root)
	title.LayoutOrder = 2

	local selection = Instance.new("Frame")
	selection.Name = "TabSelection"
	selection.AnchorPoint = Vector2.new(0.5, 1)
	selection.Position = UDim2.fromScale(0.5, 1)
	selection.Size = UDim2.new(1, -2, 0, 2)
	selection.BackgroundColor3 = Theme.Text.strong
	selection.BorderSizePixel = 0
	selection.Visible = false
	selection.Parent = button

	button.MouseEnter:Connect(function()
		if button:GetAttribute("Active") then
			return
		end
		title.TextTransparency = 0.2
		setTabIconTransparency(tabLabel:FindFirstChild("Icon"), 0.2)
	end)
	button.MouseLeave:Connect(function()
		if button:GetAttribute("Active") then
			return
		end
		title.TextTransparency = 0.5
		setTabIconTransparency(tabLabel:FindFirstChild("Icon"), 0.5)
	end)

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

function Controls.MoreButton(parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = "MoreButton"
	button.Size = UDim2.fromOffset(Metric.squareButton, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = parent
	Theme.paint(button, Surface.chipStrong)
	Theme.corner(button, Radius.buttonSmall)

	local dots = Instance.new("Frame")
	dots.Name = "Icon"
	dots.AnchorPoint = Vector2.new(0.5, 0.5)
	dots.Position = UDim2.fromScale(0.5, 0.5)
	dots.Size = UDim2.fromOffset(22, 6)
	dots.BackgroundTransparency = 1
	dots.Parent = button

	for index = 1, 3 do
		local dot = Instance.new("Frame")
		dot.Name = `Dot{index}`
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale((index - 1) / 2, 0.5)
		dot.Size = UDim2.fromOffset(5, 5)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = Theme.Text.strong
		dot.Parent = dots
		Theme.pill(dot)
	end

	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0.76
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = Surface.chipStrong.transparency
	end)

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
