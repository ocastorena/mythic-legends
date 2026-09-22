--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/InventoryController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Parent.Types)
local EquipmentMeta = require(ReplicatedStorage.Shared.Configurations.Equipment)
local Trove = require(ReplicatedStorage.Packages.Trove)

local InventoryController = {}

local lifetime = Trove.new()
local characterLifetime = lifetime:Extend()
local hasStopped = false
local generation = 0
local equipmentChanged: BindableEvent
local isInitialized = false
local isRunning = false
local equipmentAssets: Folder
local getCombatLoadout: RemoteFunction
local equipCombatItem: RemoteFunction
local deleteMythling: RemoteFunction

local function bindCharacter(character: Model)
	characterLifetime:Clean()
	characterLifetime:Add(character:GetAttributeChangedSignal("RightEquipped"):Connect(function()
		equipmentChanged:Fire()
	end))
	characterLifetime:Add(character:GetAttributeChangedSignal("LeftEquipped"):Connect(function()
		equipmentChanged:Fire()
	end))
	equipmentChanged:Fire()
end

function InventoryController.Init(_context: Types.ClientContext)
	if isInitialized then
		return
	end
	isInitialized = true
	equipmentChanged = Instance.new("BindableEvent")
	InventoryController.OnEquipmentChanged = equipmentChanged.Event

	local network = ReplicatedStorage:WaitForChild("Network")
	local combatNetwork = network:WaitForChild("Combat")
	getCombatLoadout = combatNetwork:WaitForChild("GetLoadout") :: RemoteFunction
	equipCombatItem = combatNetwork:WaitForChild("Equip") :: RemoteFunction
	deleteMythling =
		network:WaitForChild("Inventory"):WaitForChild("DeleteMythling") :: RemoteFunction
	equipmentAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Equipment") :: Folder
end

function InventoryController.Start()
	assert(isInitialized, "[InventoryController] Init must run before Start")
	assert(not hasStopped, "[InventoryController] Stop ends this controller's signal lifetime")
	if isRunning then
		return
	end
	isRunning = true

	lifetime:Connect(Players.LocalPlayer.CharacterAdded, bindCharacter)
	lifetime:Connect(Players.LocalPlayer.CharacterRemoving, function()
		characterLifetime:Clean()
	end)
	if Players.LocalPlayer.Character then
		bindCharacter(Players.LocalPlayer.Character)
	end
end

function InventoryController.RequestEquipmentSnapshot(): Types.InventoryEquipmentMap?
	assert(isInitialized, "[InventoryController] Init must run before RequestEquipmentSnapshot")
	local equipment: Types.InventoryEquipmentMap = {}
	local requestGeneration = generation
	local success, rawResponse = pcall(getCombatLoadout.InvokeServer, getCombatLoadout)
	if hasStopped or requestGeneration ~= generation then
		return nil
	end
	if not success then
		warn("[InventoryController] Combat Loadout request failed")
		return nil
	end
	local response: unknown = rawResponse
	if type(response) ~= "table" then
		return nil
	end
	local record = response :: { [string]: unknown }
	if record.ok ~= true or type(record.snapshot) ~= "table" then
		return nil
	end

	local snapshot = record.snapshot :: { [string]: unknown }
	if type(snapshot.equipment) ~= "table" then
		return nil
	end
	for _, rawOwned in snapshot.equipment :: { [unknown]: unknown } do
		if type(rawOwned) ~= "table" then
			continue
		end
		local owned = rawOwned :: { [string]: unknown }
		local definitionId = owned.definitionId
		local instanceId = owned.instanceId
		if type(definitionId) ~= "string" or type(instanceId) ~= "string" then
			continue
		end
		local profile = EquipmentMeta.profiles[definitionId]
		if profile then
			local entry: Types.InventoryEquipmentEntry = equipment[definitionId]
				or {
					quantity = 0,
					equipped = false,
					textureId = "",
					instanceId = instanceId,
					previewModel = equipmentAssets:FindFirstChild(profile.modelName),
				}
			equipment[definitionId] = entry
			entry.quantity += 1
			if
				owned.instanceId == snapshot.primaryWeaponInstanceId
				or owned.instanceId == snapshot.shieldInstanceId
			then
				entry.equipped = true
				entry.instanceId = instanceId
			end
		end
	end
	return equipment
