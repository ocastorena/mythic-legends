-- StarterPlayer/StarterPlayerScripts/UI/PanelUtil
-- The panel shell and its parts, as described by §03-§08 of the design system.
--
-- The design doc's own instruction is to build every menu by composing one shell rather
-- than laying each menu out by hand: scrim over the world, a centered card, a header row
-- (identity left · tabs center · actions right), and a body split grid 2/3 · details 1/3.
-- This module is that shell. A controller says what goes in it, never where it goes.
--
--   local panel = PanelUtil.panel({
--       parent = screenGui,
--       title = "Inventory",
--       titleIcon = "rbxassetid://...",
--       tabs = { "Mythlings", "Materials" },
--       coins = true,
--       onClose = function() ... end,
--   })
--   local details = PanelUtil.details(panel.Details, { stats = 3, progress = true })
--
-- The scrim is deliberately absent: the application overlay owns the shared ModalBackdropGui
-- ScreenGui, so a panel that drew its own would double-darken the world.

local ThemeUtil = require(script.Parent.ThemeUtil)

local PanelUtil = {}

local Metric = ThemeUtil.Metric
local Radius = ThemeUtil.Radius
local Surface = ThemeUtil.Surface
local Em = ThemeUtil.Em

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local function newFrame(name: string, parent: Instance?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function newLabel(name: string, parent: Instance?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = ThemeUtil.Font.extraBold
	label.TextColor3 = ThemeUtil.Text.strong
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = false
	label.Parent = parent
	return label
end

--- A horizontal or vertical flex row. `gap` is the design's `gap` in pixels.
local function newList(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = parent
	return layout
end

--- `flex: 1` — take the leftover space on the layout's axis.
local function flexFill(instance: GuiObject): UIFlexItem
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = instance
	return flex
end

--- Sizes text from an em multiple, and records the multiple on the instance so the panel
--- can re-derive it later.
---
--- The design sizes every label in em against a per-device root, and that root changes
--- when a window crosses a breakpoint -- a desktop player dragging their window narrow is
--- a phone by the doc's rules. Stamping the multiple as an attribute means `rescaleText`
--- can walk a whole panel and reapply it without a registry to keep in sync, and because
--- attributes survive `:Clone()`, grid cells stamped on the template stay correct too.
local function setText(instance: TextLabel | TextButton, em: number, root: number, scale: number?)
	instance:SetAttribute("Em", em)
	instance:SetAttribute("EmScale", scale)
	instance.TextSize = ThemeUtil.text(em, root) * (scale or 1)
end

--- Reapplies every em-stamped text size under `container` against a new device root.
function PanelUtil.rescaleText(container: Instance, root: number)
	for _, descendant in ipairs(container:GetDescendants()) do
		local em = descendant:GetAttribute("Em")
		if em and (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then
			local scale = descendant:GetAttribute("EmScale") or 1
			descendant.TextSize = ThemeUtil.text(em, root) * scale

			-- Labels whose height is derived from their font must be remeasured too.
			-- Updating only TextSize made the inventory stats grow or shrink inside a
			-- stale desktop-height box after crossing a device breakpoint.
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

--------------------------------------------------------------------------------
-- 04 · Tabs
--------------------------------------------------------------------------------

--- One 88px pill. Active is a solid accent fill with dark ink; inactive is a faint fill
--- with dimmed accent text.
function PanelUtil.tab(parent: Instance, text: string, accent: Color3?, root: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.Size = UDim2.fromOffset(Metric.tabWidth, Metric.tabHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = text
	button.FontFace = ThemeUtil.Font.extraBold
	setText(button, Em.tab, root)
	button.Parent = parent
	ThemeUtil.corner(button, Radius.tab)
	PanelUtil.setTabActive(button, false, accent or ThemeUtil.Accent.gold)
	return button
end

--- Repaints a pill for its active state. Kept separate from `tab` so a controller can
--- flip tabs without knowing the token values.
function PanelUtil.setTabActive(button: TextButton, active: boolean, accent: Color3?)
	local tint = accent or ThemeUtil.Accent.gold
	if active then
		button.BackgroundColor3 = tint
		button.BackgroundTransparency = 0
		button.TextColor3 = ThemeUtil.Ink.onGold
		button.TextTransparency = 0
		button.FontFace = ThemeUtil.Font.extraBold
	else
		ThemeUtil.paint(button, Surface.chip)
		button.TextColor3 = tint
		button.TextTransparency = 0.4
		button.FontFace = ThemeUtil.Font.bold
	end
end

--------------------------------------------------------------------------------
-- 07 · Buttons · 08 · Badges & pills
--------------------------------------------------------------------------------

--- The wide footer button: accent fill, dark ink, 11px radius, `flex: 1`.
function PanelUtil.primaryButton(parent: Instance, text: string, root: number, accent: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "PrimaryButton"
	button.Size = UDim2.new(1, 0, 0, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = text
	button.FontFace = ThemeUtil.Font.extraBold
	setText(button, Em.body, root)
	button.Parent = parent
	ThemeUtil.corner(button, Radius.button)
	PanelUtil.setButtonEnabled(button, true, accent or ThemeUtil.Accent.gold)
	return button
end

--- Disabled is a faint fill with a muted label, per §07. The accent is remembered so
--- re-enabling restores the right colour without the caller passing it again.
function PanelUtil.setButtonEnabled(button: TextButton, enabled: boolean, accent: Color3?)
	if accent then
		button:SetAttribute("Accent", accent)
	end
	local tint = button:GetAttribute("Accent") or ThemeUtil.Accent.gold
	button.Active = enabled
	button.Selectable = enabled

	if enabled then
		button.BackgroundColor3 = tint
		button.BackgroundTransparency = 0
		button.TextColor3 = if tint == ThemeUtil.Accent.green
			then ThemeUtil.Ink.onGreen
			elseif tint == ThemeUtil.Accent.red then ThemeUtil.Ink.onRed
			else ThemeUtil.Ink.onGold
		button.TextTransparency = 0
	else
		ThemeUtil.paint(button, Surface.chip)
		button.TextColor3 = ThemeUtil.Text.dim
		button.TextTransparency = 0.6
	end
end

--- The 44px square that sits beside a primary button: a tinted icon well.
function PanelUtil.squareButton(parent: Instance, icon: string, tint: Color3?): ImageButton
	local button = Instance.new("ImageButton")
	button.Name = "SquareButton"
	button.Size = UDim2.fromOffset(Metric.squareButton, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = tint or ThemeUtil.Accent.gold
	button.BackgroundTransparency = 0.88
	button.Image = icon
	button.ImageColor3 = tint or ThemeUtil.Accent.gold
	button.ScaleType = Enum.ScaleType.Fit
	button.Parent = parent
	ThemeUtil.corner(button, Radius.buttonSmall)
	ThemeUtil.padding(button, 9, 9, 9, 9)
	return button
end

--- The same square well, but carrying a glyph instead of an image. The design draws its
--- secondary actions as inline SVG, including a bare `+` for "add to this slot"; a text
--- glyph is the asset-free equivalent of that icon language.
function PanelUtil.squareTextButton(parent: Instance, glyph: string, root: number, tint: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name = "SquareButton"
	button.Size = UDim2.fromOffset(Metric.squareButton, Metric.buttonHeight)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = tint or ThemeUtil.Accent.gold
	button.BackgroundTransparency = 0.88
	button.Text = glyph
	button.FontFace = ThemeUtil.Font.heavy
	setText(button, Em.panelTitle, root)
	button.TextColor3 = tint or ThemeUtil.Accent.gold
	button.Parent = parent
	ThemeUtil.corner(button, Radius.buttonSmall)
	return button
end

--- The round ✕ in a panel header.
---
--- The glyph is drawn from two rotated bars rather than set as text: Nunito has no ✕
--- (U+2715), so a text button renders it as a fallback box or drops it entirely.
function PanelUtil.closeButton(parent: Instance, root: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = "CloseButton"
	button.Size = UDim2.fromOffset(Metric.closeSize, Metric.closeSize)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = parent
	ThemeUtil.paint(button, Surface.chip)
	button.BackgroundTransparency = 0.9
	ThemeUtil.pill(button)

	for _, angle in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(13, 2)
		bar.Rotation = angle
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = ThemeUtil.Text.strong
		bar.BackgroundTransparency = 0.15
		bar.Parent = button
		ThemeUtil.pill(bar)
	end

	return button
end

--- Coin pill: rounded chip, coin glyph, gold figures. Returns the pill and its label.
---
--- `height` defaults to the design's in-panel size. The HUD passes the top bar's button
--- size instead, so the pill matches the height of Roblox's own chrome beside it; every
--- part scales off that rather than being pinned to the panel-sized numbers.
function PanelUtil.coinPill(parent: Instance, icon: string, root: number, height: number?): (Frame, TextLabel)
	local pillHeight = height or 26
	local scale = pillHeight / 26

	local pill = newFrame("CoinPill", parent)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, pillHeight)
	ThemeUtil.paint(pill, Surface.chip)
	ThemeUtil.pill(pill)
	ThemeUtil.padding(pill, 0, math.round(11 * scale), 0, math.round(8 * scale))
	newList(pill, Enum.FillDirection.Horizontal, math.round(5 * scale))

	local iconSize = math.round(15 * scale)
	local coin = Instance.new("ImageLabel")
	coin.Name = "Icon"
	coin.BackgroundTransparency = 1
	coin.Size = UDim2.fromOffset(iconSize, iconSize)
	coin.Image = icon
	coin.ScaleType = Enum.ScaleType.Fit
	coin.LayoutOrder = 1
	coin.Parent = pill

	local label = newLabel("Amount", pill)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, pillHeight)
	setText(label, Em.sectionLabel, root, scale)
	label.TextColor3 = ThemeUtil.Text.coin
	label.LayoutOrder = 2
	label.Text = "0"

	return pill, label
end

--- "Level 3" pill, tinted to the menu's accent.
function PanelUtil.levelPill(parent: Instance, root: number, accent: Color3?): TextLabel
	local tint = accent or ThemeUtil.Accent.gold
	local label = newLabel("LevelPill", parent)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 22)
	label.BackgroundColor3 = tint
	label.BackgroundTransparency = 0.84
	label.TextColor3 = tint
	label.FontFace = ThemeUtil.Font.heavy
	setText(label, Em.caption, root)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = ""
	ThemeUtil.pill(label)
	ThemeUtil.padding(label, 0, 10, 0, 10)
	return label
end

--------------------------------------------------------------------------------
-- 03 · Panel shell
--------------------------------------------------------------------------------

export type PanelConfig = {
	parent: Instance,
	title: string,
	-- Optional feature-specific responsive size. Placement, safe-area handling and text
	-- scaling remain owned by the shared shell.
	size: ((Vector2) -> UDim2)?,
	-- Left-hand identity glyph. An image id, or nil for a title-only header.
	titleIcon: string?,
	-- Optional image box size for artwork with built-in transparent margins.
	titleIconSize: number?,
	-- Draws the glyph as a filled element disc rather than a flat icon (the shrine header).
	iconColor: Color3?,
	-- Tab labels, centered in the header. Omit for a panel with no tabs.
	tabs: { string }?,
	-- Adds the coin pill to the header actions.
	coins: boolean?,
	coinIcon: string?,
	-- Adds a "Level n" pill to the header actions.
	levelPill: boolean?,
	-- Menu accent. Gold unless the menu says otherwise (cyan for crafting).
	accent: Color3?,
	onClose: (() -> ())?,
}

export type Panel = {
	Card: Frame,
	Header: Frame,
	Body: Frame,
	Grid: Frame,
	Details: Frame,
	TitleLabel: TextLabel,
	TitleIcon: ImageLabel?,
	Tabs: { [string]: TextButton },
	CoinLabel: TextLabel?,
	LevelLabel: TextLabel?,
	CloseButton: TextButton,
	Root: number,
	Accent: Color3,
}

--- Builds the shell. Sized against the current viewport, and re-sized whenever that
--- changes so one panel serves phone, tablet and desktop.
function PanelUtil.panel(config: PanelConfig): Panel
	local accent = config.accent or ThemeUtil.Accent.gold
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local root = ThemeUtil.root(viewport)

	-- Every application panel uses Roblox's live safe canvas. This avoids timing-sensitive
	-- manual inset measurements while keeping controls clear of CoreGui and device notches.
	local screenGui = config.parent:IsA("ScreenGui") and config.parent
		or config.parent:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui then
		ThemeUtil.useSafeCanvas(screenGui)
	end

	local function resolveCardSize(size: Vector2): UDim2
		return config.size and config.size(size) or ThemeUtil.panelSize(size)
	end

	local card = newFrame("Card", config.parent)
	local anchor, position = ThemeUtil.panelPlacement(viewport)
	card.AnchorPoint = anchor
	card.Position = position
	card.Size = resolveCardSize(viewport)
	card.ClipsDescendants = true
	ThemeUtil.paint(card, Surface.panel)
	ThemeUtil.corner(card, Radius.card)

	local cardLayout = newList(card, Enum.FillDirection.Vertical, 0)
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	-- No safe-area padding along the bottom: the grid and details deliberately extend into the
	-- strip the phone reserves for its home indicator, so the space the card gained is space
	-- the content actually uses. Padding it back left the content exactly where it had been
	-- and only the background grew. The body's own 16px padding keeps the last row and the
	-- footer button off the physical edge.

	-- Header: three groups, so the tab set stays centered in the card rather than
	-- drifting with the width of the identity and action groups.
	local header = newFrame("Header", card)
	header.Size = UDim2.new(1, 0, 0, Metric.headerPadTop + Metric.closeSize + Metric.headerPadBottom)
	header.LayoutOrder = 1
	ThemeUtil.padding(header, Metric.headerPadTop, Metric.headerPadRight, Metric.headerPadBottom, Metric.headerPadLeft)

	local identity = newFrame("Identity", header)
	identity.AnchorPoint = Vector2.new(0, 0.5)
	identity.Position = UDim2.fromScale(0, 0.5)
	identity.Size = UDim2.new(0, 0, 1, 0)
	identity.AutomaticSize = Enum.AutomaticSize.X
	newList(identity, Enum.FillDirection.Horizontal, 10)

	local titleIcon: ImageLabel? = nil
	if config.titleIcon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BorderSizePixel = 0
		icon.Image = config.titleIcon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.LayoutOrder = 1
		icon.Parent = identity
		if config.iconColor then
			-- The shrine header's glyph sits on a filled element disc.
			icon.Size = UDim2.fromOffset(34, 34)
			icon.BackgroundColor3 = config.iconColor
			icon.BackgroundTransparency = 0
			ThemeUtil.pill(icon)
			ThemeUtil.padding(icon, 7, 7, 7, 7)
		else
			local iconSize = config.titleIconSize or 20
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
			icon.BackgroundTransparency = 1
			icon.ImageColor3 = accent
		end
		titleIcon = icon
	end

	local titleLabel = newLabel("Title", identity)
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.new(0, 0, 1, 0)
	setText(titleLabel, Em.panelTitle, root)
	titleLabel.Text = config.title
	titleLabel.LayoutOrder = 2

	local tabs: { [string]: TextButton } = {}
	if config.tabs then
		local tabRow = newFrame("Tabs", header)
		tabRow.AnchorPoint = Vector2.new(0.5, 0.5)
		tabRow.Position = UDim2.fromScale(0.5, 0.5)
		tabRow.Size = UDim2.new(0, 0, 1, 0)
		tabRow.AutomaticSize = Enum.AutomaticSize.X
		local row = newList(tabRow, Enum.FillDirection.Horizontal, Metric.tabGap)
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for index, name in ipairs(config.tabs) do
			local tab = PanelUtil.tab(tabRow, name, accent, root)
			tab.LayoutOrder = index
			tabs[name] = tab
		end
	end

	local actions = newFrame("Actions", header)
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.Position = UDim2.fromScale(1, 0.5)
	actions.Size = UDim2.new(0, 0, 1, 0)
	actions.AutomaticSize = Enum.AutomaticSize.X
	newList(actions, Enum.FillDirection.Horizontal, 10)

	local coinLabel: TextLabel? = nil
	if config.coins then
		local pill, label = PanelUtil.coinPill(actions, config.coinIcon or "", root)
		pill.LayoutOrder = 1
		coinLabel = label
	end

	local levelLabel: TextLabel? = nil
	if config.levelPill then
		levelLabel = PanelUtil.levelPill(actions, root, accent)
		;(levelLabel :: TextLabel).LayoutOrder = 2
	end

	local closeButton = PanelUtil.closeButton(actions, root)
	closeButton.LayoutOrder = 3

	-- Body: grid 2fr · details 1fr · gap 14, at every size.
	local body = newFrame("Body", card)
	body.Size = UDim2.new(1, 0, 1, 0)
	body.LayoutOrder = 2
	flexFill(body)
	ThemeUtil.padding(body, Metric.bodyPadTop, Metric.bodyPad, Metric.bodyPad, Metric.bodyPad)
	local bodyLayout = newList(body, Enum.FillDirection.Horizontal, Metric.bodyGap)
	bodyLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local grid = newFrame("Grid", body)
	grid.Size = UDim2.new(1, 0, 1, 0)
	grid.LayoutOrder = 1
	flexFill(grid)

	local details = newFrame("Details", body)
	details.Size = UDim2.new(0, ThemeUtil.detailWidth(viewport), 1, 0)
	details.LayoutOrder = 2

	if config.onClose then
		closeButton.Activated:Connect(config.onClose)
	end

	-- Rotating a phone or resizing a window changes which device root applies, so the card
	-- is re-measured and every em-sized label re-derived against the new root. The details
	-- pane and grid live under this card, so one pass covers them.
	if camera then
		local viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local size = camera.ViewportSize
			card.Size = resolveCardSize(size)
			card.AnchorPoint, card.Position = ThemeUtil.panelPlacement(size)
			details.Size = UDim2.new(0, ThemeUtil.detailWidth(size), 1, 0)
			PanelUtil.rescaleText(card, ThemeUtil.root(size))
		end)
		card.Destroying:Once(function()
			viewportConnection:Disconnect()
		end)
	end

	return {
		Card = card,
		Header = header,
		Body = body,
		Grid = grid,
		Details = details,
		TitleLabel = titleLabel,
		TitleIcon = titleIcon,
		Tabs = tabs,
		CoinLabel = coinLabel,
		LevelLabel = levelLabel,
		CloseButton = closeButton,
		Root = root,
		Accent = accent,
	}
end

--------------------------------------------------------------------------------
-- 05 · Grid cell
--------------------------------------------------------------------------------

-- A selected cell's ring is 3px of border-mode stroke drawn outside the cell. One extra
-- pixel keeps it clear of the scroll frame's edge.
local RING_BLEED = 4

--- Width the grid column ends up with, derived from the shell's own metrics rather than
--- measured: AbsoluteSize is still zero when a panel is built, one frame before layout.
local function gridColumnWidth(viewport: Vector2): number
	-- A phone panel is sized in scale against the full-screen canvas, so its offset is a
	-- negative inset correction rather than a width. Its pixel width is the safe band, which
	-- is what the camera viewport measures.
	local panelWidth = if ThemeUtil.isPhone(viewport)
		then viewport.X
		else ThemeUtil.panelSize(viewport).X.Offset
	return panelWidth - 2 * Metric.bodyPad - Metric.bodyGap - ThemeUtil.detailWidth(viewport)
end

--- The scrolling grid that fills the panel's 2/3 column. Cells are the design's fixed
--- 112px squares; phones fall back to four equal columns, as the canvas does.
function PanelUtil.grid(parent: Instance): ScrollingFrame
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cells"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255)
	scroll.ScrollBarImageTransparency = 0.72
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = parent

	-- Two separate reservations, both inside the scroll frame:
	--
	--   * the scroll bar is drawn inside the frame, so cells laid out across the full width
	--     run underneath it and the right-hand column gets clipped;
	--   * a cell's rarity ring is a border-mode UIStroke, which draws *outside* the cell's
	--     bounds. Without room for it the top row's ring is sliced off by the scroll frame,
	--     which reads as the cards themselves being cut off along the top edge.
	ThemeUtil.padding(scroll, RING_BLEED, scroll.ScrollBarThickness + RING_BLEED, RING_BLEED, RING_BLEED)

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(Metric.cellGap, Metric.cellGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	--- Phones get four equal columns; everything else gets the fixed 112px cell.
	local function applyCellSize(size: Vector2)
		if size.Y < 500 then
			local usable = gridColumnWidth(size) - scroll.ScrollBarThickness - 2 * RING_BLEED
			local cell = math.max(48, math.floor((usable - 3 * Metric.cellGap) / 4))
			layout.CellSize = UDim2.fromOffset(cell, cell)
		else
			layout.CellSize = UDim2.fromOffset(Metric.cellSize, Metric.cellSize)
		end
	end
	applyCellSize(viewport)

	if camera then
		local viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			applyCellSize(camera.ViewportSize)
		end)
		scroll.Destroying:Once(function()
			viewportConnection:Disconnect()
		end)
	end

	return scroll
end

export type CellConfig = {
	parent: Instance,
	-- Adds the "Lv 12" badge bottom-left.
	level: boolean?,
	-- Adds the green ✓ top-right for equipped/stationed.
	check: boolean?,
	-- Adds the "x4" count badge, for stackable entries.
	quantity: boolean?,
	root: number,
}

--- The cell template CardListUtil clones: a square, faint fill, the artwork inset inside
--- the rarity ring, and overlay badges created up front and left invisible so a clone only
--- has to toggle them.
---
--- The doc floats a transparent glyph at 52% of the cell. This game's thumbnails carry an
--- opaque background, and at 52% each one read as a hard-edged square stranded inside a
--- rounded cell -- worse still, the backing colour differs per creature, so a grid of them
--- looked like mismatched stickers. Filling the cell and matching the corner radius turns
--- that backing into the tile itself.
function PanelUtil.cellTemplate(config: CellConfig): ImageButton
	local cell = Instance.new("ImageButton")
	cell.Name = "CardTemplate"
	cell.Size = UDim2.fromOffset(Metric.cellSize, Metric.cellSize)
	cell.AutoButtonColor = false
	cell.BorderSizePixel = 0
	cell.Image = ""
	cell.Visible = false
	cell.ClipsDescendants = false
	cell.Parent = config.parent
	ThemeUtil.paint(cell, Surface.cell)
	ThemeUtil.corner(cell, Radius.cell)
	ThemeUtil.ring(cell, ThemeUtil.Rarity.Fabled, 2)

	-- A restrained top light keeps the dark card from reading as a flat black tile while
	-- leaving rarity colour exclusively to the ring.
	local backgroundGradient = Instance.new("UIGradient")
	backgroundGradient.Name = "BackgroundGradient"
	backgroundGradient.Rotation = 90
	backgroundGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 216, 235)),
	})
	backgroundGradient.Parent = cell

	-- Kept named 2dPreview: every controller and CardListUtil decorator already sets
	-- this child's Image.
	local preview = Instance.new("ImageLabel")
	preview.Name = "2dPreview"
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.Position = UDim2.fromScale(0.5, 0.5)
	-- Inset by the ring's own thickness so the rarity ring still reads as a ring around the
	-- art rather than a border drawn on top of it.
	preview.Size = UDim2.new(1, -6, 1, -6)
	preview.BackgroundTransparency = 1
	preview.BorderSizePixel = 0
	preview.ScaleType = Enum.ScaleType.Fit
	preview.Parent = cell
	ThemeUtil.corner(preview, Radius.cell - 3)

	if config.level then
		local badge = newLabel("LevelBadge", cell)
		badge.AnchorPoint = Vector2.new(0, 1)
		badge.Position = UDim2.new(0, 3, 1, -3)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 15)
		setText(badge, Em.badge, config.root)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.Text = ""
		badge.Visible = false
		ThemeUtil.paint(badge, Surface.badge)
		ThemeUtil.corner(badge, Radius.badge)
		ThemeUtil.padding(badge, 0, 6, 0, 6)
	end

	if config.quantity then
		local badge = newLabel("QuantityLabel", cell)
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, -3, 1, -3)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 15)
		setText(badge, Em.badge, config.root)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.TextColor3 = ThemeUtil.Text.coin
		badge.Text = ""
		ThemeUtil.paint(badge, Surface.badge)
		ThemeUtil.corner(badge, Radius.badge)
		ThemeUtil.padding(badge, 0, 6, 0, 6)
	end

	if config.check then
		local check = newLabel("EquippedCheck", cell)
		check.AnchorPoint = Vector2.new(1, 0)
		check.Position = UDim2.new(1, -3, 0, 3)
		check.Size = UDim2.fromOffset(15, 15)
		check.BackgroundColor3 = ThemeUtil.Accent.green
		check.BackgroundTransparency = 0
		check.TextColor3 = ThemeUtil.Ink.onGreen
		check.FontFace = ThemeUtil.Font.heavy
		setText(check, Em.badge, config.root)
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.Text = "✓"
		check.Visible = false
		ThemeUtil.pill(check)
	end

	return cell
