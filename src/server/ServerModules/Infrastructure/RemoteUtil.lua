-- ServerScriptService/ServerModules/Infrastructure/RemoteUtil
-- Rojo owns the network instances. This module validates and resolves that contract.

local RemoteUtil = {}

local CONTRACT = {
	State = { Update = "RemoteEvent", Request = "RemoteFunction" },
	Inventory = { DeleteMythling = "RemoteFunction" },
	Production = { GetStatus = "RemoteFunction", Collect = "RemoteFunction" },
	Base = { PlaceMythling = "RemoteFunction", RemoveMythling = "RemoteFunction" },
	Combat = {
		StartAttack = "RemoteEvent",
		ReportHit = "RemoteEvent",
		SetShieldGuard = "RemoteEvent",
		Reaction = "RemoteEvent",
		Impact = "RemoteEvent",
		GetLoadout = "RemoteFunction",
		Equip = "RemoteFunction",
	},
	World = { Spawned = "RemoteEvent", ClaimState = "RemoteEvent" },
}

export type Network = {
	State: { Update: RemoteEvent, Request: RemoteFunction },
	Inventory: { DeleteMythling: RemoteFunction },
	Production: { GetStatus: RemoteFunction, Collect: RemoteFunction },
	Base: { PlaceMythling: RemoteFunction, RemoveMythling: RemoteFunction },
	Combat: {
		StartAttack: RemoteEvent,
		ReportHit: RemoteEvent,
		SetShieldGuard: RemoteEvent,
		Reaction: RemoteEvent,
		Impact: RemoteEvent,
		GetLoadout: RemoteFunction,
		Equip: RemoteFunction,
	},
	World: { Spawned: RemoteEvent, ClaimState: RemoteEvent },
}

function RemoteUtil.Resolve(replicatedStorage: ReplicatedStorage): Network
	local root = replicatedStorage:WaitForChild("Network")
	local resolved = {}
	for domainName, definitions in pairs(CONTRACT) do
		local domain = root:WaitForChild(domainName)
		assert(domain:IsA("Folder"), `[RemoteUtil] Network.{domainName} must be a Folder`)
		local domainRemotes = {}
		for remoteName, expectedClass in pairs(definitions) do
			local remote = domain:WaitForChild(remoteName)
			assert(
				remote.ClassName == expectedClass,
				`[RemoteUtil] Network.{domainName}.{remoteName} must be a {expectedClass}`
			)
			domainRemotes[remoteName] = remote
		end
		resolved[domainName] = domainRemotes
	end
	return resolved :: any
end

return RemoteUtil
