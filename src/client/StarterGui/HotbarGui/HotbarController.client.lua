-- StarterGui/HotbarGui/HotbarController
-- The tool hotbar, styled as part of Roblox's own chrome.
--
-- Roblox's backpack hotbar cannot be restyled -- CoreGui owns it and exposes no properties
-- -- so matching the platform's look means turning it off and rebuilding it here. The
-- CoreGui flag is set once for the session; ModalUtil no longer touches it (see the note
-- there), and hides this ScreenGui instead when a panel opens.
--
-- A slot is one of Roblox's top left buttons: `#121215 @ 0.08`, going opaque under the
-- cursor. Those are the same tokens the HUD cluster in MainGui already uses, so the top and
-- bottom of the screen read as one system. There is no bar behind the slots -- the row is
-- the slots and nothing else. Two things depart from the platform on purpose:
--
--   * The slots are rounded squares, not the discs the top bar uses, so item art has a
--     square frame to sit in.
--   * The equipped state is a gold ring, the design system's primary accent. Roblox's own
--     white selection ring would be the one thing on screen a player could mistake for
--     platform UI.
--
-- Behaviour is otherwise the hotbar it replaces: slots fill in the order tools arrive, the
-- number keys equip and unequip them, and clicking an equipped slot puts the tool away.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Util = ReplicatedStorage:WaitForChild("Util")
local ButtonUtil = require(Util:WaitForChild("ButtonUtil"))
local ThemeUtil = require(Util:WaitForChild("ThemeUtil"))
local ModalUtil = require(Util:WaitForChild("ModalUtil"))
local CharacterUtil = require(Util:WaitForChild("CharacterUtil"))

-- Six slots, all of them on screen whether or not they hold anything. Roblox's hotbar is
-- ten deep and hides the empties; a fixed six reads as a deliberate loadout rather than a
-- list that grows, and it keeps the tray a stable width so it never jumps as tools come and
-- go. Tools past the sixth are still carried, they just have no slot -- the overflow lives
-- in the backpack on the platform hotbar, and here that is InventoryGui.
local SLOT_COUNT = 6

-- Gap between the bottom slot edge and the bottom of the screen. This is the one number to
-- change to raise or lower the hotbar.
local BOTTOM_MARGIN = 6

-- Keyboard slot bindings, in slot order.
local SLOT_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
}

local localPlayer = Players.LocalPlayer
local screenGui = script.Parent

screenGui.DisplayOrder = ThemeUtil.Layer.hotbar
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true

-- Off for the whole session. Set here rather than in ModalUtil because this script is the
-- thing standing in for it, so the flag and its replacement live or die together.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local camera = workspace.CurrentCamera

local function viewportSize(): Vector2
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

--------------------------------------------------------------------------------
-- Tray
--------------------------------------------------------------------------------

-- Bottom-centred. Invisible: it is a layout container only, so the slots are the whole of
-- the hotbar and there is no bar behind them. It carries no padding either -- padding would
-- hold the slots away from an edge nothing draws.
--
-- The GUI inset is ignored so the tray addresses the physical screen rather than the span
-- under Roblox's top bar, which is what lets the margin below be an honest distance from
-- the bottom of the display.
local tray = Instance.new("Frame")
tray.Name = "Tray"
tray.AnchorPoint = Vector2.new(0.5, 1)
tray.Size = UDim2.fromOffset(0, 0)
tray.AutomaticSize = Enum.AutomaticSize.XY
tray.BackgroundTransparency = 1
tray.BorderSizePixel = 0
tray.Visible = false
tray.Parent = screenGui

local trayLayout = Instance.new("UIListLayout")
trayLayout.FillDirection = Enum.FillDirection.Horizontal
trayLayout.Padding = UDim.new(0, ThemeUtil.Metric.hotbarGap)
trayLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
trayLayout.VerticalAlignment = Enum.VerticalAlignment.Center
trayLayout.SortOrder = Enum.SortOrder.LayoutOrder
trayLayout.Parent = tray

--------------------------------------------------------------------------------
-- Slots
--------------------------------------------------------------------------------

type Slot = {
	button: ImageButton,
	icon: ImageLabel,
	label: TextLabel,
	keyLabel: TextLabel,
	ring: UIStroke,
	hovered: boolean,
	tool: Tool?,
}

local slots: { Slot } = {}

