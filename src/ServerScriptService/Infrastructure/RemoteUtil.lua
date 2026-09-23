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
	local production = folder(root, "Production")
	local base = folder(root, "Base")
	local combat = folder(root, "Combat")
	local world = folder(root, "World")
	return {
		Admin = { Feedback = event(admin, "Feedback") },
		State = { Update = event(state, "Update"), Request = request(state, "Request") },
		Inventory = { DeleteMythling = request(inventory, "DeleteMythling") },
		Production = {
			GetStatus = request(production, "GetStatus"),
			Collect = request(production, "Collect"),
		},
		Base = {
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
