-- ReplicatedStorage/Client/Ui/ThemeUtil
-- The Mythic Legends design system, in one place.
--
-- Ported from the "Mythic Legends — Design System" doc. Sections below match its numbered
-- sections, so a token that changes there changes in exactly one place here.
--
-- Two conventions carry the web design over to Roblox:
--
--   * CSS `rgba(r,g,b,a)` fills become a Color3 plus a BackgroundTransparency of `1 - a`.
--     Each surface is exported as a {color, transparency} pair; `ThemeUtil.paint` applies
--     one to an instance so callers never juggle the two halves.
--   * The doc sizes panel text in `em` against a per-device root (12.5px phone / 14px
--     tablet / 15px desktop). `ThemeUtil.root` reads that root off the viewport and
--     `ThemeUtil.text` turns an em multiple into a TextSize, so one panel scales across
--     all three devices exactly as the doc describes.

local ThemeUtil = {}

export type Surface = { color: Color3, transparency: number }

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

--- rgba() -> the Color3 + BackgroundTransparency pair Roblox needs.
local function surface(value: string, alpha: number): Surface
	return { color = hex(value), transparency = 1 - alpha }
end

--------------------------------------------------------------------------------
-- 01 · Color
--------------------------------------------------------------------------------

ThemeUtil.Surface = {
	-- The centered card every menu is built on.
	panel = surface("141416", 0.92),
	-- Dim the world behind an open panel.
	scrim = surface("0a1222", 0.45),
	-- Lore/confirm modals sit above a panel, so they are nearly opaque.
	modal = surface("181a20", 0.98),
	-- Grid cells and other inset fills.
	cell = surface("ffffff", 0.08),
	-- An empty grid slot: the same inset, weaker.
	cellEmpty = surface("ffffff", 0.04),
	-- A locked grid cell reads as a hole rather than a fill.
	cellLocked = surface("000000", 0.32),
	-- Pills, secondary buttons and the close button.
	chip = surface("ffffff", 0.08),
	chipStrong = surface("ffffff", 0.14),
	-- Hairline divider inside modals.
	divider = surface("ffffff", 0.1),
	-- Progress bar troughs.
	trough = surface("ffffff", 0.12),
	-- The scrim a modal lays over its own panel.
	modalScrim = surface("060a14", 0.72),
	-- Badge backing on grid cells and proximity labels.
	badge = surface("141416", 0.75),
}

ThemeUtil.Accent = {
	gold = hex("ffd75e"), -- primary
	cyan = hex("8ad8e8"), -- craft
	green = hex("00d857"), -- confirm
	red = hex("ff3b4e"), -- danger
}

-- Ink laid on top of an accent fill.
ThemeUtil.Ink = {
	onGold = hex("141416"),
	onCyan = hex("141416"),
	onGreen = hex("0b2b16"),
	onRed = hex("ffffff"),
}

ThemeUtil.Text = {
	-- Panel titles and item names.
	strong = hex("ffffff"),
	-- Body copy outside a panel header.
	body = hex("e8edf7"),
	-- Coin pill figures.
	coin = hex("ffe9b0"),
	-- Stat labels under a stat value.
	muted = Color3.fromRGB(255, 255, 255),
	mutedTransparency = 0.5,
	-- Disabled button labels and locked-cell captions.
	dim = Color3.fromRGB(255, 255, 255),
	dimTransparency = 0.6,
}

ThemeUtil.Rarity = {
	Fabled = hex("e9eef5"), -- common · soft white
	Awakened = hex("35c4d8"), -- rare · pulsing teal
	Ancient = hex("9b45f0"), -- epic · mystic purple
	Divine = hex("ffd75e"), -- legendary · radiant gold
	Primordial = hex("ff3b4e"), -- mythical · prismatic shift
}