--- Builds one round slot. Nothing about it is tool-specific; `bindSlot` fills it in.
local function createSlot(index: number): Slot
	local size = ThemeUtil.Metric.hotbarSlot

	local button = Instance.new("ImageButton")
	button.Name = string.format("Slot%d", index)
	button.Size = UDim2.fromOffset(size, size)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = ThemeUtil.Platform.topbarButtonFill
	button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonTransparency
	button.Image = ""
	button.LayoutOrder = index
	button.Parent = tray
	ThemeUtil.corner(button, ThemeUtil.Radius.hotbarSlot)

	-- Off until the slot is equipped. A zero-thickness stroke still renders a hairline, so
	-- the ring is switched with Transparency rather than Thickness.
	local ring = ThemeUtil.ring(button, ThemeUtil.Accent.gold, 2)
	ring.Transparency = 1

	-- The tool's own TextureId, when it has one. Roblox's hotbar falls back to the tool
	-- name and so does this: the Bat in StarterPack ships with an empty TextureId, so the
	-- fallback is the path this game actually takes today, not a rare edge case.
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.82, 0.5)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = ThemeUtil.Font.extraBold
	label.TextColor3 = ThemeUtil.Text.strong
	label.TextScaled = true
	label.TextWrapped = false
	label.Visible = false
	label.Parent = button

	-- Slot number, in the corner Roblox puts it in. Hidden on touch, where there is no
	-- keyboard for it to refer to.
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.AnchorPoint = Vector2.new(0.5, 1)
	keyLabel.Position = UDim2.new(0.5, 0, 1, -3)
	keyLabel.Size = UDim2.fromOffset(size, 10)
	keyLabel.BackgroundTransparency = 1
	keyLabel.BorderSizePixel = 0
	keyLabel.FontFace = ThemeUtil.Font.bold
	keyLabel.Text = tostring(index)
	keyLabel.TextColor3 = ThemeUtil.Text.dim
	keyLabel.TextTransparency = ThemeUtil.Text.dimTransparency
	keyLabel.TextSize = 10
	keyLabel.Visible = not UserInputService.TouchEnabled
	keyLabel.Parent = button

	return {
		button = button,
		icon = icon,
		label = label,
		keyLabel = keyLabel,
		ring = ring,
		hovered = false,
		tool = nil,
	}
end

--- True while `tool` is held rather than stowed.
local function isEquipped(tool: Tool): boolean
	local character = CharacterUtil.Get()
	return character ~= nil and tool.Parent == character
end

--- Repaints one slot's fill and ring for its current state. Equipped wins over hover, so
--- moving the cursor off an equipped slot does not clear its highlight.
---
--- Every state is the top bar button fill at a different strength -- a full-strength slot
--- holds something, a thinned one is empty. With no tray behind them the slots carry that
--- fill themselves; it used to come from the bar they sat in.
local function paintSlot(slot: Slot)
	local tool = slot.tool
	local equipped = tool ~= nil and isEquipped(tool)

	if equipped or slot.hovered then
		slot.button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonHoverTransparency
	elseif tool then
		slot.button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonTransparency
	else
		slot.button.BackgroundTransparency = ThemeUtil.Platform.topbarButtonEmptyTransparency
	end

	slot.ring.Transparency = equipped and 0 or 1
end

--- Points a slot at a tool, or at nothing when `tool` is nil. An empty slot keeps its place
--- in the tray -- it just loses its art and shows the empty fill.
local function bindSlot(slot: Slot, tool: Tool?)
	slot.tool = tool

	if not tool then
		slot.icon.Visible = false
		slot.label.Visible = false
		paintSlot(slot)
		return
	end

	local texture = tool.TextureId
	if texture ~= "" then
		slot.icon.Image = texture
		slot.icon.Visible = true
		slot.label.Visible = false
	else
		-- Two letters is what fits legibly in a 44px slot at this weight.
		slot.icon.Visible = false
		slot.label.Text = string.upper(string.sub(tool.Name, 1, 2))
		slot.label.Visible = true
	end

	paintSlot(slot)
end

for index = 1, SLOT_COUNT do
	local slot = createSlot(index)
	slots[index] = slot

	slot.button.MouseEnter:Connect(function()
		slot.hovered = true
		paintSlot(slot)
	end)
	slot.button.MouseLeave:Connect(function()
		slot.hovered = false
		paintSlot(slot)
	end)
end

--------------------------------------------------------------------------------
-- Equipping
--------------------------------------------------------------------------------

--- Equips the slot's tool, or stows it if it is already out. Roblox's hotbar toggles on a
--- second press of the same key and this matches.
local function activateSlot(index: number)
	local slot = slots[index]
	local tool = slot and slot.tool
	if not tool then
		return
	end

	local humanoid = CharacterUtil.GetHumanoid()
	if not humanoid then
		return
	end

	if isEquipped(tool) then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