end

--- Applies §05's ring rules to a cell: rarity colour always, 3px when selected and 2px
--- (dimmed) when not. Primordial's ring cycles, so its tween is owned here and stopped
--- as soon as the cell stops being prismatic.
---
--- `colorOverride` is for entries that have no rarity at all — Materials carry their own
--- identity colour instead, and without this the selection ring would repaint them with
--- the default tier's white.
function PanelUtil.setCellRing(cell: GuiObject, rarity: string?, selected: boolean, colorOverride: Color3?)
	local stroke = ThemeUtil.ring(cell, colorOverride or ThemeUtil.rarityColor(rarity), selected and 3 or 2)
	stroke.Transparency = selected and 0 or 0.53
	local cardSurface = selected and Surface.cellSelected or Surface.cell
	cell.BackgroundColor3 = cardSurface.color
	cell.BackgroundTransparency = cardSurface.transparency

	local existing = cell:FindFirstChild("RingCycle")
	if not ThemeUtil.isPrismatic(rarity) then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end

	-- A marker child doubles as the loop's lifetime: destroying it ends the cycle, so a
	-- recycled cell never leaves a tween running.
	local marker = Instance.new("BoolValue")
	marker.Name = "RingCycle"
	marker.Parent = cell

	task.spawn(function()
		local cycle = ThemeUtil.PrimordialCycle
		local index = 1
		while marker.Parent do
			index = index % #cycle + 1
			local goal = cycle[index]
			local steps = 24
			local from = stroke.Color
			for step = 1, steps do
				if not marker.Parent then
					return
				end
				stroke.Color = from:Lerp(goal, step / steps)
				task.wait(0.8 / steps)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 06 · Details pane
--------------------------------------------------------------------------------

export type DetailsConfig = {
	parent: Frame,
	root: number,
	accent: Color3?,
	-- How many hero stats sit under the art (big value over small label).
	stats: number?,
	-- Adds the level + XP progress row above the footer.
	progress: boolean?,
	-- Adds the [ i ] button to the hero frame, which opens the lore modal.
	info: boolean?,
	-- Adds a footer with a wide primary button.
	primary: string?,
	-- Adds the square secondary beside it.
	secondaryIcon: string?,
	secondaryTint: Color3?,
}

export type Details = {
	Root: Frame,
	Hero: Frame,
	Art: ImageLabel,
	NameLabel: TextLabel,
	ElementIcon: ImageLabel,
	RarityLabel: TextLabel,
	InfoButton: TextButton?,
	Stats: { { Value: TextLabel, Label: TextLabel } },
	ProgressLabel: TextLabel?,
	ProgressDetail: TextLabel?,
	ProgressFill: Frame?,
	PrimaryButton: TextButton?,
	SecondaryButton: ImageButton?,
	Footer: Frame?,
}

--- The showcase column of §06: a 16:9 hero frame with name and element overlaid, an
--- [ i ] button for lore, rarity bottom-left and a rarity ring; then hero stats,
--- progress, and the footer buttons. Every menu's detail pane is this anatomy.
function PanelUtil.details(config: DetailsConfig): Details
	local root = config.root
	local accent = config.accent or ThemeUtil.Accent.gold
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local column = config.parent
	local layout = newList(column, Enum.FillDirection.Vertical, 10)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Hero: 16:9, capped so the art never crowds out the stats on a short screen.
	local hero = newFrame("Hero", column)
	hero.Size = UDim2.new(1, 0, 0, math.min(math.floor(ThemeUtil.detailWidth(viewport) * 9 / 16), ThemeUtil.artMaxHeight(viewport)))
	hero.ClipsDescendants = true

	-- On a short screen the column cannot fit hero + stats + progress + footer at their
	-- natural heights, and without this the surplus spills past the card, which clips it --
	-- taking the footer button with it. The hero is the only part with slack, so it is the
	-- one allowed to give ground; everything below it stays at its designed size.
	local heroFlex = Instance.new("UIFlexItem")
	heroFlex.FlexMode = Enum.UIFlexMode.Shrink
	heroFlex.Parent = hero
	hero.LayoutOrder = 1
	ThemeUtil.corner(hero, Radius.hero)
	hero.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hero.BackgroundTransparency = 0.9

	local heroWash = Instance.new("UIGradient")
	heroWash.Rotation = 90
	heroWash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.88),
		NumberSequenceKeypoint.new(0.4, 0.94),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	heroWash.Parent = hero

	-- The doc's art is a transparent glyph floating at 42% width. This game's thumbnails are
	-- photographs with an opaque background baked in, so at 42% they read as a small pasted
	-- rectangle stranded in a wide dark frame. Filling the frame's height and rounding the
	-- corners instead makes that backing look like a deliberate portrait tile.
	--
	-- The source art is square and the frame is roughly 2:1, so it can never fill the width
	-- without cropping the creature's head and feet -- height is the honest axis to fill.
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1, 0.88)
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = hero
	-- The box is forced square so it matches the artwork's own aspect. Without this, Fit
	-- letterboxes a square image inside a wider box and the rounded corners land on the
	-- empty box edges instead of the image, leaving the picture's own corners sharp.
	-- Non-square art still degrades gracefully: it just letterboxes inside the square.
	local artRatio = Instance.new("UIAspectRatioConstraint")
	artRatio.AspectRatio = 1
	artRatio.DominantAxis = Enum.DominantAxis.Height
	artRatio.Parent = art
	ThemeUtil.corner(art, Radius.cell)

	-- The top/bottom scrim that keeps the overlaid name and rarity legible over any art.
	--
	-- Darker and deeper than the doc's, which fades out by 32%. The doc can afford that
	-- because its art is a glyph on a dark wash; over a bright photo background the name row
	-- (7%-25% of the height) landed on almost undarkened cream. The dark band now covers the
	-- name row before it fades.
	local veil = newFrame("Veil", hero)
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	veil.BackgroundTransparency = 0
	veil.ZIndex = 2
	-- Must be rounded to match the hero. ClipsDescendants on the hero clips to its
	-- rectangle, not to its corner radius, so a square opaque child fills the rounded
	-- corners back in -- and this child is at its most opaque exactly at the top and bottom
	-- edges, which is where those corners are.
	ThemeUtil.corner(veil, Radius.hero)
	local veilGradient = Instance.new("UIGradient")
	veilGradient.Rotation = 90
	veilGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.28, 0.42),
		NumberSequenceKeypoint.new(0.46, 1),
		NumberSequenceKeypoint.new(0.64, 1),
		NumberSequenceKeypoint.new(1, 0.18),
	})
	veilGradient.Parent = veil

	local nameRow = newFrame("NameRow", hero)
	nameRow.Position = UDim2.new(0, 11, 0, 9)
	nameRow.Size = UDim2.new(1, -55, 0, 24)
	nameRow.ZIndex = 3
	newList(nameRow, Enum.FillDirection.Horizontal, 7)

	local elementIcon = Instance.new("ImageLabel")
	elementIcon.Name = "ElementIcon"
	elementIcon.Size = UDim2.fromOffset(24, 24)
	elementIcon.BackgroundColor3 = accent
	elementIcon.BackgroundTransparency = 0
	elementIcon.BorderSizePixel = 0
	-- The design draws a dark glyph on a bright disc. This game's icons are full-colour
	-- artwork rather than glyphs, so they are left untinted; the disc behind still carries
	-- the identity colour the design asks the element mark to communicate.
	elementIcon.ScaleType = Enum.ScaleType.Fit
	elementIcon.LayoutOrder = 1
	elementIcon.Parent = nameRow
	ThemeUtil.pill(elementIcon)
	ThemeUtil.padding(elementIcon, 5, 5, 5, 5)

	local nameLabel = newLabel("NameLabel", nameRow)
	nameLabel.Size = UDim2.new(1, -31, 1, 0)
	setText(nameLabel, Em.itemName, root)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameLabel.LayoutOrder = 2
	local nameShadow = Instance.new("UIStroke")
	nameShadow.Color = Color3.fromRGB(0, 0, 0)
	-- Near-opaque: this text is overlaid on artwork whose brightness is unknown, so the
	-- outline is what guarantees it stays readable rather than the veil behind it.
	nameShadow.Thickness = 2
	nameShadow.Transparency = 0.15
	nameShadow.Parent = nameLabel

	local infoButton: TextButton? = nil
	if config.info then
		local button = Instance.new("TextButton")
		button.Name = "InfoButton"
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -9, 0, 9)
		button.Size = UDim2.fromOffset(Metric.infoSize, Metric.infoSize)
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
		button.BackgroundTransparency = 0.5
		button.Text = "i"
		button.FontFace = ThemeUtil.Font.heavy
		setText(button, Em.caption, root)
		button.TextColor3 = ThemeUtil.Text.strong
		button.ZIndex = 3
		button.Parent = hero
		ThemeUtil.pill(button)
		ThemeUtil.ring(button, Color3.fromRGB(255, 255, 255), 1.5).Transparency = 0.25
		infoButton = button
	end

	local rarityLabel = newLabel("RarityLabel", hero)
	rarityLabel.AnchorPoint = Vector2.new(0, 1)
	rarityLabel.Position = UDim2.new(0, 12, 1, -8)
	rarityLabel.AutomaticSize = Enum.AutomaticSize.X
	rarityLabel.Size = UDim2.fromOffset(0, 16)
	rarityLabel.FontFace = ThemeUtil.Font.heavy
	setText(rarityLabel, Em.caption, root)
	rarityLabel.TextColor3 = accent
	rarityLabel.ZIndex = 3
	rarityLabel.Text = ""
	local rarityShadow = Instance.new("UIStroke")
	rarityShadow.Color = Color3.fromRGB(0, 0, 0)
	rarityShadow.Thickness = 2
	rarityShadow.Transparency = 0.15
	rarityShadow.Parent = rarityLabel

	ThemeUtil.ring(hero, accent, 3)

	-- Hero stats: big value over a small label, evenly split.
	local stats = {}
	if config.stats and config.stats > 0 then
		local statRow = newFrame("Stats", column)
		statRow.Size = UDim2.new(1, 0, 0, 40)
		statRow.LayoutOrder = 2
		-- The stat block owns the flexible middle of the details column. Its slots center
		-- their contents, placing the text halfway between hero art and footer/progress on
		-- every viewport instead of pinning it directly beneath the art.
		flexFill(statRow)
		local statLayout = newList(statRow, Enum.FillDirection.Horizontal, 6)
		statLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		for index = 1, config.stats do
			local slot = newFrame("Stat" .. index, statRow)
			slot.Size = UDim2.new(1 / config.stats, 0, 1, 0)
			slot.LayoutOrder = index
			flexFill(slot)
			local slotLayout = newList(slot, Enum.FillDirection.Vertical, 3)
			slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center

			local value = newLabel("Value", slot)
			value.Size = UDim2.new(1, 0, 0, math.ceil(ThemeUtil.text(Em.statValue, root)))
			value.FontFace = ThemeUtil.Font.heavy
			setText(value, Em.statValue, root)
			value:SetAttribute("TextHeightPadding", 0)
			value.TextXAlignment = Enum.TextXAlignment.Center
			value.TextTruncate = Enum.TextTruncate.AtEnd
			value.Text = "—"
			value.LayoutOrder = 1

			local label = newLabel("Label", slot)
			label.Size = UDim2.new(1, 0, 0, math.ceil(ThemeUtil.text(Em.statLabel, root)) + 2)
			label.FontFace = ThemeUtil.Font.bold
			setText(label, Em.statLabel, root)
			label:SetAttribute("TextHeightPadding", 2)
			label.TextColor3 = ThemeUtil.Text.muted
			label.TextTransparency = ThemeUtil.Text.mutedTransparency
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.Text = ""
			label.LayoutOrder = 2

			table.insert(stats, { Value = value, Label = label })
		end
	end

	-- Push the footer to the bottom of the column, the way `margin-top: auto` does.
	local spacer = newFrame("Spacer", column)
	spacer.Size = UDim2.new(1, 0, 0, 0)
	spacer.LayoutOrder = 3
	if not config.stats or config.stats <= 0 then
		flexFill(spacer)
	end

	local progressLabel: TextLabel? = nil
	local progressDetail: TextLabel? = nil
	local progressFill: Frame? = nil
	if config.progress then
		local block = newFrame("Progress", column)
		block.Size = UDim2.new(1, 0, 0, 24)
		block.LayoutOrder = 4
		local blockLayout = newList(block, Enum.FillDirection.Vertical, 4)
		blockLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

		local row = newFrame("Row", block)
		row.Size = UDim2.new(1, 0, 0, 13)
		row.LayoutOrder = 1

		progressLabel = newLabel("Label", row)
		;(progressLabel :: TextLabel).Size = UDim2.new(0.5, 0, 1, 0)
		setText(progressLabel :: TextLabel, Em.caption, root)
		;(progressLabel :: TextLabel).Text = ""

		progressDetail = newLabel("Detail", row)
		;(progressDetail :: TextLabel).AnchorPoint = Vector2.new(1, 0)
		;(progressDetail :: TextLabel).Position = UDim2.fromScale(1, 0)
		;(progressDetail :: TextLabel).Size = UDim2.new(0.5, 0, 1, 0)
		;(progressDetail :: TextLabel).FontFace = ThemeUtil.Font.bold
		setText(progressDetail :: TextLabel, Em.statLabel, root)
		;(progressDetail :: TextLabel).TextColor3 = ThemeUtil.Text.muted
		;(progressDetail :: TextLabel).TextTransparency = ThemeUtil.Text.mutedTransparency
		;(progressDetail :: TextLabel).TextXAlignment = Enum.TextXAlignment.Right
		;(progressDetail :: TextLabel).Text = ""

		local trough = newFrame("Trough", block)
		trough.Size = UDim2.new(1, 0, 0, Metric.barHeight)
		trough.ClipsDescendants = true
		trough.LayoutOrder = 2
		ThemeUtil.paint(trough, Surface.trough)
		ThemeUtil.pill(trough)

		progressFill = newFrame("Fill", trough)
		;(progressFill :: Frame).Size = UDim2.fromScale(0, 1)
		;(progressFill :: Frame).BackgroundColor3 = accent
		;(progressFill :: Frame).BackgroundTransparency = 0
		ThemeUtil.pill(progressFill :: Frame)
	end

	local footer: Frame? = nil
	local primaryButton: TextButton? = nil
	local secondaryButton: ImageButton? = nil
	if config.primary or config.secondaryIcon then
		footer = newFrame("Footer", column)
		;(footer :: Frame).Size = UDim2.new(1, 0, 0, Metric.buttonHeight)
		;(footer :: Frame).LayoutOrder = 5
		local footerLayout = newList(footer :: Frame, Enum.FillDirection.Horizontal, 8)
		footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		if config.primary then
			primaryButton = PanelUtil.primaryButton(footer :: Frame, config.primary, root, accent)
			;(primaryButton :: TextButton).LayoutOrder = 1
			flexFill(primaryButton :: TextButton)
		end
		if config.secondaryIcon then
			secondaryButton = PanelUtil.squareButton(footer :: Frame, config.secondaryIcon, config.secondaryTint or accent)
			;(secondaryButton :: ImageButton).LayoutOrder = 2
		end
	end

	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local size = camera.ViewportSize
			hero.Size = UDim2.new(1, 0, 0, math.min(math.floor(ThemeUtil.detailWidth(size) * 9 / 16), ThemeUtil.artMaxHeight(size)))
		end)
	end

	return {
		Root = column,
		Hero = hero,
		Art = art,
		NameLabel = nameLabel,
		ElementIcon = elementIcon,
		RarityLabel = rarityLabel,
		InfoButton = infoButton,
		Stats = stats,
		ProgressLabel = progressLabel,
		ProgressDetail = progressDetail,
		ProgressFill = progressFill,
		PrimaryButton = primaryButton,
		SecondaryButton = secondaryButton,
		Footer = footer,
	}