-- The doc labels each tier with the generic rarity it stands for ("Fabled · Common · soft
-- white"), which is the bridge between the design's names and the ones this game uses.
-- Metadata/Spawns declares the ladder as Common · Rare · Epic · Legendary · Secret — five
-- tiers deep exactly like the design's, so they line up rank for rank. "Secret" is the
-- rarest (spawn weight 5 against Common's 100), so it takes the design's rarest tier and
-- gets the prismatic ring.
--
-- Unmapped values fall through to the tier of the same name, so metadata that adopts the
-- design's own vocabulary keeps working without a change here.
ThemeUtil.RarityTier = {
	Common = "Fabled",
	Rare = "Awakened",
	Epic = "Ancient",
	Legendary = "Divine",
	Secret = "Primordial",
	Mythical = "Primordial",
}

--- The design tier for a metadata rarity, e.g. "Legendary" -> "Divine".
function ThemeUtil.tier(rarity: string?): string
	if not rarity then
		return "Fabled"
	end
	return ThemeUtil.RarityTier[rarity] or rarity
end

-- Primordial's ring cycles rather than sitting still. RingUtil tweens through these.
ThemeUtil.PrimordialCycle = {
	hex("ffd75e"),
	hex("ff8a5c"),
	hex("ff5ca8"),
	hex("b36bff"),
	hex("5cb8ff"),
}

ThemeUtil.Element = {
	Fire = hex("ff7a3c"),
	Water = hex("4aa3ff"),
	Earth = hex("8bce5a"),
	Air = hex("b6e3ea"),
	Light = hex("ffe07a"),
	Dark = hex("9d6bd6"),
}

--- Rarity ring colour, falling back to Fabled for anything unrecognised. Takes either a
--- design tier ("Divine") or a metadata rarity ("Legendary").
function ThemeUtil.rarityColor(rarity: string?): Color3
	return ThemeUtil.Rarity[ThemeUtil.tier(rarity)] or ThemeUtil.Rarity.Fabled
end

--- Only the top tier animates its ring.
function ThemeUtil.isPrismatic(rarity: string?): boolean
	return ThemeUtil.tier(rarity) == "Primordial"
end

--- Element tint, falling back to gold for anything unrecognised.
function ThemeUtil.elementColor(element: string?): Color3
	return (element and ThemeUtil.Element[element]) or ThemeUtil.Accent.gold
end

--------------------------------------------------------------------------------
-- 02 · Typography
--------------------------------------------------------------------------------

ThemeUtil.Font = {
	bold = Font.fromName("Nunito", Enum.FontWeight.Bold), -- 700
	extraBold = Font.fromName("Nunito", Enum.FontWeight.ExtraBold), -- 800
	heavy = Font.fromName("Nunito", Enum.FontWeight.Heavy), -- 900
}

-- em multiples off the device root, straight from the doc's type table.
ThemeUtil.Em = {
	panelTitle = 1.2, -- 18px desktop · 800
	statValue = 1.4667, -- 22px desktop · 900
	itemName = 1.0667, -- 16px desktop · 800
	body = 0.9333, -- 14px desktop · 800
	tab = 0.8667, -- 13px desktop · 800
	sectionLabel = 0.8, -- 12px desktop · 800
	caption = 0.7333, -- 11px desktop · 800
	statLabel = 0.6333, -- 9.5px desktop · 700
	badge = 0.6, -- 9px desktop · 800
}

--- The per-device root the doc sizes everything against: 12.5px phone, 14px tablet,
--- 15px desktop. Phones are detected by height the way the design canvas does, so a
--- landscape phone gets phone type rather than tablet type.
function ThemeUtil.root(viewport: Vector2): number
	if viewport.Y < 500 then
		return 12.5
	elseif viewport.X < 1300 then
		return 14
	end
	return 15
end

--- An em multiple as a pixel TextSize.
function ThemeUtil.text(em: number, root: number): number
	return math.round(em * root * 10) / 10
end

--------------------------------------------------------------------------------
-- 03 · Metrics
--------------------------------------------------------------------------------

ThemeUtil.Radius = {
	card = 16,
	hero = 14,
	cell = 10,
	modal = 16,
	button = 11,
	buttonSmall = 10,
	tab = 10,
	badge = 6,
	pill = 999,
	-- Hotbar slots are rounded squares rather than the discs the top bar uses, so item art
	-- gets a square frame to sit in.
	hotbarSlot = 12,
}

ThemeUtil.Metric = {
	-- Header row: identity left · tabs center · actions right.
	headerPadTop = 14,
	headerPadRight = 16,
	headerPadBottom = 10,
	headerPadLeft = 18,
	-- Body: grid 2fr · details 1fr · gap 14.
	bodyPad = 16,
	bodyPadTop = 4,
	bodyGap = 14,
	-- Grid cells.
	cellSize = 112,
	cellGap = 10,
	-- Tab pills.
	tabWidth = 88,
	tabHeight = 30,
	tabGap = 6,
	-- Round close button, and the [ i ] button on a hero frame.
	closeSize = 30,
	infoSize = 26,
	-- Footer: wide primary beside a square secondary.
	buttonHeight = 43,
	squareButton = 44,
	-- Progress bars.
	barHeight = 7,
	barHeightWide = 9,
	-- Proximity buttons out in the world.
	proximitySize = 56,
	-- Hotbar: a unibar-style tray of round slots along the bottom edge. The slot diameter
	-- matches Roblox's own top bar buttons so both strips read as the same chrome, and the
	-- tray's padding matches the gap Roblox leaves around the buttons inside its unibar.
	-- The hotbar is slots and nothing else -- no bar behind them -- so there is no tray
	-- padding here, and its gap off the bottom edge lives with the controller that sets it.
	hotbarSlot = 44,
	hotbarGap = 6,
}

--------------------------------------------------------------------------------
-- Top bar
--------------------------------------------------------------------------------

-- Roblox's own top bar chrome, read off CoreGui:
--
--   IconHitArea  44x44  screen y 12..56  #121215 @ 0.08  corner UDim(1, 0)
--   unibar pill  140x44 screen y 12..56  #121215 @ 0.08  corner UDim(1, 0)
--
-- with GetGuiInset().Y = 58. So the bar is the *bottom 48px* of the inset, and its buttons
-- are 44px centred in that, leaving 2px above and below.
--
-- These are constants rather than measurements because a LocalScript in a live game cannot
-- read CoreGui -- only Studio can. Deriving the button size from the inset instead would
-- be wrong on a notched phone, where the inset grows to clear the notch but Roblox's bar
-- stays 48 and simply sits lower. Anchoring to the bottom of the inset handles that.
ThemeUtil.Platform = {
	topbarRowHeight = 48,
	topbarButtonSize = 44,
	topbarButtonFill = hex("121215"),
	topbarButtonTransparency = 0.08,
	-- Slightly more opaque under the cursor, standing in for Roblox's own state overlay.
	topbarButtonHoverTransparency = 0,
	-- A hotbar slot standing empty. The same fill as a top bar button, thinned out so the
	-- slot reads as a place for something rather than a thing in its own right.
	topbarButtonEmptyTransparency = 0.5,
}

export type Topbar = {
	-- Screen Y where Roblox's bar starts, and how tall it is.
	rowTop: number,
	rowHeight: number,
	-- Diameter of a HUD button that sits level with Roblox's own.
	buttonSize: number,
	-- Horizontal span the developer may use. Roblox's own chrome sits left of `minX`.
	minX: number,
	maxX: number,
}

--- Locates Roblox's top bar so HUD chrome can line up with it.
---
--- TopbarInset is the absolute rectangle Roblox reserves for unobstructed topbar content.
--- It is the only reliable source for both axes: GetGuiInset describes the Core UI safe
--- canvas, which can be much taller than the visual topbar on mobile devices.
---
--- Guarded because GuiService is only meaningful on a client; a server-side require of
--- this module still needs to load.
function ThemeUtil.topbar(viewport: Vector2): Topbar
	local rowHeight = ThemeUtil.Platform.topbarRowHeight

	local okInset, guiInset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset()
	end)
	local insetY = (okInset and guiInset and guiInset.Y > 0) and guiInset.Y or rowHeight
	local rowTop = math.max(0, insetY - rowHeight)

	local minX, maxX = 0, viewport.X
	local okBar, bar = pcall(function()
		return game:GetService("GuiService").TopbarInset
	end)
	if okBar and bar and bar.Width > 0 then
		minX, maxX = bar.Min.X, bar.Max.X
		if bar.Height > 0 then
			rowTop = bar.Min.Y
			rowHeight = bar.Height
		end
	end

	return {
		rowTop = rowTop,
		rowHeight = rowHeight,
		buttonSize = ThemeUtil.Platform.topbarButtonSize,
		minX = minX,
		maxX = maxX,
	}
end

-- Margin left between the panel card and the edge of the usable area.
local PANEL_MARGIN = 8
-- On a phone the card only keeps a margin at the top, clear of Roblox's bar.
local PANEL_TOP_MARGIN = 4
-- The doc's fixed card height, kept as-is for tablet and desktop.
local PANEL_HEIGHT = 470

--- Height of the area a panel actually has to live in: the viewport minus Roblox's top
--- bar, since panels sit in a ScreenGui that respects the GUI inset.
function ThemeUtil.usableHeight(viewport: Vector2): number
	local ok, inset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset()
	end)
	local insetY = (ok and inset) and inset.Y or 0
	return math.max(viewport.Y - insetY, 120)
