--!strict
-- ServerScriptService/Infrastructure/RemoteUtil
-- Rojo owns the network instances. Resolve and validate the canonical shared contract.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local RemoteUtil = {}
export type Network = Types.Network

local function folder(parent: Instance, name: string): Folder
	local value = parent:WaitForChild(name)
	assert(value:IsA("Folder"), `[RemoteUtil] {parent.Name}.{name} must be a Folder`)
	return value
end

local function event(parent: Folder, name: string): RemoteEvent
	local value = parent:WaitForChild(name)
	assert(value:IsA("RemoteEvent"), `[RemoteUtil] {parent.Name}.{name} must be a RemoteEvent`)
	return value
end

local function request(parent: Folder, name: string): RemoteFunction
	local value = parent:WaitForChild(name)
	assert(
		value:IsA("RemoteFunction"),
		`[RemoteUtil] {parent.Name}.{name} must be a RemoteFunction`
	)
	return value
end

function RemoteUtil.Resolve(replicatedStorage: ReplicatedStorage): Network
	local root = folder(replicatedStorage, "Network")
	local admin = folder(root, "Admin")
	local state = folder(root, "State")
	local inventory = folder(root, "Inventory")
	local shop = folder(root, "Shop")
	local crafting = folder(root, "Crafting")
	local production = folder(root, "Production")
	local base = folder(root, "Base")
	local combat = folder(root, "Combat")
	local world = folder(root, "World")
	return {
		Admin = { Feedback = event(admin, "Feedback") },
		State = { Update = event(state, "Update"), Request = request(state, "Request") },
		Inventory = {
			DeleteMythling = request(inventory, "DeleteMythling"),
			EvolveMythling = request(inventory, "EvolveMythling"),
			SellMythling = request(inventory, "SellMythling"),
			SellEquipment = request(inventory, "SellEquipment"),
			SellMaterial = request(inventory, "SellMaterial"),
			DiscardMaterial = request(inventory, "DiscardMaterial"),
			UpgradeCapacity = request(inventory, "UpgradeCapacity"),
		},
		Shop = { GetShop = request(shop, "GetShop"), BuyOffer = request(shop, "BuyOffer") },
		Crafting = {
			GetStation = request(crafting, "GetStation"),
			StartJob = request(crafting, "StartJob"),
			CancelJob = request(crafting, "CancelJob"),
		},
		Production = {
			GetStatus = request(production, "GetStatus"),
			Collect = request(production, "Collect"),
		},
		Base = {
			GetBase = request(base, "GetBase"),
			BuildShrine = request(base, "BuildShrine"),
			ExpandBase = request(base, "ExpandBase"),
			PlaceMythling = request(base, "PlaceMythling"),
			RemoveMythling = request(base, "RemoveMythling"),
		},
		Combat = {
			StartAttack = event(combat, "StartAttack"),
			ReportHit = event(combat, "ReportHit"),
			SetShieldGuard = event(combat, "SetShieldGuard"),
			Reaction = event(combat, "Reaction"),
			Impact = event(combat, "Impact"),
			GetLoadout = request(combat, "GetLoadout"),
			Equip = request(combat, "Equip"),
			EquipEquipment = request(combat, "EquipEquipment"),
			UnequipEquipment = request(combat, "UnequipEquipment"),
		},
		World = { Spawned = event(world, "Spawned"), ClaimState = event(world, "ClaimState") },
	}
end

-- Roblox permits removing this callback; the published API definition omits its nil setter.
-- Isolate that engine-definition mismatch instead of weakening each service's remote type.
function RemoteUtil.ClearServerHandler(remote: RemoteFunction)
	local writable = (remote :: unknown) :: { OnServerInvoke: unknown }
	writable.OnServerInvoke = nil
end

return RemoteUtil
