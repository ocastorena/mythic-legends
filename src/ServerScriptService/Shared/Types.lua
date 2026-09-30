--!strict
-- ServerScriptService/Shared/Types
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
export type ProfileBoundary = "Ready" | "Checkpoint" | "Release"
export type ProfileMutation = (PlayerData, number) -> SharedTypes.TransactionOutcome
export type MutationPreparation = (PlayerData, number) -> SharedTypes.TransactionOutcome
export type ProfileSettlement = (
	PlayerData,
	number,
	ProfileBoundary
) -> SharedTypes.TransactionOutcome
export type DataApi = {
	RegisterProfileSettlement: (string, ProfileSettlement) -> (),
	RegisterMutationPreparation: (string, MutationPreparation) -> (),
	Checkpoint: (Player) -> SharedTypes.TransactionResult,
	Load: (Player) -> boolean,
	Release: (Player) -> (),
	GetData: (Player) -> PlayerData,
	GetLoadedData: (Player) -> PlayerData?,
	Update: (Player, string, ProfileMutation) -> SharedTypes.TransactionResult,
	Transact: (
		Player,
		SharedTypes.TransactionRequest,
		ProfileMutation
	) -> SharedTypes.TransactionResult,
	MarkDirty: (Player) -> boolean,
	SaveNow: (Player) -> boolean,
}
export type ProductionApi = {
	GetProduction: (Player, number) -> SharedTypes.ProductionStatus?,
	CollectProduction: (Player, number) -> (boolean, string?, SharedTypes.ProductionCollection?),
	SettleProduction: (Player, number) -> (boolean, string?),
	SettleShrines: (Player) -> SharedTypes.TransactionResult,
	CollectShrine: (Player, SharedTypes.CollectShrineRequest) -> SharedTypes.TransactionResult,
}
export type InventoryApi = {
	EvolveMythling: (Player, SharedTypes.EvolveMythlingRequest) -> SharedTypes.TransactionResult,
	SellMythling: (Player, SharedTypes.SellMythlingRequest) -> SharedTypes.TransactionResult,
	SellEquipment: (Player, SharedTypes.SellEquipmentRequest) -> SharedTypes.TransactionResult,
	SellMaterial: (Player, SharedTypes.SellMaterialRequest) -> SharedTypes.TransactionResult,
	DiscardMaterial: (Player, SharedTypes.DiscardMaterialRequest) -> SharedTypes.TransactionResult,
	UpgradeCapacity: (
		Player,
		SharedTypes.UpgradeInventoryCapacityRequest
	) -> SharedTypes.TransactionResult,
	GetMythlingCapacity: (Player) -> SharedTypes.InventoryCapacity?,
	SaveWonMythling: (Player, { typeId: string, variantId: string }) -> string?,
	GetMythling: (Player, string) -> SharedTypes.MythlingEntry?,
	MarkDirty: (Player) -> boolean,
	AddMaterial: (Player, string, number) -> boolean,
}
export type BaseApi = {
	GetBase: (Player) -> SharedTypes.BaseViewResult,
	CheckCraftingAccess: (Player, SharedTypes.BaseRecord, string?) -> string?,
	ExpandBase: (Player, SharedTypes.ExpandBaseRequest) -> SharedTypes.TransactionResult,
	BuildShrine: (Player, SharedTypes.BuildShrineRequest) -> SharedTypes.TransactionResult,
	UpgradeShrine: (Player, SharedTypes.UpgradeShrineRequest) -> SharedTypes.TransactionResult,
	DismantleShrine: (Player, SharedTypes.DismantleShrineRequest) -> SharedTypes.TransactionResult,
	AssignShrineWorker: (
		Player,
		SharedTypes.AssignShrineWorkerRequest
	) -> SharedTypes.TransactionResult,
	RemoveShrineWorker: (
		Player,
		SharedTypes.RemoveShrineWorkerRequest
	) -> SharedTypes.TransactionResult,
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
	CombatService: {
		EquipEquipment: (
			Player,
			SharedTypes.EquipEquipmentRequest
		) -> SharedTypes.TransactionResult,
		UnequipEquipment: (
			Player,
			SharedTypes.UnequipEquipmentRequest
		) -> SharedTypes.TransactionResult,
	},
	CraftingService: {
		GetStation: (
			Player,
			SharedTypes.GetCraftingStationRequest
		) -> SharedTypes.CraftingStationViewResult,
		StartJob: (Player, SharedTypes.StartCraftingRequest) -> SharedTypes.TransactionResult,
		CancelJob: (Player, SharedTypes.CancelCraftingRequest) -> SharedTypes.TransactionResult,
	},
	ShopService: {
		GetShop: (Player) -> SharedTypes.ShopViewResult,
		BuyOffer: (Player, SharedTypes.BuyShopOfferRequest) -> SharedTypes.TransactionResult,
	},
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
