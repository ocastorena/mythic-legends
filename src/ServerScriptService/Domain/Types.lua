--!strict
-- ServerScriptService/Domain/Types
-- Server-only protocols. Saved records and wire payloads retain their shared owner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)

export type PlayerData = SharedTypes.PlayerDoc
export type Mythlings = { [string]: SharedTypes.MythlingEntry }
export type Materials = { [string]: SharedTypes.MaterialEntry }
export type InventorySession = {
	mythlings: Mythlings?,
	materials: Materials?,
}
export type InventorySessions = { [number]: InventorySession }
export type DataApi = {
	Load: (Player) -> boolean,
	Release: (Player) -> (),
	GetData: (Player) -> PlayerData,
	GetLoadedData: (Player) -> PlayerData?,
	MarkDirty: (Player) -> boolean,
	SaveNow: (Player) -> boolean,
}
export type ProductionApi = {
	GetProduction: (Player, number) -> SharedTypes.ProductionStatus?,
	CollectProduction: (Player, number) -> (boolean, string?, SharedTypes.ProductionCollection?),
	SettleProduction: (Player, number) -> (boolean, string?),
}
export type InventoryApi = {
	GetMythlingCapacity: (Player) -> SharedTypes.InventoryCapacity?,
	SaveWonMythling: (Player, { typeId: string, variantId: string }) -> string?,
	GetMythling: (Player, string) -> SharedTypes.MythlingEntry?,
	MarkDirty: (Player) -> boolean,
	AddMaterial: (Player, string, number) -> (),
}
export type BaseApi = {
	GetSpawnPoint: (Player) -> BasePart?,
	HasStand: (Player, number) -> boolean,
	RemoveMythlingFromStand: (Player, string) -> boolean,
}
export type SpawnEntry = {
	id: string,
	displayName: string,
	model: Model,
	zone: BasePart?,
	typeId: string,
	variantId: string,
	rarity: string,
	radius: number,
	fillRate: number,
	drainRate: number,
	startedAt: number,
	lifetimeSeconds: number,
	expireAt: number,
	state: "PREFILL" | "SPAWNED" | "OVERTIME" | "CLAIMED" | "ESCORT" | "DESPAWNED",
	ownerUserId: number?,
	claimed: boolean?,
	claiming: boolean?,
}
export type SpawnApi = {
	GetActiveMythlings: () -> { [string]: SpawnEntry },
	IsCaptureReady: () -> boolean,
	EndContest: (string, string?) -> (),
	SetOvertime: (string) -> (),
	OnClaimed: (string, Player) -> (),
}
export type Services = {
	DivineInterventionService: { StartEvent: (string) -> (boolean, string) },
	DataService: DataApi,
	InventoryService: InventoryApi,
	BaseService: BaseApi,
	ProductionService: ProductionApi,
	MythlingSpawnService: SpawnApi,
}
export type Context = {
	Instances: {
		World: Folder,
		Runtime: Instance,
		Arena: BasePart,
		Mythlings: Instance,
		Bases: Folder,
		BaseIslands: Folder,
		MythlingAssets: Folder,
		BaseAssets: Instance,
		EquipmentAssets: Folder,
		Templates: Instance,
	},
	Configurations: {
		AdminCommands: SharedTypes.AdminCommandsConfiguration,
		Mythlings: { [string]: SharedTypes.MythlingDef },
		Equipment: SharedTypes.EquipmentConfiguration,
		MythlingSpawns: SharedTypes.MythlingSpawnConfiguration,
		Materials: { [string]: SharedTypes.MaterialDef },
		Consumables: { [string]: SharedTypes.ConsumableDef },
	},
	Remotes: SharedTypes.Network,
	Services: Services,
}
export type Service = {
	Init: (Context) -> (),
	Start: () -> (),
	Stop: () -> (),
}

return {}
