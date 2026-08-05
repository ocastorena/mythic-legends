-- StarterPlayer/StarterPlayerScripts/Controllers/InventoryController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local EquipmentMeta = require(ReplicatedStorage.Shared.Configurations.Equipment)

local InventoryController = {}

local connections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}
local equipmentChanged: BindableEvent
local initialized = false
local running = false
local equipmentAssets: Folder
local getCombatLoadout: RemoteFunction
local equipCombatItem: RemoteFunction
local deleteMythling: RemoteFunction

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function bindCharacter(character: Model)
	disconnectAll(characterConnections)
	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal("RightEquipped"):Connect(function()
			equipmentChanged:Fire()
		end)
	)
	table.insert(
		characterConnections,
		character:GetAttributeChangedSignal("LeftEquipped"):Connect(function()
			equipmentChanged:Fire()
		end)
	)
	equipmentChanged:Fire()
end

function InventoryController.Init(_context: Types.ClientContext)
	if initialized then
		return
	end
	initialized = true
	equipmentChanged = Instance.new("BindableEvent")
	InventoryController.OnEquipmentChanged = equipmentChanged.Event

	local network = ReplicatedStorage:WaitForChild("Network")
	local combatNetwork = network:WaitForChild("Combat")
	getCombatLoadout = combatNetwork:WaitForChild("GetLoadout") :: RemoteFunction
	equipCombatItem = combatNetwork:WaitForChild("Equip") :: RemoteFunction
	deleteMythling = network:WaitForChild("Inventory"):WaitForChild("DeleteMythling") :: RemoteFunction
	equipmentAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Equipment") :: Folder
end

function InventoryController.Start()
	assert(initialized, "[InventoryController] Init must run before Start")
	if running then
		return
	end
	running = true

	table.insert(connections, Players.LocalPlayer.CharacterAdded:Connect(bindCharacter))
	if Players.LocalPlayer.Character then
		bindCharacter(Players.LocalPlayer.Character)
	end
end

function InventoryController.RequestEquipmentSnapshot(): Types.InventoryEquipmentMap
	assert(initialized, "[InventoryController] Init must run before RequestEquipmentSnapshot")
	local equipment: Types.InventoryEquipmentMap = {}
	local success, response = pcall(getCombatLoadout.InvokeServer, getCombatLoadout)
	if not success then
		warn("[InventoryController] Combat Loadout request failed")
		return equipment
	end
	if type(response) ~= "table" or response.ok ~= true or type(response.snapshot) ~= "table" then
		return equipment
	end

	local snapshot = response.snapshot
	for _, owned in snapshot.equipment or {} do
		local definitionId = owned.definitionId
		local profile = type(definitionId) == "string" and EquipmentMeta.Profiles[definitionId]
		if profile then
			local entry = equipment[definitionId]
			if not entry then
				entry = {
					quantity = 0,
					equipped = false,
					textureId = "",
					instanceId = owned.instanceId,
					previewModel = equipmentAssets:FindFirstChild(profile.modelName),
				}
				equipment[definitionId] = entry
			end
			entry.quantity += 1
			if
				owned.instanceId == snapshot.primaryWeaponInstanceId
				or owned.instanceId == snapshot.shieldInstanceId
			then
				entry.equipped = true
				entry.instanceId = owned.instanceId
			end
		end
	end
	return equipment
end

function InventoryController.Equip(instanceId: string): boolean
	assert(initialized, "[InventoryController] Init must run before Equip")
	if instanceId == "" then
		return false
	end
	local success, response = pcall(equipCombatItem.InvokeServer, equipCombatItem, instanceId)
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
	assert(initialized, "[InventoryController] Init must run before DeleteMythling")
	if mythlingId == "" then
		return false
	end
	local success, response = pcall(deleteMythling.InvokeServer, deleteMythling, mythlingId)
	if not success then
		warn("[InventoryController] Delete Mythling request failed")
		return false
	end
	return type(response) == "table" and response.ok == true
end

function InventoryController.Stop()
	if not running then
		return
	end
	running = false
	disconnectAll(connections)
	disconnectAll(characterConnections)
end

return InventoryController
