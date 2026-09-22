--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Details

local Theme = require(script.Parent.Parent.Parent.Theme)
local Controls = require(script.Parent.Controls)
local Primitives = require(script.Parent.Primitives)
local ViewportUtil = require(script.Parent.Parent.Parent.ViewportUtil)

local Details = {}
local metric = Theme.metric
local radius = Theme.radius
local surfaces = Theme.surface
local em = Theme.em
local newFrame = Primitives.NewFrame
local newLabel = Primitives.NewLabel
local newList = Primitives.NewList
local flexFill = Primitives.FlexFill
local setText = Primitives.SetText
export type DetailsConfig = {
	parent: GuiObject,
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
	-- Adds a neutral ellipsis button for an anchored action menu.
	overflow: boolean?,
}

export type Details = {
	Root: GuiObject,
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
	SecondaryButton: GuiButton?,
	Footer: Frame?,
}

--- Showcase column: a 16:9 hero frame with name and element overlaid, an
--- [ i ] button for lore, rarity bottom-left and a rarity ring; then hero stats,
--- progress, and the footer buttons. Every menu's detail pane is this anatomy.
function Details.CreateDetails(config: DetailsConfig): Details
	local root = config.root
	local accent = config.accent or Theme.accent.gold
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local column = config.parent
	local layout = newList(column, Enum.FillDirection.Vertical, 10)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Hero: 16:9, capped so the art never crowds out the stats on a short screen.
	local hero = newFrame("Hero", column)
	hero.Size = UDim2.new(
		1,
		0,
		0,
		math.min(math.floor(Theme.DetailWidth(viewport) * 9 / 16), Theme.ArtMaxHeight(viewport))
	)
	hero.ClipsDescendants = true

	-- On a short screen the column cannot fit hero + stats + progress + footer at their
	-- natural heights, and without this the surplus spills past the card, which clips it --
	-- taking the footer button with it. The hero is the only part with slack, so it is the
	-- one allowed to give ground; everything below it stays at its designed size.
	local heroFlex = Instance.new("UIFlexItem")
	heroFlex.FlexMode = Enum.UIFlexMode.Shrink
	heroFlex.Parent = hero
	hero.LayoutOrder = 1
	Theme.Corner(hero, radius.hero)
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
	Theme.Corner(art, radius.cell)

	-- The top/bottom scrim that keeps the overlaid name and rarity legible over any art.
	--
	-- The dark band covers the name row before fading so bright thumbnail backgrounds
	-- cannot wash out the overlaid text at 7%-25% of the hero height.
	local veil = newFrame("Veil", hero)
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	veil.BackgroundTransparency = 0
	veil.ZIndex = 2
	-- Must be rounded to match the hero. ClipsDescendants on the hero clips to its
	-- rectangle, not to its corner radius, so a square opaque child fills the rounded
	-- corners back in -- and this child is at its most opaque exactly at the top and bottom
	-- edges, which is where those corners are.
	Theme.Corner(veil, radius.hero)
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
	Theme.Pill(elementIcon)
	Theme.Padding(elementIcon, 5, 5, 5, 5)

	local nameLabel = newLabel("NameLabel", nameRow)
	nameLabel.Size = UDim2.new(1, -31, 1, 0)
	setText(nameLabel, em.itemName, root)
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
		button.Size = UDim2.fromOffset(metric.infoSize, metric.infoSize)
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
		button.BackgroundTransparency = 0.5
		button.Text = "i"
		button.FontFace = Theme.font.heavy
		setText(button, em.caption, root)
		button.TextColor3 = Theme.textColors.strong
		button.ZIndex = 3
		button.Parent = hero
		Theme.Pill(button)
		Theme.Ring(button, Color3.fromRGB(255, 255, 255), 1.5).Transparency = 0.25
		infoButton = button
	end

	local rarityLabel = newLabel("RarityLabel", hero)
	rarityLabel.AnchorPoint = Vector2.new(0, 1)
	rarityLabel.Position = UDim2.new(0, 12, 1, -8)
	rarityLabel.AutomaticSize = Enum.AutomaticSize.X
	rarityLabel.Size = UDim2.fromOffset(0, 16)
	rarityLabel.FontFace = Theme.font.heavy
	setText(rarityLabel, em.caption, root)
	rarityLabel.TextColor3 = accent
	rarityLabel.ZIndex = 3
	rarityLabel.Text = ""
	local rarityShadow = Instance.new("UIStroke")
	rarityShadow.Color = Color3.fromRGB(0, 0, 0)
	rarityShadow.Thickness = 2
	rarityShadow.Transparency = 0.15
	rarityShadow.Parent = rarityLabel

	Theme.Ring(hero, accent, 3)

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
			value.Size = UDim2.new(1, 0, 0, math.ceil(Theme.Text(em.statValue, root)))
			value.FontFace = Theme.font.heavy
			setText(value, em.statValue, root)
			value:SetAttribute("TextHeightPadding", 0)
			value.TextXAlignment = Enum.TextXAlignment.Center
			value.TextTruncate = Enum.TextTruncate.AtEnd
			value.Text = "—"
			value.LayoutOrder = 1

			local label = newLabel("Label", slot)
			label.Size = UDim2.new(1, 0, 0, math.ceil(Theme.Text(em.statLabel, root)) + 2)
			label.FontFace = Theme.font.bold
			setText(label, em.statLabel, root)
			label:SetAttribute("TextHeightPadding", 2)
			label.TextColor3 = Theme.textColors.muted
			label.TextTransparency = Theme.textColors.mutedTransparency
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
		setText(progressLabel :: TextLabel, em.caption, root);
		(progressLabel :: TextLabel).Text = ""

		progressDetail = newLabel("Detail", row);
		(progressDetail :: TextLabel).AnchorPoint = Vector2.new(1, 0);
		(progressDetail :: TextLabel).Position = UDim2.fromScale(1, 0);
		(progressDetail :: TextLabel).Size = UDim2.fromScale(0.5, 1);
		(progressDetail :: TextLabel).FontFace = Theme.font.bold
		setText(progressDetail :: TextLabel, em.statLabel, root);
		(progressDetail :: TextLabel).TextColor3 = Theme.textColors.muted;
		(progressDetail :: TextLabel).TextTransparency = Theme.textColors.mutedTransparency;
		(progressDetail :: TextLabel).TextXAlignment = Enum.TextXAlignment.Right;
		(progressDetail :: TextLabel).Text = ""

		local trough = newFrame("Trough", block)
		trough.Size = UDim2.new(1, 0, 0, metric.barHeight)
		trough.ClipsDescendants = true
		trough.LayoutOrder = 2
		Theme.Paint(trough, surfaces.trough)
		Theme.Pill(trough)

		progressFill = newFrame("Fill", trough);
		(progressFill :: Frame).Size = UDim2.fromScale(0, 1);
		(progressFill :: Frame).BackgroundColor3 = accent;
		(progressFill :: Frame).BackgroundTransparency = 0
		Theme.Pill(progressFill :: Frame)
	end

	local footer: Frame? = nil
	local primaryButton: TextButton? = nil
	local secondaryButton: GuiButton? = nil
	if config.primary or config.secondaryIcon or config.overflow then
		footer = newFrame("Footer", column);
		(footer :: Frame).Size = UDim2.new(1, 0, 0, metric.buttonHeight);
		(footer :: Frame).LayoutOrder = 5
		local footerLayout = newList(footer :: Frame, Enum.FillDirection.Horizontal, 8)
		footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		if config.primary then
			primaryButton = Controls.PrimaryButton(footer :: Frame, config.primary, root, accent);
			(primaryButton :: TextButton).LayoutOrder = 1
			flexFill(primaryButton :: TextButton)
		end
		if not config.primary then
			local footerSpacer = newFrame("Spacer", footer :: Frame)
			footerSpacer.LayoutOrder = 1
			flexFill(footerSpacer)
		end
		if config.secondaryIcon then
			secondaryButton = Controls.SquareButton(
				footer :: Frame,
				config.secondaryIcon,
				config.secondaryTint or accent
			);
			(secondaryButton :: ImageButton).LayoutOrder = 2
		elseif config.overflow then
			secondaryButton = Controls.MoreButton(footer :: Frame);
			(secondaryButton :: TextButton).LayoutOrder = 2
		end
	end

	ViewportUtil.Observe(column, function(size)
		hero.Size = UDim2.new(
			1,
			0,
			0,
			math.min(math.floor(Theme.DetailWidth(size) * 9 / 16), Theme.ArtMaxHeight(size))
		)
	end)

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
function Details.SetHeroRarity(details: Details, rarity: string?)
	local color = Theme.RarityColor(rarity)
	local stroke = Theme.Ring(details.Hero, color, 3)
	-- The caption always shows the design's tier name, whatever vocabulary the caller has.
	details.RarityLabel.Text = rarity and Theme.Tier(rarity) or ""
	details.RarityLabel.TextColor3 = color

	local existing = details.Hero:FindFirstChild("RingCycle")
	if not Theme.IsPrismatic(rarity) then
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
		local cycle = Theme.primordialCycle
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
function Details.SetProgress(details: Details, fraction: number, fillColor: Color3?)
	local fill = details.ProgressFill
	if not fill then
		return
	end
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if fillColor then
		fill.BackgroundColor3 = fillColor
	end
end

return Details
