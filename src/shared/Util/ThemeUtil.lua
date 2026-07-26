-- ReplicatedStorage/Util/ThemeUtil
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

--- Rarity ring colour, falling back to Fabled for anything unrecognised.
function ThemeUtil.rarityColor(rarity: string?): Color3
	return (rarity and ThemeUtil.Rarity[rarity]) or ThemeUtil.Rarity.Fabled
end

function ThemeUtil.isPrismatic(rarity: string?): boolean
	return rarity == "Primordial"
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
}

--- Panel card size for a viewport, following the design canvas' own breakpoints:
--- phones fill the screen, everything else gets a fixed-height 470px card.
function ThemeUtil.panelSize(viewport: Vector2): UDim2
	if viewport.Y < 500 then
		return UDim2.new(0, math.min(760, math.floor(viewport.X * 0.94)), 1, -16)
	end
	return UDim2.fromOffset(math.min(math.floor(viewport.X * 0.82), 1080), 470)
end

--- Width of the details column, and the cap on its 16:9 hero frame.
function ThemeUtil.detailWidth(viewport: Vector2): number
	return viewport.Y < 500 and 264 or 300
end

function ThemeUtil.artMaxHeight(viewport: Vector2): number
	return viewport.Y < 500 and 134 or 150
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Applies a surface token's colour and transparency together.
function ThemeUtil.paint(instance: GuiObject, token: Surface)
	instance.BackgroundColor3 = token.color
	instance.BackgroundTransparency = token.transparency
end

--- Rounds a corner. Radius is in pixels, matching the doc.
function ThemeUtil.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

--- A pill's radius is "fully round", which in Roblox is half the height.
function ThemeUtil.pill(parent: Instance): UICorner
	local corner = Instance.new("UICorner")
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
