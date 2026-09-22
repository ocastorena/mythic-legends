--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Shell

local Theme = require(script.Parent.Parent.Parent.Theme)
local Controls = require(script.Parent.Controls)
local Primitives = require(script.Parent.Primitives)
local ViewportUtil = require(script.Parent.Parent.Parent.ViewportUtil)

local Shell = {}
local metric = Theme.metric
local radius = Theme.radius
local surfaces = Theme.surface
local em = Theme.em
local newFrame = Primitives.NewFrame
local newLabel = Primitives.NewLabel
local newList = Primitives.NewList
local flexFill = Primitives.FlexFill
local setText = Primitives.SetText
export type PanelConfig = {
	parent: Instance,
	title: string,
	-- Optional title size override for menus whose title is their only header identity.
	titleTextEm: number?,
	-- Optional feature-specific responsive size. Placement, safe-area handling and text
	-- scaling remain owned by the shared shell.
	size: ((Vector2) -> UDim2)?,
	-- Left-hand identity glyph. An image id, or nil for a title-only header.
	titleIcon: string?,
	-- Optional image box size for artwork with built-in transparent margins.
	titleIconSize: number?,
	-- Draws the glyph as a filled element disc rather than a flat icon (the shrine header).
	iconColor: Color3?,
	-- Roblox-style icon + label tabs, centered in the header. Strings remain supported for
	-- title-only tabs; tables add an icon-pack asset beside the title.
	tabs: { string | { name: string, icon: string?, color: Color3? } }?,
	-- Adds the coin pill to the header actions.
	coins: boolean?,
	coinIcon: string?,
	-- Adds a "Level n" pill to the header actions.
	levelPill: boolean?,
	-- Menu accent. Gold unless the menu says otherwise (cyan for crafting).
	accent: Color3?,
}

export type Panel = {
	Card: Frame,
	Header: Frame,
	Body: Frame,
	Content: Frame,
	Columns: Frame,
	Grid: Frame,
	Details: Frame,
	TitleLabel: TextLabel,
	TitleIcon: ImageLabel?,
	Tabs: { [string]: TextButton },
	CoinLabel: TextLabel?,
	LevelLabel: TextLabel?,
	MotionRoot: CanvasGroup,
	rootScale: number,
	accent: Color3,
}