end

function InventoryController.Equip(instanceId: string): boolean
	assert(isInitialized, "[InventoryController] Init must run before Equip")
	if instanceId == "" then
		return false
	end
	local requestGeneration = generation
	local success, response = pcall(equipCombatItem.InvokeServer, equipCombatItem, instanceId)
	if hasStopped or requestGeneration ~= generation then
		return false
	end
	if not success then
		warn("[InventoryController] Equip request failed")
		return false
	end
	if type(response) ~= "table" or response.ok ~= true then
		return false
	end
	equipmentChanged:Fire()
	return true
end

function InventoryController.DeleteMythling(mythlingId: string): boolean
	assert(isInitialized, "[InventoryController] Init must run before DeleteMythling")
	if mythlingId == "" then
		return false
	end
	local requestGeneration = generation
	local success, response = pcall(deleteMythling.InvokeServer, deleteMythling, mythlingId)
	if hasStopped or requestGeneration ~= generation then
		return false
	end
	if not success then
		warn("[InventoryController] Delete Mythling request failed")
		return false
	end
	return type(response) == "table" and response.ok == true
end

function InventoryController.BindEquipmentView(
	props: Types.InventoryEquipmentViewProps
): Types.InventoryEquipmentSession
	assert(isInitialized and not hasStopped, "[InventoryController] A live controller is required")
	local sessionLifetime = lifetime:Extend()
	local requests = sessionLifetime:Extend()
	local isDestroyed = false
	local isOpen = false
	local isQueued = false
	local isRequesting = false
	local needsRefresh = false
	local sessionGeneration = 0
	local session: Types.InventoryEquipmentSession
	local function close()
		isOpen = false
		sessionGeneration += 1
		requests:Clean()
		isQueued = false
		isRequesting = false
		needsRefresh = false
	end
	local function refresh()
		if isDestroyed or not isOpen or not props.isVisible() then
			return
		end
		if isRequesting then
			needsRefresh = true
			return
		end
		if isQueued then
			return
		end
		isQueued = true
		requests:Add(task.defer(function()
			isQueued = false
			if isDestroyed or not props.isVisible() then
				return
			end
			isRequesting = true
			local currentGeneration = sessionGeneration
			local snapshot = InventoryController.RequestEquipmentSnapshot()
			if isDestroyed or currentGeneration ~= sessionGeneration then
				return
			end
			isRequesting = false
			if snapshot and props.isVisible() then
				props.onSnapshot(snapshot)
			end
			if needsRefresh then
				needsRefresh = false
				refresh()
			end
			requests:Pop(coroutine.running())
		end))
	end
	session = {
		Refresh = function()
			isOpen = true
			refresh()
		end,
		Close = close,
		Equip = function(instanceId: string)
			if isDestroyed or not isOpen or not props.isVisible() then
				return
			end
			local currentGeneration = sessionGeneration
			requests:Add(task.defer(function()
				InventoryController.Equip(instanceId)
				if not isDestroyed and currentGeneration == sessionGeneration then
					refresh()
				end
				requests:Pop(coroutine.running())
			end))
		end,
		Destroy = function()
			if isDestroyed then
				return
			end
			isDestroyed = true
			close()
			lifetime:Remove(sessionLifetime)
		end,
	}
	sessionLifetime:Add(function()
		isDestroyed = true
		sessionGeneration += 1
	end)
	sessionLifetime:Connect(equipmentChanged.Event, refresh)
	return session
end

-- Stop is terminal because consumers retain the one public signal created by Init.
function InventoryController.Stop()
	if hasStopped then
		return
	end
	hasStopped = true
	isRunning = false
	generation += 1
	lifetime:Destroy()
	if isInitialized then
		equipmentChanged:Destroy()
	end
end

return InventoryController
