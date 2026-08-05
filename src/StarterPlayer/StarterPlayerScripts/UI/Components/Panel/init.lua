-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel
-- The panel shell and its parts, as described by §03-§08 of the design system.
--
-- The design doc's own instruction is to build every menu by composing one shell rather
-- than laying each menu out by hand: scrim over the world, a centered card, a header row
-- (identity left · tabs center · actions right), and a body split grid 2/3 · details 1/3.
-- This module is that shell. A controller says what goes in it, never where it goes.
--
--   local panel = Panel.Create({
--       parent = screenGui,
--       title = "Inventory",
--       titleIcon = "rbxassetid://...",
--       tabs = { "Mythlings", "Materials" },
--       coins = true,
--       onClose = function() ... end,
--   })
--   local details = Panel.CreateDetails(panel.Details, { stats = 3, progress = true })
--
-- The scrim is deliberately absent: the application overlay owns the shared ModalBackdropGui
-- ScreenGui, so a panel that drew its own would double-darken the world.

local Theme = require(script.Parent.Parent.Theme)
local Controls = require(script.Controls)
local Primitives = require(script.Primitives)

local Panel = {}

local Metric = Theme.Metric
local Radius = Theme.Radius
local Surface = Theme.Surface
local Em = Theme.Em

local newFrame = Primitives.NewFrame
local newLabel = Primitives.NewLabel
local newList = Primitives.NewList
local flexFill = Primitives.FlexFill
local setText = Primitives.SetText

Panel.RescaleText = Primitives.RescaleText
Panel.Tab = Controls.Tab
Panel.SetTabActive = Controls.SetTabActive
Panel.PrimaryButton = Controls.PrimaryButton
Panel.SetButtonEnabled = Controls.SetButtonEnabled
Panel.SquareButton = Controls.SquareButton
Panel.SquareTextButton = Controls.SquareTextButton
Panel.CloseButton = Controls.CloseButton
Panel.CoinPill = Controls.CoinPill
Panel.LevelPill = Controls.LevelPill

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
function Panel.Create(config: PanelConfig): Panel
	local accent = config.accent or Theme.Accent.gold
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local root = Theme.root(viewport)

	-- Every application panel uses Roblox's live safe canvas. This avoids timing-sensitive
	-- manual inset measurements while keeping controls clear of CoreGui and device notches.
	local screenGui = config.parent:IsA("ScreenGui") and config.parent
		or config.parent:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui then
		Theme.useSafeCanvas(screenGui)
	end

	local function resolveCardSize(size: Vector2): UDim2
		return config.size and config.size(size) or Theme.panelSize(size)
	end

	local card = newFrame("Card", config.parent)
	local anchor, position = Theme.panelPlacement(viewport)
	card.AnchorPoint = anchor
	card.Position = position
	card.Size = resolveCardSize(viewport)
	card.ClipsDescendants = true
	Theme.paint(card, Surface.panel)
	Theme.corner(card, Radius.card)

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
	Theme.padding(header, Metric.headerPadTop, Metric.headerPadRight, Metric.headerPadBottom, Metric.headerPadLeft)

	local identity = newFrame("Identity", header)
	identity.AnchorPoint = Vector2.new(0, 0.5)
	identity.Position = UDim2.fromScale(0, 0.5)
	identity.Size = UDim2.fromScale(0, 1)
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
			Theme.pill(icon)
			Theme.padding(icon, 7, 7, 7, 7)
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
	titleLabel.Size = UDim2.fromScale(0, 1)
	setText(titleLabel, Em.panelTitle, root)
	titleLabel.Text = config.title
	titleLabel.LayoutOrder = 2

	local tabs: { [string]: TextButton } = {}
	if config.tabs then
		local tabRow = newFrame("Tabs", header)
		tabRow.AnchorPoint = Vector2.new(0.5, 0.5)
		tabRow.Position = UDim2.fromScale(0.5, 0.5)
		tabRow.Size = UDim2.fromScale(0, 1)
		tabRow.AutomaticSize = Enum.AutomaticSize.X
		local row = newList(tabRow, Enum.FillDirection.Horizontal, Metric.tabGap)
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for index, name in ipairs(config.tabs) do
			local tab = Panel.Tab(tabRow, name, accent, root)
			tab.LayoutOrder = index
			tabs[name] = tab
		end
	end

	local actions = newFrame("Actions", header)
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.Position = UDim2.fromScale(1, 0.5)
	actions.Size = UDim2.fromScale(0, 1)
	actions.AutomaticSize = Enum.AutomaticSize.X
	newList(actions, Enum.FillDirection.Horizontal, 10)

	local coinLabel: TextLabel? = nil
	if config.coins then
		local pill, label = Panel.CoinPill(actions, config.coinIcon or "", root)
		pill.LayoutOrder = 1
		coinLabel = label
	end

	local levelLabel: TextLabel? = nil
	if config.levelPill then
		levelLabel = Panel.LevelPill(actions, root, accent);
		(levelLabel :: TextLabel).LayoutOrder = 2
	end

	local closeButton = Panel.CloseButton(actions, root)
	closeButton.LayoutOrder = 3

	-- Body: grid 2fr · details 1fr · gap 14, at every size.
	local body = newFrame("Body", card)
	body.Size = UDim2.fromScale(1, 1)
	body.LayoutOrder = 2
	flexFill(body)
	Theme.padding(body, Metric.bodyPadTop, Metric.bodyPad, Metric.bodyPad, Metric.bodyPad)
	local bodyLayout = newList(body, Enum.FillDirection.Horizontal, Metric.bodyGap)
	bodyLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local grid = newFrame("Grid", body)
	grid.Size = UDim2.fromScale(1, 1)
	grid.LayoutOrder = 1
	flexFill(grid)

	local details = newFrame("Details", body)
	details.Size = UDim2.new(0, Theme.detailWidth(viewport), 1, 0)
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
			card.AnchorPoint, card.Position = Theme.panelPlacement(size)
			details.Size = UDim2.new(0, Theme.detailWidth(size), 1, 0)
			Panel.RescaleText(card, Theme.root(size))
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
	local panelWidth = if Theme.isPhone(viewport) then viewport.X else Theme.panelSize(viewport).X.Offset
	return panelWidth - 2 * Metric.bodyPad - Metric.bodyGap - Theme.detailWidth(viewport)