end

--- Paints the hero frame for a rarity: ring, rarity caption, and the prismatic cycle for
--- Primordial. Mirrors `setCellRing` so a cell and its detail pane never disagree.
function PanelUtil.setHeroRarity(details: Details, rarity: string?)
	local color = ThemeUtil.rarityColor(rarity)
	local stroke = ThemeUtil.ring(details.Hero, color, 3)
	-- The caption always shows the design's tier name, whatever vocabulary the caller has.
	details.RarityLabel.Text = rarity and ThemeUtil.tier(rarity) or ""
	details.RarityLabel.TextColor3 = color

	local existing = details.Hero:FindFirstChild("RingCycle")
	if not ThemeUtil.isPrismatic(rarity) then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end

	local marker = Instance.new("BoolValue")
	marker.Name = "RingCycle"
	marker.Parent = details.Hero

	task.spawn(function()
		local cycle = ThemeUtil.PrimordialCycle
		local index = 1
		while marker.Parent do
			index = index % #cycle + 1
			local goal = cycle[index]
			local from = stroke.Color
			for step = 1, 24 do
				if not marker.Parent then
					return
				end
				local blended = from:Lerp(goal, step / 24)
				stroke.Color = blended
				details.RarityLabel.TextColor3 = blended
				task.wait(0.8 / 24)
			end
		end
	end)
