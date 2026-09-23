--!strict
-- ReplicatedStorage/Shared/Types
-- Canonical configuration, saved-state, and network contracts shared across boundaries.

export type MaterialEntry = {
	total: number,
}

export type MaterialDef = {
	displayName: string,
	category: string,
	guiColor: string,
	thumbnail: string,
	description: string,
}

-- Inactive prototype definitions remain optional until their future update is designed.
export type ConsumableDef = {
	displayName: string?,
	thumbnail: string?,
	description: string?,
	rarity: string?,
	category: string?,
	value: number?,
	effect: string?,
}

export type ConsumableEntry = {
	consumableId: string?,
	quantity: number?,
	total: number?,
}

export type MythlingSpawnConfiguration = {
	targetActive: number,
	refillDeadlineSeconds: number,
	refillRetrySeconds: number,
	captureTickSeconds: number,
	ringVerticalAllowanceStuds: number,
	zonePadding: number, -- studs
	boundaryClearance: number,
	maxPlacementTries: number,
	fallbackStepStuds: number,
	rarityWeights: { [string]: number },
	expireSeconds: { [string]: number },
	formExpireSeconds: { [string]: number },
	defaultExpireSeconds: number,
}

-- One owned mythling, as persisted under the player document's `mythlings` section.
export type MythlingEntry = {
	typeId: string,
	variantId: string,
	claimedAt: number,
	level: number?,
	xp: number?,
	standId: number?,
	-- Legacy v2 cursor, consumed by the v3 migration. New work belongs to the stand.
	lastCollectionAt: number?,
}

export type MythlingProduction = {
	materialId: string,
	materialsPerMinute: number,
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
	swingDurationSeconds: number?,
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
	impactStaminaCost: number?,
	minimumGuardStamina: number?,
	raiseSeconds: number?,
	raiseTimeoutSeconds: number?,
	lowerSeconds: number?,
	lowerTimeoutSeconds: number?,
	blockArcDegrees: number?,
	slideKnockback: number?,
	slideDurationSeconds: number?,
	raiseAnimationId: string?,
	holdAnimationId: string?,
	lowerAnimationId: string?,
}

export type EquipmentConfiguration = {
	presentationDefaults: {
		cooldownSeconds: number,
		swingDurationSeconds: number,
		raiseSeconds: number,
		raiseTimeoutSeconds: number,
		lowerSeconds: number,
		lowerTimeoutSeconds: number,
		hitStartFallbackSeconds: number,
		contactWindowSeconds: number,
		slideDurationSeconds: number,
		launchControlSeconds: number,
		maximumReactionSeconds: number,
		landingRecoverySeconds: number,
		shieldSlideFullSpeedFraction: number,
	},
	combat: {
		staminaMaximum: number,
		staminaSpawn: number,
		staminaRegenPerSecond: number,
		knockbackImmunitySeconds: number,
		arenaHeightAllowanceStuds: number,
	},
	profiles: { [string]: EquipmentProfile },
}

-- The player document held by DataService through ProfileStore.
export type PlayerDoc = {
	version: number,
	profile: {
		userId: number,
		createdAt: number,
		lastLoginAt: number,
	},
	mythlings: { [string]: MythlingEntry },
	inventoryUpgrades: { [string]: number }?,
	materials: { [string]: MaterialEntry },
	-- Legacy values are preserved opaquely; this cleanup does not activate Consumables.
	consumables: { [string]: unknown },
	currency: { [string]: number },
	equipment: { [string]: { definitionId: string } },
	combatLoadout: {
		primaryWeaponInstanceId: string?,
		shieldInstanceId: string?,
	},
	base: {
		stands: { [string]: { production: StandProduction? } },
	},
}

export type StatePacket = {
	revision: number,
	-- This heterogeneous projection is decoded by LocalData's named-section boundary.
	-- Domain APIs expose their concrete records instead of carrying this dynamic shape onward.
	values: { [string]: any },
	removed: { string }?,
	full: boolean?,
}

export type ProductionStatus = {
	production: number,
	rate: number,
	capacity: number,
	progress: number,
	materials: { [string]: { stored: number, progress: number } },
	active: boolean,
	sampledAt: number,
}

export type StandProduction = {
	lastAccruedAt: number,
	materials: { [string]: { stored: number, progress: number } },
}

export type ProductionCollection = {
	collected: number,
	remaining: number,
	materials: { [string]: number },
}

export type CombatGuardRequest = {
	action: "Begin" | "Raised" | "Release" | "Lowered",
	sequence: number,
	character: Model,
}

export type CombatAttackRequest = { sequence: number, character: Model }

export type CombatHitReport = {
	sequence: number,
	character: Model,
	targetUserId: number,
	targetCharacter: Model,
}

export type CombatReactionType = "Launch" | "ShieldSlide"

export type CombatReaction = {
	hitId: number,
	character: Model,
	launchVelocity: Vector3,
	angularVelocity: Vector3,
	controlSeconds: number,
	reactionType: CombatReactionType,
	slideDurationSeconds: number,
	maximumReactionSeconds: number,
	landingRecoverySeconds: number,
}

export type InventoryCapacity = { used: number, limit: number }

export type ClaimMode = "Idle" | "Filling" | "Draining" | "Full"

export type ClaimUpdate = {
	userId: number,
	mythlingId: string?,
	mode: ClaimMode,
	progress: number,
	fillRate: number?,
	drainRate: number?,
	character: Model?,
	sampledAt: number,
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

return {}
