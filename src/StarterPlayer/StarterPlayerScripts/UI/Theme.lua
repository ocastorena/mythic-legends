--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Theme
-- Shared presentation tokens and responsive helpers; see docs/UI_GUIDELINES.md.
-- Surface tokens pair color with transparency. Typography uses em multiples of a device root.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Theme = {}

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

Theme.surface = {
	-- The centered card every menu is built on.
	panel = surface("141416", 0.92),
	-- Dim the world behind an open panel.
	scrim = surface("0a1222", 0.45),
	-- Lore/confirm modals sit above a panel, so they are nearly opaque.
	modal = surface("181a20", 0.98),
	-- Grid cards: a distinct slate well so transparent 3D previews separate from the panel.
	cell = surface("252c3a", 0.96),
	cellSelected = surface("30394a", 0.98),
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

Theme.accent = {
	gold = hex("ffd75e"), -- primary
	cyan = hex("8ad8e8"), -- craft
	green = hex("00d857"), -- confirm
	red = hex("ff3b4e"), -- danger
}

-- Stable semantic colors for menu tab icons. Labels and selection rails stay neutral so
-- color supplements the icon silhouette without becoming the only active-state signal.
Theme.tabIcon = {
	mythlings = hex("ffd75e"),
	equipment = hex("68b5ff"),
	consumables = hex("54d88b"),
	materials = hex("f5a45d"),
	featured = hex("ff78bd"),
	upgrades = hex("a98bff"),
}

-- Ink laid on top of an accent fill.
Theme.ink = {
	onGold = hex("141416"),
	onCyan = hex("141416"),
	onGreen = hex("0b2b16"),
	onRed = hex("ffffff"),
}

Theme.textColors = {
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

Theme.rarity = {
	Fabled = hex("e9eef5"), -- common · soft white
	Awakened = hex("35c4d8"), -- rare · pulsing teal
	Ancient = hex("9b45f0"), -- epic · mystic purple
	Divine = hex("ffd75e"), -- legendary · radiant gold
	Primordial = hex("ff3b4e"), -- mythical · prismatic shift
}

-- Retained prototype presentation names. Canonical launch labels are defined by the GDD;
-- changing visible labels belongs to the separate launch-alignment work.
Theme.rarityTier = {
	Common = "Fabled",
	Rare = "Awakened",
	Epic = "Ancient",
	Legendary = "Divine",
	Secret = "Primordial",
	Mythical = "Primordial",
}

--- The design tier for a metadata rarity, e.g. "Legendary" -> "Divine".
function Theme.Tier(rarity: string?): string
	if not rarity then
		return "Fabled"
	end
	return Theme.rarityTier[rarity] or rarity
end

-- Panel/Grid and Panel/Details animate the top prototype tier through these colors.
Theme.primordialCycle = {
	hex("ffd75e"),
	hex("ff8a5c"),
	hex("ff5ca8"),
	hex("b36bff"),
	hex("5cb8ff"),
}

Theme.element = {
	Fire = hex("ff7a3c"),
	Water = hex("4aa3ff"),
	Earth = hex("8bce5a"),
	Air = hex("b6e3ea"),
	Light = hex("ffe07a"),
	Dark = hex("9d6bd6"),
}

--- Rarity ring colour, falling back to Fabled for anything unrecognised. Takes either a
--- design tier ("Divine") or a metadata rarity ("Legendary").
function Theme.RarityColor(rarity: string?): Color3
	return Theme.rarity[Theme.Tier(rarity)] or Theme.rarity.Fabled
end

--- Only the top tier animates its ring.
function Theme.IsPrismatic(rarity: string?): boolean
	return Theme.Tier(rarity) == "Primordial"
end

--- Element tint, falling back to gold for anything unrecognised.
function Theme.ElementColor(element: string?): Color3
	local colors: { [string]: Color3 } = Theme.element
	return if element then colors[element] or Theme.accent.gold else Theme.accent.gold
end

--------------------------------------------------------------------------------
-- 02 · Typography
--------------------------------------------------------------------------------

Theme.font = {
	bold = Font.fromName("Nunito", Enum.FontWeight.Bold), -- 700
	extraBold = Font.fromName("Nunito", Enum.FontWeight.ExtraBold), -- 800
	heavy = Font.fromName("Nunito", Enum.FontWeight.Heavy), -- 900
}

-- Typography multiples relative to the configured device root.
Theme.em = {
	panelTitle = 1.2, -- 18px desktop · 800
	panelTitleLarge = 1.4, -- 21px desktop · 800
	statValue = 1.4667, -- 22px desktop · 900
	itemName = 1.0667, -- 16px desktop · 800
	body = 0.9333, -- 14px desktop · 800
	tab = 0.9333, -- 14px desktop · 800
	sectionLabel = 0.8, -- 12px desktop · 800
	caption = 0.7333, -- 11px desktop · 800
	statLabel = 0.6333, -- 9.5px desktop · 700
	badge = 0.6, -- 9px desktop · 800
}

-- Em-stamped text inside application menus gets one shared accessibility scale. HUD text
-- uses Theme.textColors directly and deliberately remains at the platform-sized baseline.
Theme.menuTextScale = 1.3

--- Responsive typography uses a 12.5px phone root, 14px tablet root,
--- 15px desktop. Phones are detected by height the way the design canvas does, so a
--- landscape phone gets phone type rather than tablet type.
function Theme.Root(viewport: Vector2): number
	if viewport.Y < 500 then
		return 12.5
	elseif viewport.X < 1300 then
		return 14
	end
	return 15
end

--- An em multiple as a pixel TextSize.
function Theme.Text(em: number, root: number): number
	return math.round(em * root * 10) / 10
end

--------------------------------------------------------------------------------
-- 03 · Metrics
--------------------------------------------------------------------------------

Theme.radius = {
	-- Roblox's in-experience menu container uses a 10px outer corner radius.
	card = 10,
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

Theme.metric = {
	-- Header row: identity left · tabs center · actions right.
	headerPadTop = 8,
	headerPadRight = 16,
	headerPadBottom = 6,
	headerPadLeft = 18,
	-- Body: grid 2fr · details 1fr · gap 14.
	bodyPad = 16,
	bodyPadTop = 4,
	bodyGap = 14,
	-- Grid cells.
	cellSize = 112,
	cellGap = 10,
	-- Roblox-style menu tabs: icon + label on a transparent rail with a 2px underline.
	tabWidth = 116,
	tabHeight = 40,
	tabGap = 12,
	tabIconSize = 22,
	tabIconGap = 6,
	-- Round close button, and the [ i ] button on a hero frame.
	closeSize = 30,
	infoSize = 26,
	-- Footer: wide primary beside a square secondary.
	buttonHeight = 43,
	squareButton = 44,
	-- Inventory overflow menu, anchored above the footer's ellipsis button.
	actionMenuWidth = 168,
	actionMenuItemHeight = 46,
	actionMenuIconSize = 24,
	actionMenuPadding = 6,
	actionMenuGap = 4,
	actionMenuOffset = 8,
	-- Full-body Inventory empty state.
	emptyStateMaxWidth = 420,
	emptyStateHeight = 164,
	emptyStateIconDiscSize = 72,
	emptyStateIconSize = 40,
	emptyStateGap = 8,
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
Theme.platform = {
	topbarRowHeight = 48,
	topbarButtonSize = 44,
	-- Roblox's menu icon is 24px at rest and grows to 30px while its menu is open.
	topbarIconSize = 24,
	topbarIconOpenScale = 1.25,
	-- Match the critically damped ReactOtter spring used by Roblox's menu icon.
	topbarIconSpringSpeed = 2 * math.pi / 0.35,
	topbarIconSpringDamping = 1,
	-- Physical gap between a platform control and a display edge.
	topbarEdgePadding = 12,
	-- Keep the menu low while retaining enough safe-canvas clearance for its corners.
	menuBottomCornerClearance = Theme.radius.card - 8,
	topbarButtonFill = hex("121215"),
	topbarButtonTransparency = 0.08,
	-- Roblox Foundation's light state-layer values for top-bar controls.
	topbarButtonStateLayerFill = Color3.new(1, 1, 1),
	topbarButtonHoverStateTransparency = 0.88,
	topbarButtonPressedStateTransparency = 0.8,
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
}

--- Locates Roblox's top bar so HUD chrome can line up with it.
---
--- The vertical Core UI inset gives the bottom of Roblox's button row. We keep the row
--- height fixed to Roblox's standard control height, rather than stretching the HUD to
--- the whole inset (which includes additional device-safe space on phones).
---
--- Guarded because GuiService is only meaningful on a client; a server-side require of
--- this module still needs to load.
function Theme.Topbar(_viewport: Vector2): Topbar
	local rowHeight = Theme.platform.topbarRowHeight

	local okInset, guiInset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset()
	end)
	local insetY = (okInset and guiInset and guiInset.Y > 0) and guiInset.Y or rowHeight
	local rowTop = math.max(0, insetY - rowHeight)

	return {
		rowTop = rowTop,
		rowHeight = rowHeight,
		buttonSize = Theme.platform.topbarButtonSize,
	}
end

-- Margin left between the panel card and the edge of the usable area.
local PANEL_MARGIN = 8
-- On a phone the card only keeps a margin at the top, clear of Roblox's bar.
local PANEL_TOP_MARGIN = 4
-- Keep the rounded bottom edge inside the safe canvas instead of clipping it below the screen.
local PANEL_PHONE_BOTTOM_MARGIN = Theme.platform.menuBottomCornerClearance
-- Fixed card height for tablet and desktop.
local PANEL_HEIGHT = 470

--- Height of the area a panel actually has to live in: the viewport minus Roblox's top
--- bar, since panels sit in a ScreenGui that respects the GUI inset.
function Theme.UsableHeight(viewport: Vector2): number
	local ok, inset = pcall(function()
		return game:GetService("GuiService"):GetGuiInset()
	end)
	local insetY = (ok and inset) and inset.Y or 0
	return math.max(viewport.Y - insetY, 120)
end

--- Panel card size for a viewport: phones fill the safe canvas; larger devices use a
--- fixed-height card.
---
--- Phones use Roblox's CoreUISafeInsets canvas. The card fills that safe canvas with a small
--- top and bottom margin, keeping controls clear of the top bar, notch, and home region.
function Theme.PanelSize(viewport: Vector2): UDim2
	local usable = Theme.UsableHeight(viewport)

	if Theme.IsPhone(viewport) then
		return UDim2.new(1, 0, 1, -(PANEL_TOP_MARGIN + PANEL_PHONE_BOTTOM_MARGIN))
	end

	-- Never taller than the usable area: the fixed height overflows on short-but-not-
	-- phone screens (a 548px window has only 490px once Roblox's bar is out), and the card
	-- clips its own footer when that happens.
	local height = math.min(PANEL_HEIGHT, usable - PANEL_MARGIN * 2)
	return UDim2.fromOffset(math.min(math.floor(viewport.X * 0.82), 1080), height)
end

--- Where the panel card sits inside its ScreenGui.
---
--- Phones bottom-anchor it so it runs flush to the physical bottom edge and spend their one
-- margin at the top, where Roblox's bar is. Larger screens centre between the bottom of
-- Roblox's top HUD and the top of the hotbar rather than against the whole remaining canvas.
function Theme.PanelPlacement(viewport: Vector2): (Vector2, UDim2)
	-- The ScreenGui already uses CoreUISafeInsets, so placement is relative to the safe canvas.
	if Theme.IsPhone(viewport) then
		return Vector2.new(0, 1), UDim2.new(0, 0, 1, -PANEL_PHONE_BOTTOM_MARGIN)
	end

	local hotbarHeight = Theme.metric.hotbarSlot + Theme.platform.topbarEdgePadding
	return Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, -hotbarHeight / 2)
end

--- Keeps application panels inside Roblox's current top-bar and device-safe canvas.
function Theme.UseSafeCanvas(screenGui: ScreenGui)
	screenGui.IgnoreGuiInset = false
	screenGui.ClipToDeviceSafeArea = true
	screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	pcall(function()
		screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
end

--- True when panels should take the whole screen rather than float as a card.
function Theme.IsPhone(viewport: Vector2): boolean
	return viewport.Y < 500
end

--- Width of the details column, and the cap on its 16:9 hero frame.
function Theme.DetailWidth(viewport: Vector2): number
	if viewport.Y < 500 then
		return 264
	end
	return viewport.X >= 1300 and 400 or 300
end

function Theme.ArtMaxHeight(viewport: Vector2): number
	if viewport.Y < 500 then
		return 134
	end
	return viewport.X >= 1300 and 195 or 150
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
-- The hotbar and Stamina meter sit below the scrim: they are world chrome, so an open panel
-- dims them and blocks any input while leaving them visible as persistent combat context.
Theme.layer = {
	hotbar = 0,
	stamina = 0,
	scrim = 1,
	panel = 2,
	hud = 5,
	toast = 10,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Applies a surface token's colour and transparency together.
function Theme.Paint(instance: GuiObject, token: Surface)
	instance.BackgroundColor3 = token.color
	instance.BackgroundTransparency = token.transparency
end

--- Rounds a corner in pixels. Reuses an existing UICorner so
--- restyling an authored instance twice cannot leave two of them behind.
function Theme.Corner(parent: Instance, radius: number): UICorner
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

--- A pill's radius is "fully round", which in Roblox is half the height.
function Theme.Pill(parent: Instance): UICorner
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
	return corner
end

--- Rarity and selection ring. Border-mode stroke keeps it
--- inside the cell like `inset 0 0 0 Npx` does.
function Theme.Ring(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = parent:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

--- Uniform padding in pixels.
function Theme.Padding(
	parent: Instance,
	top: number,
	right: number,
	bottom: number,
	left: number
): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingRight = UDim.new(0, right)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, left)
	pad.Parent = parent
	return pad
end

return FreezeUtil.DeepFreeze(Theme)