end

--- Sets a progress bar from a 0-1 fraction.
function PanelUtil.setProgress(details: Details, fraction: number, fillColor: Color3?)
	local fill = details.ProgressFill
	if not fill then
		return
	end
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if fillColor then
		fill.BackgroundColor3 = fillColor
	end
end

--------------------------------------------------------------------------------
-- 08 · Modal
--------------------------------------------------------------------------------

export type ModalConfig = {
	parent: Instance,
	root: number,
	-- Instance name. Worth setting when a panel owns more than one modal, so the tree
	-- reads as LoreModal/ConfirmModal rather than two children both called "Modal".
	name: string?,
	title: string?,
	-- Adds the rarity · source subtitle row.
	subtitle: boolean?,
	-- Adds the italic lore paragraph.
	body: boolean?,
	-- Confirm/cancel buttons along the bottom.
	confirm: string?,
	cancel: string?,
	confirmTint: Color3?,
	accent: Color3?,
}

export type Modal = {
	Root: Frame,
	Card: Frame,
	TitleLabel: TextLabel,
	IconDisc: ImageLabel,
	SubtitleLabel: TextLabel?,
	BodyLabel: TextLabel?,
	CloseButton: TextButton,
	ConfirmButton: TextButton?,
	CancelButton: TextButton?,
	Open: (Modal) -> (),
	Close: (Modal) -> (),
}

