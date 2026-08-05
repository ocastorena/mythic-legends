-- StarterPlayer/StarterPlayerScripts/Controllers/HotbarController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Client = script.Parent.Parent
local ButtonUtil = require(Client:WaitForChild("UI"):WaitForChild("ButtonUtil"))
local EquipmentPreviewUtil = require(Client.UI:WaitForChild("EquipmentPreviewUtil"))
local ModalState = require(Client.UI:WaitForChild("State"):WaitForChild("ModalState"))
local Theme = require(Client.UI:WaitForChild("Theme"))
local CharacterUtil = require(Client:WaitForChild("Character"):WaitForChild("CharacterUtil"))
local ConsumablesMeta =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configurations"):WaitForChild("Consumables"))

local HotbarController = {}

local SLOT_COUNT = 6
local SLOT_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
}

type Slot = Types.HotbarSlotView & {
	hovered: boolean,
	tool: Tool?,
}

local initialized = false
local running = false
local view: Types.HotbarView?
local connections: { RBXScriptConnection } = {}
local slots: { Slot } = {}
local assigned: { Tool? } = table.create(SLOT_COUNT)
local disconnectModal: (() -> ())?
local refreshQueued = false
local coreGuiGeneration = 0

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function setBackpackEnabled(enabled: boolean)
	coreGuiGeneration += 1
	local generation = coreGuiGeneration
	task.spawn(function()
		for attempt = 1, 8 do
			if generation ~= coreGuiGeneration then
				return
			end
			local ok = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, enabled)
			if ok then
				return
			end
			task.wait(0.1 * attempt)
		end
		warn(`[HotbarController] Could not {if enabled then "restore" else "disable"} the Roblox Backpack UI`)
	end)
end

local function normalizeMetadataId(value: string): string
	return string.lower(string.gsub(value, "[^%w]", ""))
end

local function isConsumableTool(tool: Tool): boolean
	local configuredId = tool:GetAttribute("ConsumableId")
	local consumableId = if type(configuredId) == "string" and configuredId ~= "" then configuredId else tool.Name
	local normalizedId = normalizeMetadataId(consumableId)
	for metadataId, metadata in ConsumablesMeta do
		if
			type(metadata) == "table"
			and normalizeMetadataId(metadataId) == normalizedId
			and metadata.category == "consumable"
		then
			return true
		end
	end
	return false
end

local function isEquipped(tool: Tool): boolean
	local character = CharacterUtil.Get()
	return character ~= nil and tool.Parent == character
end

local function paintSlot(slot: Slot)
	local tool = slot.tool
	local equipped = tool ~= nil and isEquipped(tool)
	if equipped or slot.hovered then
		slot.button.BackgroundTransparency = Theme.Platform.topbarButtonHoverTransparency
	elseif tool then
		slot.button.BackgroundTransparency = Theme.Platform.topbarButtonTransparency
	else
		slot.button.BackgroundTransparency = Theme.Platform.topbarButtonEmptyTransparency
	end
	slot.ring.Transparency = if equipped then 0 else 1
end

local function bindSlot(slot: Slot, tool: Tool?)
	slot.tool = tool
	if not tool then
		EquipmentPreviewUtil.Clear(slot.icon)
		slot.icon.Image = ""
		slot.icon.Visible = false
		slot.label.Visible = false
		paintSlot(slot)
		return
	end

	EquipmentPreviewUtil.Clear(slot.icon)
	if tool.TextureId ~= "" then
		slot.icon.Image = tool.TextureId
		slot.icon.Visible = true
		slot.label.Visible = false
	elseif EquipmentPreviewUtil.Render(slot.icon, tool) then
		slot.icon.Image = ""
		slot.icon.Visible = true
		slot.label.Visible = false
	else
		slot.icon.Image = ""
		slot.icon.Visible = false
		slot.label.Text = string.upper(string.sub(tool.Name, 1, 2))
		slot.label.Visible = true
	end
	paintSlot(slot)
end

local function activateSlot(index: number)
	if ModalState.AnyOpen() then
		return
	end
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