for index, slot in ipairs(slots) do
	ButtonUtil.hookClick(slot.button, function()
		activateSlot(index)
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- `gameProcessed` covers chat and any other text field, so typing "1" in chat cannot
	-- swing a bat.
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	-- Panels take the keyboard while they are up, the same as they take the mouse.
	if ModalUtil.AnyOpen() then
		return
	end

	local index = table.find(SLOT_KEYS, input.KeyCode)
	if index then
		activateSlot(index)
	end
end)

--------------------------------------------------------------------------------
-- Tracking the player's tools
--------------------------------------------------------------------------------

-- Slot assignment is by arrival order and is *sticky*: a tool keeps its slot while it is
-- equipped, even though equipping moves it out of the Backpack and into the character.
-- Rebuilding the list from the Backpack alone would make the equipped tool's slot vanish
-- from under the player's cursor mid-swing.
local assigned: { Tool? } = table.create(SLOT_COUNT)

local function toolsInHand(): { Tool }
	local held = {}
	local character = CharacterUtil.Get()
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(held, child)
			end
		end
	end
	return held
end

local function toolsStowed(): { Tool }
	local stowed = {}
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				table.insert(stowed, child)
			end
		end
	end
	return stowed
end

--- Re-reads the player's tools and repaints every slot.
---
--- Cheap enough to run on any change: ten slots against a handful of tools. It is the whole
--- state machine, so equip, unequip, pickup, drop and respawn all land here rather than
--- each getting their own partial update to fall out of step.
local function refresh()
	-- Kept as an ordered list as well as a set: a set alone iterates in hash order, which
	-- would hand two tools picked up together their slots in an arbitrary order.
	local liveList: { Tool } = {}
	local live: { [Tool]: true } = {}
	for _, tool in ipairs(toolsStowed()) do
		live[tool] = true
		table.insert(liveList, tool)
	end
	for _, tool in ipairs(toolsInHand()) do
		if not live[tool] then
			live[tool] = true
			table.insert(liveList, tool)
		end
	end

	-- Drop tools that are gone entirely -- dropped, destroyed, or left behind by a respawn.
	for index = 1, SLOT_COUNT do
		local tool = assigned[index]
		if tool and not live[tool] then
			assigned[index] = nil
		end
	end

	-- Anything new takes the lowest free slot, which is how the platform hotbar fills.
	local placed: { [Tool]: true } = {}
	for index = 1, SLOT_COUNT do
		local tool = assigned[index]
		if tool then
			placed[tool] = true
		end
	end

	for _, tool in ipairs(liveList) do
		if not placed[tool] then
			for index = 1, SLOT_COUNT do
				if not assigned[index] then
					assigned[index] = tool
					placed[tool] = true
					break
				end
			end
		end
	end

	for index = 1, SLOT_COUNT do
		bindSlot(slots[index], assigned[index])
	end

	-- The tray is always up, even carrying nothing: the six slots are the loadout, and a
	-- player who has just dropped their last tool should still see where it goes back.
	-- Panels are the one thing that takes it off screen.
	tray.Visible = not ModalUtil.AnyOpen()
end

-- Every signal that can change what the player is carrying, coalesced onto one refresh.
-- Equipping fires a removal and an addition back to back on two different parents; deferring
-- means the pair is seen as the single state change it is.
local refreshQueued = false

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refresh()
	end)
end

local function watch(container: Instance)
	container.ChildAdded:Connect(queueRefresh)
	container.ChildRemoved:Connect(queueRefresh)
end

local backpack = localPlayer:FindFirstChildOfClass("Backpack")
if backpack then
	watch(backpack)
end

-- The Backpack is destroyed and remade on every respawn, so the new one has to be picked
-- up as it arrives; the connections to the old one die with it.
localPlayer.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watch(child)
		queueRefresh()
	end
end)

CharacterUtil.OnCharacter(function(character)
	watch(character)
	queueRefresh()
end)

--------------------------------------------------------------------------------
-- Layout and visibility
--------------------------------------------------------------------------------

--- Drops the slots to `BOTTOM_MARGIN` off the physical bottom edge.
---
--- This used to mirror the gap above Roblox's top bar buttons, but that gap is measured to
--- the *bar*, and there is no bar down here any more -- matching it left the slots reading
--- as though they were floating well short of the edge.
local function relayout()
	tray.Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
end

relayout()

if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end

-- Out of the way while a panel is up, in place of the CoreGui backpack toggle that used to
-- live in ModalUtil.
ModalUtil.OnChanged(function()
	queueRefresh()
end)

queueRefresh()
