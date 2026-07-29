-- ReplicatedStorage/Shared/Types
-- Shared shapes so services can stop typing `any`. Import with:
--   local Types = require(ReplicatedStorage.Shared.Types)
--   local function f(ctx: Types.Context) ... end

export type ResourceEntry = {
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
	resourceId: string,
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

export type WeaponSwing = {
	cooldownSeconds: number,
	animationId: string,
	animationSpeed: number,
	activeWindowSeconds: number,
	hitStopSeconds: number,
}

export type WeaponTarget = {
	maxTargets: number,
	reachStuds: number,
	serverToleranceStuds: number,
	requireLineOfSight: boolean,
}

export type WeaponImpact = {
	reactionMode: string,
	tumbleAngularSpeed: number,
	launchControlSeconds: number,
	planarDeltaV: number,
	verticalDeltaV: number,
	ragdollMaxSeconds: number,
	ragdollLandingRecoverySeconds: number,
}

export type WeaponImpactSound = {
	id: string,
	volume: number,
	startTimeSeconds: number?,
	minDistance: number,
	maxDistance: number,
}

export type WeaponVfx = {
	hitBurstParticles: number,
	impactSound: WeaponImpactSound?,
	airTrailParticlesPerStud: number,
	airTrailSeconds: number,
	airTrailBurstParticles: number,
}

export type ShieldProfile = {
	toggleCooldownSeconds: number,
	impactStaminaCost: number,
	slidePlanarDeltaV: number,
	slideControlSeconds: number,
}

export type WeaponProfile = {
	displayName: string,
	rarity: string,
	thumbnail: string,
	description: string,
	combatKind: string,
	weaponFamily: string,
	arenaOnly: boolean?,
	arenaHeightAllowanceStuds: number?,
	staminaCost: number?,
	swing: WeaponSwing?,
	target: WeaponTarget?,
	impact: WeaponImpact?,
	shield: ShieldProfile?,
	vfx: WeaponVfx?,
}

export type WeaponsMetadata = {
	Combat: {
		stamina: {
			maximum: number,
			regenPerSecond: number,
		},
		knockbackImmunitySeconds: number,
	},
	ToolAliases: { [string]: string },
	Profiles: { [string]: WeaponProfile },
	GetId: (Tool) -> string?,
	GetProfile: (Tool) -> (string?, WeaponProfile?),
	IsMeleeTool: (Tool) -> boolean,
	IsShieldTool: (Tool) -> boolean,
	IsCombatTool: (Tool) -> boolean,
}

-- The player document held by DataService.
export type PlayerDoc = {
	version: number,
	profile: { [string]: any },
	mythlings: { [string]: MythlingEntry },
	resources: { [string]: ResourceEntry },
	items: { [string]: any },
	currency: { [string]: number },
}

-- Injected into every service's Init by Bootstrap.
export type Context = {
	Instances: { [string]: Instance },
	Metadata: {
		Mythlings: { [string]: MythlingDef },
		Resources: { [string]: any },
		Items: { [string]: any },
		Spawns: { [string]: any },
		Weapons: WeaponsMetadata,
	},
	Remotes: { [string]: RemoteEvent | RemoteFunction },
	Services: { [string]: any },
}

-- Every service module follows this shape. Priority orders Init/Start; lower runs first.
export type Service = {
	Priority: number?,
	Init: ((Context) -> ())?,
	Start: (() -> ())?,
	Stop: (() -> ())?,
}

return {}
