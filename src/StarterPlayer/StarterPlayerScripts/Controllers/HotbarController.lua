--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/HotbarController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)
local client = script.Parent.Parent
local ButtonUtil = require(client:WaitForChild("UI"):WaitForChild("ButtonUtil"))
local EquipmentPreviewUtil = require(client.UI:WaitForChild("EquipmentPreviewUtil"))
local ModalState = require(client.UI:WaitForChild("State"):WaitForChild("ModalState"))
local Theme = require(client.UI:WaitForChild("Theme"))
local CharacterUtil = require(client:WaitForChild("Character"):WaitForChild("CharacterUtil"))
local ConsumablesMeta = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Configurations")
		:WaitForChild("Consumables")
)

local HotbarController = {}

local SLOT_COUNT = 6
local SLOT_KEYS = table.freeze({
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
})

type Slot = Types.HotbarSlotView & {
	isHovered: boolean,
	tool: Tool?,
}

local isInitialized = false
local isRunning = false
local view: Types.HotbarView?
local lifetime = Trove.new()
local previousBackpackEnabled: boolean? = nil
local slots: { Slot } = {}
local assigned: { Tool? } = {}

local isRefreshQueued = false
local coreGuiGeneration = 0

local function setBackpackEnabled(isEnabled: boolean)
	coreGuiGeneration += 1
	local generation = coreGuiGeneration
	lifetime:Add(task.defer(function()
		for attempt = 1, 8 do
			if generation ~= coreGuiGeneration then
				lifetime:Pop(coroutine.running())
				return
			end
			local ok = pcall(
				StarterGui.SetCoreGuiEnabled,
				StarterGui,
				Enum.CoreGuiType.Backpack,
				isEnabled
			)
			if ok then
				lifetime:Pop(coroutine.running())
				return
			end
			task.wait(0.1 * attempt)
		end
		warn(
			`[HotbarController] Could not {if isEnabled then "restore" else "disable"} the Roblox Backpack UI`
		)
		lifetime:Pop(coroutine.running())
	end))
end

local function normalizeMetadataId(value: string): string
	local normalized = string.gsub(value, "[^%w]", "")
	return string.lower(normalized)
end

local function isConsumableTool(tool: Tool): boolean
	local configuredId = tool:GetAttribute("ConsumableId")
	local consumableId = if type(configuredId) == "string" and configuredId ~= ""
		then configuredId
		else tool.Name
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
	if equipped or slot.isHovered then
		slot.button.BackgroundTransparency = Theme.platform.topbarButtonHoverTransparency
	elseif tool then
		slot.button.BackgroundTransparency = Theme.platform.topbarButtonTransparency
	else
		slot.button.BackgroundTransparency = Theme.platform.topbarButtonEmptyTransparency
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
	if not isRunning or not view then
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
	local currentView = view
	if currentView then
		currentView.tray.Visible = true
	end
end

local function queueRefresh()
	if isRefreshQueued or not isRunning then
		return
	end
	isRefreshQueued = true
	lifetime:Add(task.defer(function()
		isRefreshQueued = false
		refresh()
		lifetime:Pop(coroutine.running())
	end))
end

local function watch(container: Instance, owner: Trove.Trove?)
	local resourceOwner = owner or lifetime
	resourceOwner:Connect(container.ChildAdded, queueRefresh)
	resourceOwner:Connect(container.ChildRemoved, queueRefresh)
end

function HotbarController.Init(_context: Types.ClientContext)
	isInitialized = true
end

function HotbarController.BindView(newView: Types.HotbarView): () -> ()
	assert(isInitialized, "[HotbarController] Init must run before BindView")
	assert(view == nil or view == newView, "[HotbarController] A Hotbar view is already bound")
	view = newView
	return function()
		if view == newView then
			view = nil
		end
	end
end

function HotbarController.Start()
	assert(isInitialized, "[HotbarController] Init must run before Start")
	assert(view, "[HotbarController] Hotbar view must be bound before Start")
	if isRunning then
		return
	end
	isRunning = true
	local gotBackpackState, backpackState =
		pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
	previousBackpackEnabled = if gotBackpackState then backpackState else nil
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
			isHovered = false,
			tool = nil,
		}
		slots[index] = slot
		lifetime:Add(slot.button.MouseEnter:Connect(function()
			slot.isHovered = true
			paintSlot(slot)
		end))
		lifetime:Add(slot.button.MouseLeave:Connect(function()
			slot.isHovered = false
			paintSlot(slot)
		end))
		local clickConnection = ButtonUtil.HookClick(slot.button, function()
			activateSlot(index)
		end)
		lifetime:Add(clickConnection)
	end

	local disconnectModal = ModalState.OnChanged(function(isPanelOpen: boolean)
		for _, slot in slots do
			slot.button.Interactable = not isPanelOpen
		end
	end)
	lifetime:Add(function()
		disconnectModal()
	end)
	lifetime:Add(
		UserInputService.InputBegan:Connect(function(input: InputObject, wasGameProcessed: boolean)
			if
				wasGameProcessed
				or input.UserInputType ~= Enum.UserInputType.Keyboard
				or ModalState.AnyOpen()
			then
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
	lifetime:Add(Players.LocalPlayer.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			watch(child)
			queueRefresh()
		end
	end))
	local disconnectCharacter = CharacterUtil.OnCharacter(
		function(character: Model, characterLifetime)
			if isRunning then
				watch(character, characterLifetime)
				queueRefresh()
			end
		end
	)
	lifetime:Add(function()
		disconnectCharacter()
	end)
	queueRefresh()
end

function HotbarController.Stop()
	if not isRunning then
		return
	end
	isRunning = false
	isRefreshQueued = false
	coreGuiGeneration += 1
	lifetime:Clean()
	if view then
		view.tray.Visible = false
	end
	for _, slot in slots do
		EquipmentPreviewUtil.Clear(slot.icon)
	end
	table.clear(slots)
	table.clear(assigned)
	local wasEnabled = previousBackpackEnabled
	previousBackpackEnabled = nil
	if wasEnabled ~= nil then
		local restored = pcall(function()
			if not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack) then
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, wasEnabled)
			end
		end)
		if not restored then
			warn("[HotbarController] Could not restore the Roblox Backpack UI")
		end
	end
end

return HotbarController