end

--- Panel card size for a viewport: phones fill the screen, everything else gets the doc's
--- fixed-height card.
---
--- Phones deliberately override the doc. They sit in a full-screen canvas (see
--- `useFullScreenCanvas`) and bleed past the safe area at the bottom only, so the card
--- reaches the physical screen edge through the strip the device reserves for its home
--- indicator. At the sides the card stays inside the safe area, clear of the notch.
function ThemeUtil.panelSize(viewport: Vector2): UDim2
	local usable = ThemeUtil.usableHeight(viewport)

	if ThemeUtil.isPhone(viewport) then
		local insets = ThemeUtil.safeInsets()
		return UDim2.new(1, -(insets.left + insets.right), 1, -(insets.top + PANEL_TOP_MARGIN))
	end

	-- Never taller than the usable area: the doc's fixed height overflows on short-but-not-
	-- phone screens (a 548px window has only 490px once Roblox's bar is out), and the card
	-- clips its own footer when that happens.
	local height = math.min(PANEL_HEIGHT, usable - PANEL_MARGIN * 2)
	return UDim2.fromOffset(math.min(math.floor(viewport.X * 0.82), 1080), height)
end

--- Where the panel card sits inside its ScreenGui.
---
--- Phones bottom-anchor it so it runs flush to the physical bottom edge and spend their one
--- margin at the top, where Roblox's bar is. Larger screens centre it, as the design canvas
--- shows, which is what looks right once the card no longer fills the view.
function ThemeUtil.panelPlacement(viewport: Vector2): (Vector2, UDim2)
	-- Pinned to the left safe edge rather than centred, so an asymmetric inset (a notch on
	-- one side in landscape) still lands the card inside the safe band.
	if ThemeUtil.isPhone(viewport) then
		return Vector2.new(0, 1), UDim2.new(0, ThemeUtil.safeInsets().left, 1, 0)
	end
	return Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
end

--- What the device reserves around the screen: notch/rounded corners at the sides, the home
--- indicator along the bottom, Roblox's bar along the top.
---
--- These have to be *measured*, not queried. `GetGuiInset()` reports only Roblox's top bar;
--- its second return value is `0, 0` even on a phone reserving 59px at each side and 21px
--- at the bottom. The only way to see them is to difference two canvases -- one that ignores
--- every inset against one that respects them -- which is what this does, once, and caches.
---
--- A panel that respects the safe canvas measures as flush against it while sitting visibly
--- short of the real screen edge. That was the bottom gap.
local cachedInsets: { left: number, top: number, right: number, bottom: number }? = nil

function ThemeUtil.safeInsets(): { left: number, top: number, right: number, bottom: number }
	if cachedInsets then
		return cachedInsets
	end
	local none = { left = 0, top = 0, right = 0, bottom = 0 }

	local ok, measured = pcall(function()
		local playerGui = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return nil
		end

		local function probe(ignoreInsets: boolean): (Vector2, Vector2, ScreenGui)
			local gui = Instance.new("ScreenGui")
			gui.ResetOnSpawn = false
			gui.Enabled = true
			if ignoreInsets then
				gui.IgnoreGuiInset = true
				pcall(function()
					gui.ScreenInsets = Enum.ScreenInsets.None
				end)
			end
			gui.Parent = playerGui
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundTransparency = 1
			frame.Parent = gui
			return frame.AbsolutePosition, frame.AbsoluteSize, gui
		end

		local fullPos, fullSize, fullGui = probe(true)
		local safePos, safeSize, safeGui = probe(false)
		fullGui:Destroy()
		safeGui:Destroy()

		-- Nothing has been laid out yet; caller should try again later.
		if fullSize.X <= 0 or safeSize.X <= 0 then
			return nil
		end

		return {
			left = math.max(safePos.X - fullPos.X, 0),
			top = math.max(safePos.Y - fullPos.Y, 0),
			right = math.max((fullPos.X + fullSize.X) - (safePos.X + safeSize.X), 0),
			bottom = math.max((fullPos.Y + fullSize.Y) - (safePos.Y + safeSize.Y), 0),
		}
	end)

	if ok and measured then
		cachedInsets = measured
		return measured
	end
	return none
end

--- Lets a phone panel address the whole screen, so its card can bleed past the safe area.
--- Content inside the card is padded back in by `safeInsets`, so the background reaches the
--- edges without pushing anything under the notch or the home indicator.
function ThemeUtil.useFullScreenCanvas(screenGui: ScreenGui, fullScreen: boolean)
	if fullScreen then
		screenGui.IgnoreGuiInset = true
		pcall(function()
			screenGui.ScreenInsets = Enum.ScreenInsets.None
		end)
	else
		screenGui.IgnoreGuiInset = false
		pcall(function()
			screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end)
	end
end

--- True when panels should take the whole screen rather than float as a card.
function ThemeUtil.isPhone(viewport: Vector2): boolean
	return viewport.Y < 500
end

--- Width of the details column, and the cap on its 16:9 hero frame.
function ThemeUtil.detailWidth(viewport: Vector2): number
	return viewport.Y < 500 and 264 or 300
end

function ThemeUtil.artMaxHeight(viewport: Vector2): number
	return viewport.Y < 500 and 134 or 150
end

--------------------------------------------------------------------------------
-- Layering
--------------------------------------------------------------------------------

-- ScreenGui.DisplayOrder for each layer of the UI. These used to live only in the place
-- file, where they are not version controlled and where the HUD's default of 0 put it
-- *below* the modal scrim -- so opening a panel dimmed the inventory and shop buttons
-- along with the world.
--
-- The HUD sits above both the scrim and the panels. It occupies the top bar strip, which
-- no panel reaches, so being on top costs nothing and keeps the persistent chrome lit and
-- clickable whenever a menu is open.
-- The hotbar sits below the scrim: it is world chrome like the Roblox backpack it replaces,
-- so an open panel is meant to dim it, and ModalUtil hides it outright anyway.
ThemeUtil.Layer = {
	hotbar = 0,
	scrim = 1,
	panel = 2,
	hud = 5,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Applies a surface token's colour and transparency together.
function ThemeUtil.paint(instance: GuiObject, token: Surface)
	instance.BackgroundColor3 = token.color
	instance.BackgroundTransparency = token.transparency
end

--- Rounds a corner. Radius is in pixels, matching the doc. Reuses an existing UICorner so
--- restyling an authored instance twice cannot leave two of them behind.
function ThemeUtil.corner(parent: Instance, radius: number): UICorner
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

--- A pill's radius is "fully round", which in Roblox is half the height.
function ThemeUtil.pill(parent: Instance): UICorner
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
	return corner
end

--- The inset ring the doc uses for rarity and selection. Border-mode stroke keeps it
--- inside the cell like `inset 0 0 0 Npx` does.
function ThemeUtil.ring(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = parent:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

--- Uniform padding in pixels.
function ThemeUtil.padding(parent: Instance, top: number, right: number, bottom: number, left: number): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingRight = UDim.new(0, right)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, left)
	pad.Parent = parent
	return pad
end

return ThemeUtil