--- The lore/confirm modal of §08: its own scrim over the panel, a near-opaque card with a
--- hairline border, an identity row, and optional lore or confirm buttons. Lore lives
--- here and nowhere else — the doc is explicit that flavour text is never inline.
function PanelUtil.modal(config: ModalConfig): Modal
	local root = config.root
	local accent = config.accent or ThemeUtil.Accent.gold

	local scrim = newFrame(config.name or "Modal", config.parent)
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = 10
	ThemeUtil.paint(scrim, Surface.modalScrim)

	-- Swallows clicks so the panel behind the modal cannot be used.
	local blocker = Instance.new("TextButton")
	blocker.Name = "Blocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.Parent = scrim

	local card = newFrame("Card", scrim)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(380, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.ZIndex = 11
	ThemeUtil.paint(card, Surface.modal)
	ThemeUtil.corner(card, Radius.modal)
	ThemeUtil.ring(card, Color3.fromRGB(255, 255, 255), 1).Transparency = 0.91
	ThemeUtil.padding(card, 20, 20, 20, 20)
	local cardLayout = newList(card, Enum.FillDirection.Vertical, 12)
	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local titleRow = newFrame("TitleRow", card)
	titleRow.Size = UDim2.new(1, 0, 0, Metric.closeSize)
	titleRow.LayoutOrder = 1

	local identity = newFrame("Identity", titleRow)
	identity.Size = UDim2.new(1, -40, 1, 0)
	newList(identity, Enum.FillDirection.Horizontal, 9)

	local disc = Instance.new("ImageLabel")
	disc.Name = "IconDisc"
	disc.Size = UDim2.fromOffset(28, 28)
	disc.BackgroundColor3 = accent
	disc.BackgroundTransparency = 0
	disc.BorderSizePixel = 0
	-- Untinted for the same reason as the details pane's element disc.
	disc.ScaleType = Enum.ScaleType.Fit
	disc.LayoutOrder = 1
	disc.Parent = identity
	ThemeUtil.pill(disc)
	ThemeUtil.padding(disc, 6, 6, 6, 6)

	local titleLabel = newLabel("Title", identity)
	titleLabel.Size = UDim2.new(1, -37, 1, 0)
	setText(titleLabel, Em.itemName, root)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Text = config.title or ""
	titleLabel.LayoutOrder = 2

	local closeButton = PanelUtil.closeButton(titleRow, root)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.fromScale(1, 0.5)

	local subtitleLabel: TextLabel? = nil
	if config.subtitle then
		subtitleLabel = newLabel("Subtitle", card)
		;(subtitleLabel :: TextLabel).Size = UDim2.new(1, 0, 0, 16)
		setText(subtitleLabel :: TextLabel, Em.sectionLabel, root)
		;(subtitleLabel :: TextLabel).TextColor3 = accent
		;(subtitleLabel :: TextLabel).Text = ""
		;(subtitleLabel :: TextLabel).LayoutOrder = 2

		local divider = newFrame("Divider", card)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.LayoutOrder = 3
		ThemeUtil.paint(divider, Surface.divider)
	end

	local bodyLabel: TextLabel? = nil
	if config.body then
		bodyLabel = newLabel("Body", card)
		;(bodyLabel :: TextLabel).Size = UDim2.new(1, 0, 0, 0)
		;(bodyLabel :: TextLabel).AutomaticSize = Enum.AutomaticSize.Y
		;(bodyLabel :: TextLabel).FontFace = Font.fromName("Nunito", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
		setText(bodyLabel :: TextLabel, Em.body, root)
		;(bodyLabel :: TextLabel).TextColor3 = ThemeUtil.Text.body
		;(bodyLabel :: TextLabel).TextTransparency = 0.15
		;(bodyLabel :: TextLabel).TextWrapped = true
		;(bodyLabel :: TextLabel).TextYAlignment = Enum.TextYAlignment.Top
		;(bodyLabel :: TextLabel).LineHeight = 1.35
		;(bodyLabel :: TextLabel).Text = ""
		;(bodyLabel :: TextLabel).LayoutOrder = 4
	end

	local confirmButton: TextButton? = nil
	local cancelButton: TextButton? = nil
	if config.confirm or config.cancel then
		local actions = newFrame("Actions", card)
		actions.Size = UDim2.new(1, 0, 0, Metric.buttonHeight)
		actions.LayoutOrder = 5
		local actionLayout = newList(actions, Enum.FillDirection.Horizontal, 8)
		actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		if config.cancel then
			cancelButton = PanelUtil.primaryButton(actions, config.cancel, root, ThemeUtil.Accent.gold)
			;(cancelButton :: TextButton).Name = "CancelButton"
			;(cancelButton :: TextButton).LayoutOrder = 1
			flexFill(cancelButton :: TextButton)
			-- Cancel is the quiet half of the pair: chip fill, plain white label.
			ThemeUtil.paint(cancelButton :: TextButton, Surface.chipStrong)
			;(cancelButton :: TextButton).TextColor3 = ThemeUtil.Text.strong
		end
		if config.confirm then
			confirmButton = PanelUtil.primaryButton(actions, config.confirm, root, config.confirmTint or ThemeUtil.Accent.red)
			;(confirmButton :: TextButton).Name = "ConfirmButton"
			;(confirmButton :: TextButton).LayoutOrder = 2
			flexFill(confirmButton :: TextButton)
		end
	end

	local modal: Modal
	modal = {
		Root = scrim,
		Card = card,
		TitleLabel = titleLabel,
		IconDisc = disc,
		SubtitleLabel = subtitleLabel,
		BodyLabel = bodyLabel,
		CloseButton = closeButton,
		ConfirmButton = confirmButton,
		CancelButton = cancelButton,
		Open = function()
			scrim.Visible = true
		end,
		Close = function()
			scrim.Visible = false
		end,
	}

	closeButton.Activated:Connect(function()
		scrim.Visible = false
	end)
	blocker.Activated:Connect(function()
		scrim.Visible = false
	end)

	-- A modal is a sibling of the panel card, not a descendant, so it needs its own pass
	-- when the device root changes.
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			PanelUtil.rescaleText(card, ThemeUtil.root(camera.ViewportSize))
		end)
	end

	return modal
end

--------------------------------------------------------------------------------
-- 07 · Roblox proximity buttons
--------------------------------------------------------------------------------

--- A world-space action button: 56px dark disc, accent-ringed, with a pill caption under
--- it. Used for the shrine/craft/collect cluster in the HUD design.
function PanelUtil.proximityButton(parent: Instance, icon: string, caption: string, tint: Color3, root: number): (Frame, ImageButton)
	local group = newFrame("Proximity" .. caption, parent)
	group.Size = UDim2.fromOffset(Metric.proximitySize, Metric.proximitySize + 18)
	local groupLayout = newList(group, Enum.FillDirection.Vertical, 3)
	groupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	groupLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local button = Instance.new("ImageButton")
	button.Name = "Button"
	button.Size = UDim2.fromOffset(Metric.proximitySize, Metric.proximitySize)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	button.BackgroundTransparency = 0.38
	button.Image = icon
	button.ImageColor3 = tint
	button.ScaleType = Enum.ScaleType.Fit
	button.LayoutOrder = 1
	button.Parent = group
	ThemeUtil.pill(button)
	ThemeUtil.padding(button, 13, 13, 13, 13)
	ThemeUtil.ring(button, tint, 2).Transparency = 0.45

	local label = newLabel("Caption", group)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 15)
	setText(label, Em.statLabel, root)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = caption
	label.LayoutOrder = 2
	ThemeUtil.paint(label, Surface.badge)
	ThemeUtil.pill(label)
	ThemeUtil.padding(label, 0, 7, 0, 7)

	return group, button
end

return PanelUtil
