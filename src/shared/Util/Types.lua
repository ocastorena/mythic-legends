-- ReplicatedStorage/Util/Types
-- Shared shapes so services can stop typing `any`. Import with:
--   local Types = require(ReplicatedStorage.Util.Types)
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

export type WeaponDef = {
	hitType: string,
	hitDuration: number,
	horiForce: number,
	vertForce: number,
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
		Spawns: { [string]: any },
		Weapons: { [string]: WeaponDef },
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