local function toolsIn(container: Instance?): { Tool }
	local tools = {}
	if container then
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and isConsumableTool(child) then
				table.insert(tools, child)
			end
		end
	end
	return tools
end

local function refresh()
	if not running or not view then
		return
	end
	local liveList: { Tool } = {}
	local live: { [Tool]: true } = {}
	local backpack = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
	for _, tool in toolsIn(backpack) do
		live[tool] = true
		table.insert(liveList, tool)
	end
	for _, tool in toolsIn(CharacterUtil.Get()) do
		if not live[tool] then
			live[tool] = true
			table.insert(liveList, tool)
		end
	end

	for index = 1, SLOT_COUNT do
		local tool = assigned[index]
		if tool and not live[tool] then
			assigned[index] = nil
		end
	end
	local placed: { [Tool]: true } = {}
	for index = 1, SLOT_COUNT do
		local tool = assigned[index]
		if tool then
			placed[tool] = true
		end
	end
	for _, tool in liveList do
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
	view.tray.Visible = true
end

local function queueRefresh()
	if refreshQueued or not running then
		return
	end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refresh()
	end)
end

local function watch(container: Instance)
	table.insert(connections, container.ChildAdded:Connect(queueRefresh))
	table.insert(connections, container.ChildRemoved:Connect(queueRefresh))
end

function HotbarController.Init(_context: Types.ClientContext)
	initialized = true
end

function HotbarController.BindView(newView: Types.HotbarView): () -> ()
	assert(initialized, "[HotbarController] Init must run before BindView")
	assert(view == nil or view == newView, "[HotbarController] A Hotbar view is already bound")
	view = newView
	return function()
		if view == newView then
			view = nil
		end
	end
end

function HotbarController.Start()
	assert(initialized, "[HotbarController] Init must run before Start")
	assert(view, "[HotbarController] Hotbar view must be bound before Start")
	if running then
		return
	end
	running = true
	setBackpackEnabled(false)
	table.clear(slots)
	table.clear(assigned)

	for index, slotView in (view :: Types.HotbarView).slots do
		local slot: Slot = {
			button = slotView.button,
			icon = slotView.icon,
			label = slotView.label,
			keyLabel = slotView.keyLabel,
			ring = slotView.ring,
			hovered = false,
			tool = nil,
		}
		slots[index] = slot
		table.insert(
			connections,
			slot.button.MouseEnter:Connect(function()
				slot.hovered = true
				paintSlot(slot)
			end)
		)
		table.insert(
			connections,
			slot.button.MouseLeave:Connect(function()
				slot.hovered = false
				paintSlot(slot)
			end)
		)
		table.insert(
			connections,
			ButtonUtil.hookClick(slot.button, function()
				activateSlot(index)
			end)
		)
	end

	disconnectModal = ModalState.OnChanged(function(anyPanelOpen: boolean)
		for _, slot in slots do
			slot.button.Interactable = not anyPanelOpen
		end
	end)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard or ModalState.AnyOpen() then
				return
			end
			local index = table.find(SLOT_KEYS, input.KeyCode)
			if index then
				activateSlot(index)
			end
		end)
	)

	local backpack = Players.LocalPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		watch(backpack)
	end
	table.insert(
		connections,
		Players.LocalPlayer.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Backpack") then
				watch(child)
				queueRefresh()
			end
		end)
	)
	table.insert(
		connections,
		CharacterUtil.OnCharacter(function(character: Model)
			if running then
				watch(character)
				queueRefresh()
			end
		end)
	)
	queueRefresh()
end

function HotbarController.Stop()
	if not running then
		return
	end
	running = false
	refreshQueued = false
	disconnectAll()
	if disconnectModal then
		disconnectModal()
		disconnectModal = nil
	end
	if view then
		view.tray.Visible = false
	end
	for _, slot in slots do
		EquipmentPreviewUtil.Clear(slot.icon)
	end
	table.clear(slots)
	table.clear(assigned)
	setBackpackEnabled(true)
end

return HotbarController