end

--- The scrolling grid that fills the panel's 2/3 column. Cells are the design's fixed
--- 112px squares; phones fall back to four equal columns, as the canvas does.
function Panel.CreateGrid(parent: Instance): ScrollingFrame
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
	Theme.padding(scroll, RING_BLEED, scroll.ScrollBarThickness + RING_BLEED, RING_BLEED, RING_BLEED)

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

--- The cell template CardList clones: a square, faint fill, the artwork inset inside
--- the rarity ring, and overlay badges created up front and left invisible so a clone only
--- has to toggle them.
---
--- The doc floats a transparent glyph at 52% of the cell. This game's thumbnails carry an
--- opaque background, and at 52% each one read as a hard-edged square stranded inside a
--- rounded cell -- worse still, the backing colour differs per creature, so a grid of them
--- looked like mismatched stickers. Filling the cell and matching the corner radius turns
--- that backing into the tile itself.
function Panel.CreateCellTemplate(config: CellConfig): ImageButton
	local cell = Instance.new("ImageButton")
	cell.Name = "CardTemplate"
	cell.Size = UDim2.fromOffset(Metric.cellSize, Metric.cellSize)
	cell.AutoButtonColor = false
	cell.BorderSizePixel = 0
	cell.Image = ""
	cell.Visible = false
	cell.ClipsDescendants = false
	cell.Parent = config.parent
	Theme.paint(cell, Surface.cell)
	Theme.corner(cell, Radius.cell)
	Theme.ring(cell, Theme.Rarity.Fabled, 2)

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

	-- Kept named 2dPreview: every controller and CardList decorator already sets
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
	Theme.corner(preview, Radius.cell - 3)

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
		Theme.paint(badge, Surface.badge)
		Theme.corner(badge, Radius.badge)
		Theme.padding(badge, 0, 6, 0, 6)
	end

	if config.quantity then
		local badge = newLabel("QuantityLabel", cell)
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, -3, 1, -3)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 15)
		setText(badge, Em.badge, config.root)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.TextColor3 = Theme.Text.coin
		badge.Text = ""
		Theme.paint(badge, Surface.badge)
		Theme.corner(badge, Radius.badge)
		Theme.padding(badge, 0, 6, 0, 6)
	end

	if config.check then
		local check = newLabel("EquippedCheck", cell)
		check.AnchorPoint = Vector2.new(1, 0)
		check.Position = UDim2.new(1, -3, 0, 3)
		check.Size = UDim2.fromOffset(15, 15)
		check.BackgroundColor3 = Theme.Accent.green
		check.BackgroundTransparency = 0
		check.TextColor3 = Theme.Ink.onGreen
		check.FontFace = Theme.Font.heavy
		setText(check, Em.badge, config.root)
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.Text = "✓"
		check.Visible = false
		Theme.pill(check)
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
function Panel.SetCellRing(cell: GuiObject, rarity: string?, selected: boolean, colorOverride: Color3?)
	local stroke = Theme.ring(cell, colorOverride or Theme.rarityColor(rarity), selected and 3 or 2)
	stroke.Transparency = selected and 0 or 0.53
	local cardSurface = selected and Surface.cellSelected or Surface.cell
	cell.BackgroundColor3 = cardSurface.color
	cell.BackgroundTransparency = cardSurface.transparency

	local existing = cell:FindFirstChild("RingCycle")
	if not Theme.isPrismatic(rarity) then
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
		local cycle = Theme.PrimordialCycle
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
function Panel.CreateDetails(config: DetailsConfig): Details
	local root = config.root
	local accent = config.accent or Theme.Accent.gold
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local column = config.parent
	local layout = newList(column, Enum.FillDirection.Vertical, 10)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Hero: 16:9, capped so the art never crowds out the stats on a short screen.
	local hero = newFrame("Hero", column)
	hero.Size =
		UDim2.new(1, 0, 0, math.min(math.floor(Theme.detailWidth(viewport) * 9 / 16), Theme.artMaxHeight(viewport)))
	hero.ClipsDescendants = true

	-- On a short screen the column cannot fit hero + stats + progress + footer at their
	-- natural heights, and without this the surplus spills past the card, which clips it --
	-- taking the footer button with it. The hero is the only part with slack, so it is the
	-- one allowed to give ground; everything below it stays at its designed size.
	local heroFlex = Instance.new("UIFlexItem")
	heroFlex.FlexMode = Enum.UIFlexMode.Shrink
	heroFlex.Parent = hero
	hero.LayoutOrder = 1
	Theme.corner(hero, Radius.hero)
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
	Theme.corner(art, Radius.cell)

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
	Theme.corner(veil, Radius.hero)
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
	nameRow.Position = UDim2.fromOffset(11, 9)
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
	Theme.pill(elementIcon)
	Theme.padding(elementIcon, 5, 5, 5, 5)

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
		button.FontFace = Theme.Font.heavy
		setText(button, Em.caption, root)
		button.TextColor3 = Theme.Text.strong
		button.ZIndex = 3
		button.Parent = hero
		Theme.pill(button)
		Theme.ring(button, Color3.fromRGB(255, 255, 255), 1.5).Transparency = 0.25
		infoButton = button
	end

	local rarityLabel = newLabel("RarityLabel", hero)
	rarityLabel.AnchorPoint = Vector2.new(0, 1)
	rarityLabel.Position = UDim2.new(0, 12, 1, -8)
	rarityLabel.AutomaticSize = Enum.AutomaticSize.X
	rarityLabel.Size = UDim2.fromOffset(0, 16)
	rarityLabel.FontFace = Theme.Font.heavy
	setText(rarityLabel, Em.caption, root)
	rarityLabel.TextColor3 = accent
	rarityLabel.ZIndex = 3
	rarityLabel.Text = ""
	local rarityShadow = Instance.new("UIStroke")
	rarityShadow.Color = Color3.fromRGB(0, 0, 0)
	rarityShadow.Thickness = 2
	rarityShadow.Transparency = 0.15
	rarityShadow.Parent = rarityLabel

	Theme.ring(hero, accent, 3)

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
			slot.Size = UDim2.fromScale(1 / config.stats, 1)
			slot.LayoutOrder = index
			flexFill(slot)
			local slotLayout = newList(slot, Enum.FillDirection.Vertical, 3)
			slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center

			local value = newLabel("Value", slot)
			value.Size = UDim2.new(1, 0, 0, math.ceil(Theme.text(Em.statValue, root)))
			value.FontFace = Theme.Font.heavy
			setText(value, Em.statValue, root)
			value:SetAttribute("TextHeightPadding", 0)
			value.TextXAlignment = Enum.TextXAlignment.Center
			value.TextTruncate = Enum.TextTruncate.AtEnd
			value.Text = "—"
			value.LayoutOrder = 1

			local label = newLabel("Label", slot)
			label.Size = UDim2.new(1, 0, 0, math.ceil(Theme.text(Em.statLabel, root)) + 2)
			label.FontFace = Theme.Font.bold
			setText(label, Em.statLabel, root)
			label:SetAttribute("TextHeightPadding", 2)
			label.TextColor3 = Theme.Text.muted
			label.TextTransparency = Theme.Text.mutedTransparency
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.Text = ""
			label.LayoutOrder = 2

			table.insert(stats, { Value = value, Label = label })
		end
	end

	-- Push the footer to the bottom of the column, the way `margin-top: auto` does.
	local spacer = newFrame("Spacer", column)
	spacer.Size = UDim2.fromScale(1, 0)
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

		progressLabel = newLabel("Label", row);
		(progressLabel :: TextLabel).Size = UDim2.fromScale(0.5, 1)
		setText(progressLabel :: TextLabel, Em.caption, root);
		(progressLabel :: TextLabel).Text = ""

		progressDetail = newLabel("Detail", row);
		(progressDetail :: TextLabel).AnchorPoint = Vector2.new(1, 0);
		(progressDetail :: TextLabel).Position = UDim2.fromScale(1, 0);
		(progressDetail :: TextLabel).Size = UDim2.fromScale(0.5, 1);
		(progressDetail :: TextLabel).FontFace = Theme.Font.bold
		setText(progressDetail :: TextLabel, Em.statLabel, root);
		(progressDetail :: TextLabel).TextColor3 = Theme.Text.muted;
		(progressDetail :: TextLabel).TextTransparency = Theme.Text.mutedTransparency;
		(progressDetail :: TextLabel).TextXAlignment = Enum.TextXAlignment.Right;
		(progressDetail :: TextLabel).Text = ""

		local trough = newFrame("Trough", block)
		trough.Size = UDim2.new(1, 0, 0, Metric.barHeight)
		trough.ClipsDescendants = true
		trough.LayoutOrder = 2
		Theme.paint(trough, Surface.trough)
		Theme.pill(trough)

		progressFill = newFrame("Fill", trough);
		(progressFill :: Frame).Size = UDim2.fromScale(0, 1);
		(progressFill :: Frame).BackgroundColor3 = accent;
		(progressFill :: Frame).BackgroundTransparency = 0
		Theme.pill(progressFill :: Frame)
	end

	local footer: Frame? = nil
	local primaryButton: TextButton? = nil
	local secondaryButton: ImageButton? = nil
	if config.primary or config.secondaryIcon then
		footer = newFrame("Footer", column);
		(footer :: Frame).Size = UDim2.new(1, 0, 0, Metric.buttonHeight);
		(footer :: Frame).LayoutOrder = 5
		local footerLayout = newList(footer :: Frame, Enum.FillDirection.Horizontal, 8)
		footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		if config.primary then
			primaryButton = Panel.PrimaryButton(footer :: Frame, config.primary, root, accent);
			(primaryButton :: TextButton).LayoutOrder = 1
			flexFill(primaryButton :: TextButton)
		end
		if config.secondaryIcon then
			secondaryButton = Panel.SquareButton(footer :: Frame, config.secondaryIcon, config.secondaryTint or accent);
			(secondaryButton :: ImageButton).LayoutOrder = 2
		end
	end

	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local size = camera.ViewportSize
			hero.Size =
				UDim2.new(1, 0, 0, math.min(math.floor(Theme.detailWidth(size) * 9 / 16), Theme.artMaxHeight(size)))
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
function Panel.SetHeroRarity(details: Details, rarity: string?)
	local color = Theme.rarityColor(rarity)
	local stroke = Theme.ring(details.Hero, color, 3)
	-- The caption always shows the design's tier name, whatever vocabulary the caller has.
	details.RarityLabel.Text = rarity and Theme.tier(rarity) or ""
	details.RarityLabel.TextColor3 = color

	local existing = details.Hero:FindFirstChild("RingCycle")
	if not Theme.isPrismatic(rarity) then
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
		local cycle = Theme.PrimordialCycle
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
function Panel.SetProgress(details: Details, fraction: number, fillColor: Color3?)
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
function Panel.CreateModal(config: ModalConfig): Modal
	local root = config.root
	local accent = config.accent or Theme.Accent.gold

	local scrim = newFrame(config.name or "Modal", config.parent)
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = 10
	Theme.paint(scrim, Surface.modalScrim)

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
	Theme.paint(card, Surface.modal)
	Theme.corner(card, Radius.modal)
	Theme.ring(card, Color3.fromRGB(255, 255, 255), 1).Transparency = 0.91
	Theme.padding(card, 20, 20, 20, 20)
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
	Theme.pill(disc)
	Theme.padding(disc, 6, 6, 6, 6)

	local titleLabel = newLabel("Title", identity)
	titleLabel.Size = UDim2.new(1, -37, 1, 0)
	setText(titleLabel, Em.itemName, root)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Text = config.title or ""
	titleLabel.LayoutOrder = 2

	local closeButton = Panel.CloseButton(titleRow, root)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.fromScale(1, 0.5)

	local subtitleLabel: TextLabel? = nil
	if config.subtitle then
		subtitleLabel = newLabel("Subtitle", card);
		(subtitleLabel :: TextLabel).Size = UDim2.new(1, 0, 0, 16)
		setText(subtitleLabel :: TextLabel, Em.sectionLabel, root);
		(subtitleLabel :: TextLabel).TextColor3 = accent;
		(subtitleLabel :: TextLabel).Text = ""
		(subtitleLabel :: TextLabel).LayoutOrder = 2

		local divider = newFrame("Divider", card)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.LayoutOrder = 3
		Theme.paint(divider, Surface.divider)
	end

	local bodyLabel: TextLabel? = nil
	if config.body then
		bodyLabel = newLabel("Body", card);
		(bodyLabel :: TextLabel).Size = UDim2.fromScale(1, 0);
		(bodyLabel :: TextLabel).AutomaticSize = Enum.AutomaticSize.Y;
		(bodyLabel :: TextLabel).FontFace = Font.fromName("Nunito", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
		setText(bodyLabel :: TextLabel, Em.body, root);
		(bodyLabel :: TextLabel).TextColor3 = Theme.Text.body;
		(bodyLabel :: TextLabel).TextTransparency = 0.15
		(bodyLabel :: TextLabel).TextWrapped = true
		(bodyLabel :: TextLabel).TextYAlignment = Enum.TextYAlignment.Top;
		(bodyLabel :: TextLabel).LineHeight = 1.35
		(bodyLabel :: TextLabel).Text = ""
		(bodyLabel :: TextLabel).LayoutOrder = 4
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
			cancelButton = Panel.PrimaryButton(actions, config.cancel, root, Theme.Accent.gold);
			(cancelButton :: TextButton).Name = "CancelButton"
			(cancelButton :: TextButton).LayoutOrder = 1
			flexFill(cancelButton :: TextButton)
			-- Cancel is the quiet half of the pair: chip fill, plain white label.
			Theme.paint(cancelButton :: TextButton, Surface.chipStrong);
			(cancelButton :: TextButton).TextColor3 = Theme.Text.strong
		end
		if config.confirm then
			confirmButton = Panel.PrimaryButton(actions, config.confirm, root, config.confirmTint or Theme.Accent.red);
			(confirmButton :: TextButton).Name = "ConfirmButton"
			(confirmButton :: TextButton).LayoutOrder = 2
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
			Panel.RescaleText(card, Theme.root(camera.ViewportSize))
		end)
	end

	return modal
end

--------------------------------------------------------------------------------
-- 07 · Roblox proximity buttons
--------------------------------------------------------------------------------

--- A world-space action button: 56px dark disc, accent-ringed, with a pill caption under
--- it. Used for the shrine/craft/collect cluster in the HUD design.
function Panel.CreateProximityButton(
	parent: Instance,
	icon: string,
	caption: string,
	tint: Color3,
	root: number
): (Frame, ImageButton)
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
	Theme.pill(button)
	Theme.padding(button, 13, 13, 13, 13)
	Theme.ring(button, tint, 2).Transparency = 0.45

	local label = newLabel("Caption", group)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 15)
	setText(label, Em.statLabel, root)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = caption
	label.LayoutOrder = 2
	Theme.paint(label, Surface.badge)
	Theme.pill(label)
	Theme.padding(label, 0, 7, 0, 7)

	return group, button
end

return Panel
