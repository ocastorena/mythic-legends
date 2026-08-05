--!strict
-- ReplicatedStorage/Shared/Types
-- Shared shapes so services can stop typing `any`. Import with:
--   local Types = require(ReplicatedStorage.Shared.Types)
--   local function f(ctx: Types.Context) ... end

export type MaterialEntry = {
	total: number,
}

-- One owned mythling, as persisted under the player document's `mythlings` section.
export type MythlingEntry = {
	typeId: string,
	variantId: string,
	claimedAt: number,
	standId: number?,
	-- nil while production is stopped (mythling not placed on a stand)
	lastCollectionAt: number?,
}

export type MythlingProduction = {
	materialId: string,
	baseRate: number,
	baseCapacity: number,
}

export type MythlingVariant = {
	model: string,
	thumbnail: string,
}

-- One entry in the Mythlings metadata table, keyed by typeId.
export type MythlingDef = {
	displayName: string,
	rarity: string,
	sizeClass: string,
	zoneRadius: number,
	fillRate: number,
	drainRate: number,
	description: string,
	production: MythlingProduction,
	variants: { [string]: MythlingVariant },
}

export type EquipmentProfile = {
	displayName: string,
	rarity: string,
	thumbnail: string,
	description: string,
	kind: "PrimaryWeapon" | "Shield",
	modelName: string,
	staminaCost: number?,
	cooldownSeconds: number?,
	animationId: string?,
	hitStartFallbackSeconds: number?,
	contactWindowSeconds: number?,
	hitStopSeconds: number?,
	reachStuds: number?,
	serverToleranceStuds: number?,
	requireLineOfSight: boolean?,
	planarKnockback: number?,
	verticalKnockback: number?,
	tumbleAngularSpeed: number?,
	launchControlSeconds: number?,
	maximumReactionSeconds: number?,
	landingRecoverySeconds: number?,
	airTrailSeconds: number?,
	impactSoundId: string?,
	activationCooldownSeconds: number?,
	impactStaminaCost: number?,
	blockArcDegrees: number?,
	slideKnockback: number?,
	slideDurationSeconds: number?,
	raiseAnimationId: string?,
	holdAnimationId: string?,
	lowerAnimationId: string?,
}

export type EquipmentConfiguration = {
	Combat: {
		staminaMaximum: number,
		staminaRegenPerSecond: number,
		knockbackImmunitySeconds: number,
		arenaHeightAllowanceStuds: number,
	},
	Profiles: { [string]: EquipmentProfile },
}

-- The player document held by DataService through ProfileStore.
export type PlayerDoc = {
	version: number,
	profile: { [string]: any },
	mythlings: { [string]: MythlingEntry },
	materials: { [string]: MaterialEntry },
	consumables: { [string]: any },
	currency: { [string]: number },
	equipment: { [string]: { definitionId: string } },
	combatLoadout: {
		primaryWeaponInstanceId: string?,
		shieldInstanceId: string?,
	},
	base: {
		stands: { [number]: any },
	},
}

export type StatePacket = {
	revision: number,
	values: { [string]: any },
	removed: { string }?,
	full: boolean?,
}

export type LocalDataApi = {
	OnStateChanged: RBXScriptSignal,
	Peek: (string) -> any?,
	GetRevision: () -> number,
}

export type InventoryEquipmentEntry = {
	quantity: number,
	equipped: boolean,
	textureId: string,
	instanceId: string?,
	previewModel: Instance?,
}

export type InventoryEquipmentMap = { [string]: InventoryEquipmentEntry }

export type InventoryControllerApi = {
	OnEquipmentChanged: RBXScriptSignal,
	RequestEquipmentSnapshot: () -> InventoryEquipmentMap,
	Equip: (string) -> boolean,
	DeleteMythling: (string) -> boolean,
}

export type ProductionStatus = {
	production: number,
	rate: number,
	capacity: number,
}

export type StandControllerApi = {
	OnStandRequested: RBXScriptSignal,
	GetProductionStatus: (string) -> ProductionStatus,
	Collect: (string) -> boolean,
	Place: (number, string) -> boolean,
	Remove: (number, string) -> boolean,
}

export type HotbarSlotView = {
	button: ImageButton,
	icon: ImageLabel,
	label: TextLabel,
	keyLabel: TextLabel,
	ring: UIStroke,
}

export type HotbarView = {
	screenGui: ScreenGui,
	tray: Frame,
	slots: { HotbarSlotView },
}

export type HotbarControllerApi = {
	BindView: (HotbarView) -> () -> (),
}

export type StaminaView = {
	container: Frame,
	fill: Frame,
}

export type CombatActionView = {
	root: Frame,
	attackButton: ImageButton,
	attackIcon: Frame,
	shieldButton: ImageButton,
	shieldIcon: Frame,
	relayout: () -> (),
}

export type CombatControllerApi = {
	BindView: (CombatActionView) -> () -> (),
	BindStaminaView: (StaminaView) -> () -> (),
}

export type ClientContext = {
	PlayerScripts: PlayerScripts,
	LocalData: LocalDataApi,
}

export type ActionResult<T> = { ok: true, value: T? } | { ok: false, code: string }

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

-- Injected into every service's Init by MainServer.
export type Context = {
	Instances: { [string]: Instance },
	Configurations: {
		Mythlings: { [string]: MythlingDef },
		Materials: { [string]: any },
		Consumables: { [string]: any },
		MythlingSpawns: { [string]: any },
		Equipment: EquipmentConfiguration,
	},
	Remotes: Network,
	Services: { [string]: any },
}

-- Every bootstrapped service follows this lifecycle; MainServer owns ordering.
export type Service = {
	Init: (Context) -> (),
	Start: () -> (),
	Stop: () -> (),
}

return {}