--- Builds the shell. Sized against the current viewport, and re-sized whenever that
--- changes so one panel serves phone, tablet and desktop.
function Shell.Create(config: PanelConfig): Panel
	local accent = config.accent or Theme.accent.gold
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local root = Theme.Root(viewport)

	-- Every application panel uses Roblox's live safe canvas. This avoids timing-sensitive
	-- manual inset measurements while keeping controls clear of CoreGui and device notches.
	local screenGui = config.parent:IsA("ScreenGui") and config.parent
		or config.parent:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui then
		Theme.UseSafeCanvas(screenGui)
	end

	local function resolveCardSize(size: Vector2): UDim2
		return config.size and config.size(size) or Theme.PanelSize(size)
	end

	local motionRoot = Instance.new("CanvasGroup")
	motionRoot.Name = "MotionRoot"
	motionRoot.Size = UDim2.fromScale(1, 1)
	motionRoot.BackgroundTransparency = 1
	motionRoot.BorderSizePixel = 0
	motionRoot.ClipsDescendants = true
	motionRoot.Parent = config.parent

	local card = newFrame("Card", motionRoot)
	local anchor, position = Theme.PanelPlacement(viewport)
	card.AnchorPoint = anchor
	card.Position = position
	card.Size = resolveCardSize(viewport)
	card.ClipsDescendants = true
	Theme.Paint(card, surfaces.panel)
	Theme.Corner(card, radius.card)

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
	local headerContentHeight = metric.tabHeight
	header.Size =
		UDim2.new(1, 0, 0, metric.headerPadTop + headerContentHeight + metric.headerPadBottom)
	header.LayoutOrder = 1
	Theme.Padding(
		header,
		metric.headerPadTop,
		metric.headerPadRight,
		metric.headerPadBottom,
		metric.headerPadLeft
	)

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
			Theme.Pill(icon)
			Theme.Padding(icon, 7, 7, 7, 7)
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
	setText(titleLabel, config.titleTextEm or em.panelTitle, root)
	titleLabel.Text = config.title
	titleLabel.LayoutOrder = 2

	local tabs: { [string]: TextButton } = {}
	if config.tabs then
		local tabRow = newFrame("Tabs", header)
		tabRow.AnchorPoint = Vector2.new(0.5, 0.5)
		tabRow.Position = UDim2.fromScale(0.5, 0.5)
		tabRow.Size = UDim2.fromScale(0, 1)
		tabRow.AutomaticSize = Enum.AutomaticSize.X
		local row = newList(tabRow, Enum.FillDirection.Horizontal, metric.tabGap)
		row.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for index, tabConfig in ipairs(config.tabs) do
			local name = if type(tabConfig) == "table" then tabConfig.name else tabConfig
			local icon = if type(tabConfig) == "table" then tabConfig.icon else nil
			local iconColor = if type(tabConfig) == "table" then tabConfig.color else nil
			local tab = Controls.Tab(tabRow, name, accent, root, icon, iconColor)
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
		local pill, label = Controls.CoinPill(actions, config.coinIcon or "", root)
		pill.LayoutOrder = 1
		coinLabel = label
	end

	local levelLabel: TextLabel? = nil
	if config.levelPill then
		levelLabel = Controls.LevelPill(actions, root, accent);
		(levelLabel :: TextLabel).LayoutOrder = 2
	end

	-- Body: grid 2fr · details 1fr · gap 14, at every size.
	local body = newFrame("Body", card)
	body.Size = UDim2.fromScale(1, 1)
	body.LayoutOrder = 2
	flexFill(body)
	Theme.Padding(body, metric.bodyPadTop, metric.bodyPad, metric.bodyPad, metric.bodyPad)
	local bodyLayout = newList(body, Enum.FillDirection.Vertical, 0)
	bodyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bodyLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local content = newFrame("Content", body)
	content.Size = UDim2.fromScale(1, 1)
	flexFill(content)

	local columns = newFrame("Columns", content)
	columns.Size = UDim2.fromScale(1, 1)
	local columnsLayout = newList(columns, Enum.FillDirection.Horizontal, metric.bodyGap)
	columnsLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local grid = newFrame("Grid", columns)
	grid.Size = UDim2.fromScale(1, 1)
	grid.LayoutOrder = 1
	grid.ClipsDescendants = true
	flexFill(grid)

	local details = newFrame("Details", columns)
	details.Size = UDim2.new(0, Theme.DetailWidth(viewport), 1, 0)
	details.LayoutOrder = 2
	details.ClipsDescendants = true

	-- Rotating a phone or resizing a window changes which device root applies, so the card
	-- is re-measured and every em-sized label re-derived against the new root. The details
	-- pane and grid live under this card, so one pass covers them.
	ViewportUtil.Observe(card, function(size)
		card.Size = resolveCardSize(size)
		card.AnchorPoint, card.Position = Theme.PanelPlacement(size)
		if details.Visible then
			details.Size = UDim2.new(0, Theme.DetailWidth(size), 1, 0)
		end
		Primitives.RescaleText(card, Theme.Root(size))
	end)

	return {
		Card = card,
		Header = header,
		Body = body,
		Content = content,
		Columns = columns,
		Grid = grid,
		Details = details,
		TitleLabel = titleLabel,
		TitleIcon = titleIcon,
		Tabs = tabs,
		CoinLabel = coinLabel,
		LevelLabel = levelLabel,
		MotionRoot = motionRoot,
		rootScale = root,
		accent = accent,
	}
end

--- Hides the details column and lets the grid consume the complete body for a full-width
--- empty state. Restoring it re-applies the current responsive details width and body gap.
function Shell.SetDetailsVisible(panel: Panel, visible: boolean)
	panel.Details.Visible = visible
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	panel.Details.Size = if visible
		then UDim2.new(0, Theme.DetailWidth(viewport), 1, 0)
		else UDim2.fromOffset(0, 0)

	local columnsLayout = panel.Columns:FindFirstChildWhichIsA("UIListLayout")
	if columnsLayout then
		columnsLayout.Padding = UDim.new(0, if visible then metric.bodyGap else 0)
	end
end

return Shell
