--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Grid

local Theme = require(script.Parent.Parent.Parent.Theme)
local Primitives = require(script.Parent.Primitives)
local ViewportUtil = require(script.Parent.Parent.Parent.ViewportUtil)

local Grid = {}
local metric = Theme.metric
local radius = Theme.radius
local surfaces = Theme.surface
local em = Theme.em
local newLabel = Primitives.NewLabel
local setText = Primitives.SetText
local RING_BLEED = 4

--- Width the grid column ends up with, derived from the shell's own metrics rather than
--- measured: AbsoluteSize is still zero when a panel is built, one frame before layout.
local function gridColumnWidth(viewport: Vector2): number
	-- A phone panel is sized in scale against the full-screen canvas, so its offset is a
	-- negative inset correction rather than a width. Its pixel width is the safe band, which
	-- is what the camera viewport measures.
	local panelWidth = if Theme.IsPhone(viewport)
		then viewport.X
		else Theme.PanelSize(viewport).X.Offset
	return panelWidth - 2 * metric.bodyPad - metric.bodyGap - Theme.DetailWidth(viewport)
end

--- The scrolling grid that fills the panel's 2/3 column. Cells are the design's fixed
--- 112px squares; phones fall back to four equal columns, as the canvas does.
function Grid.CreateGrid(parent: Instance): ScrollingFrame
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
	Theme.Padding(
		scroll,
		RING_BLEED,
		scroll.ScrollBarThickness + RING_BLEED,
		RING_BLEED,
		RING_BLEED
	)

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(metric.cellGap, metric.cellGap)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	--- Phones get four equal columns; everything else gets the fixed 112px cell.
	local function applyCellSize(size: Vector2)
		if size.Y < 500 then
			local usable = gridColumnWidth(size) - scroll.ScrollBarThickness - 2 * RING_BLEED
			local cell = math.max(48, math.floor((usable - 3 * metric.cellGap) / 4))
			layout.CellSize = UDim2.fromOffset(cell, cell)
		else
			layout.CellSize = UDim2.fromOffset(metric.cellSize, metric.cellSize)
		end
	end
	applyCellSize(viewport)

	ViewportUtil.Observe(scroll, applyCellSize)

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
function Grid.CreateCellTemplate(config: CellConfig): ImageButton
	local cell = Instance.new("ImageButton")
	cell.Name = "CardTemplate"
	cell.Size = UDim2.fromOffset(metric.cellSize, metric.cellSize)
	cell.AutoButtonColor = false
	cell.BorderSizePixel = 0
	cell.Image = ""
	cell.Visible = false
	cell.ClipsDescendants = false
	cell.Parent = config.parent
	Theme.Paint(cell, surfaces.cell)
	Theme.Corner(cell, radius.cell)
	Theme.Ring(cell, Theme.rarity.Fabled, 2)

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
	Theme.Corner(preview, radius.cell - 3)

	if config.level then
		local badge = newLabel("LevelBadge", cell)
		badge.AnchorPoint = Vector2.new(0, 1)
		badge.Position = UDim2.new(0, 3, 1, -3)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 15)
		setText(badge, em.badge, config.root)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.Text = ""
		badge.Visible = false
		Theme.Paint(badge, surfaces.badge)
		Theme.Corner(badge, radius.badge)
		Theme.Padding(badge, 0, 6, 0, 6)
	end

	if config.quantity then
		local badge = newLabel("QuantityLabel", cell)
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, -3, 1, -3)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 15)
		setText(badge, em.badge, config.root)
		badge.TextXAlignment = Enum.TextXAlignment.Center
		badge.TextColor3 = Theme.textColors.coin
		badge.Text = ""
		Theme.Paint(badge, surfaces.badge)
		Theme.Corner(badge, radius.badge)
		Theme.Padding(badge, 0, 6, 0, 6)
	end

	if config.check then
		local check = newLabel("EquippedCheck", cell)
		check.AnchorPoint = Vector2.new(1, 0)
		check.Position = UDim2.new(1, -3, 0, 3)
		check.Size = UDim2.fromOffset(15, 15)
		check.BackgroundColor3 = Theme.accent.green
		check.BackgroundTransparency = 0
		check.TextColor3 = Theme.ink.onGreen
		check.FontFace = Theme.font.heavy
		setText(check, em.badge, config.root)
		check.TextXAlignment = Enum.TextXAlignment.Center
		check.Text = "✓"
		check.Visible = false
		Theme.Pill(check)
	end

	return cell
end

--- Applies the cell ring: rarity colour always, 3px when selected and 2px
--- (dimmed) when not. Primordial's ring cycles, so its tween is owned here and stopped
--- as soon as the cell stops being prismatic.
---
--- `colorOverride` is for entries that have no rarity at all — Materials carry their own
--- identity colour instead, and without this the selection ring would repaint them with
--- the default tier's white.
function Grid.SetCellRing(
	cell: GuiObject,
	rarity: string?,
	selected: boolean,
	colorOverride: Color3?
)
	local stroke = Theme.Ring(cell, colorOverride or Theme.RarityColor(rarity), selected and 3 or 2)
	stroke.Transparency = selected and 0 or 0.53
	local cardSurface = selected and surfaces.cellSelected or surfaces.cell
	cell.BackgroundColor3 = cardSurface.color
	cell.BackgroundTransparency = cardSurface.transparency

	local existing = cell:FindFirstChild("RingCycle")
	if not Theme.IsPrismatic(rarity) then
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
		local cycle = Theme.primordialCycle
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

return Grid
