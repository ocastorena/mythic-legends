--!strict
-- ReplicatedStorage/Shared/Types
-- Canonical configuration, saved-state, and network contracts shared across boundaries.

export type MaterialEntry = {
	total: number,
}

export type Element = "Fire" | "Water" | "Earth" | "Air" | "Light" | "Dark"

export type MaterialDef = {
	displayName: string,
	category: string,
	guiColor: string,
	thumbnail: string,
	description: string,
	launchEnabled: boolean,
	-- Required by launch validation; retained prototype IDs have no launch economy metadata.
	element: Element?,
	stackLimit: number?,
	buyGold: number?,
	sellGold: number?,
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
	prototypeRarityWeights: { [string]: number },
	expireSeconds: { [string]: number },
	formExpireSeconds: { [string]: number },
	defaultExpireSeconds: number,
}

-- One owned mythling, as persisted under the player document's `mythlings` section.
export type MythlingEntry = {
	typeId: string,
	variantId: string,
	claimedAt: number,
	-- Retains stand-based prototype work when a saved species adopts its permanent form ID.
	legacyPrototype: boolean?,
	level: number?,
	xp: number?,
	-- Private earned batch credit; optional only for retained prototypes, never a copied rate.
	pendingXp: number?,
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
	-- Published visual references; the authored model still supplies its rig and pivot.
	assetIds: {
		mesh: string,
		colorMap: string,
		roughnessMap: string,
		idleAnimation: string?,
		walkingAnimation: string?,
	}?,
}

export type MythlingEvolutionDefinition = { targetFormId: string, requiredLevel: number }
export type MythlingSaleDefinition = { gold: number }

-- Launch business metadata; presentation and active prototype spawning are separate concerns.
-- The dictionary key is a permanent form ID, not the unique ID of a player-owned instance.
export type MythlingFormDef = {
	element: Element,
	rarity: string,
	evolutionStage: number,
	baseYieldPerHour: number,
	captureProgressPerSecond: number,
	captureDecayPerSecond: number,
	evolution: MythlingEvolutionDefinition?,
	sale: MythlingSaleDefinition,
}

-- Retained prototype metadata, keyed by existing saved typeId; not the launch form catalogue.
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
	definitions: { [string]: EquipmentDefinition },
}

export type EquipmentFinishDef = {
	displayName: string,
	description: string,
	rarity: string,
	element: Element,
	thumbnail: string?,
	effectId: string?,
}

export type EquipmentDefinition = EquipmentProfile & {
	equipmentType: "Sword" | "Shield",
	stage: number?,
	handsRequired: number?,
	sale: { gold: number }?,
	finishes: { [string]: EquipmentFinishDef }?,
}

export type ResolvedEquipment = {
	definitionId: string,
	finishId: string?,
	displayName: string,
	description: string,
	rarity: string,
	element: Element?,
	thumbnail: string,
	profile: EquipmentDefinition,
	effectId: string?,
	sellGold: number?,
}

export type EquipmentRecipe = {
	craftingStationId: string,
	goldCost: number,
	materials: { [string]: number },
	resultDefinitionId: string,
	resultFinishId: string,
	quantity: number,
	durationSeconds: number,
}

export type ElementalSwordEffect =
	{
		element: "Fire",
		kind: "Burn",
		description: string,
		staminaPerSecond: number,
		durationSeconds: number,
	}
	| {
		element: "Water",
		kind: "Slow",
		description: string,
		walkSpeedMultiplier: number,
		durationSeconds: number,
	}
	| {
		element: "Earth",
		kind: "Root",
		description: string,
		rootSeconds: number,
		landingTimeoutSeconds: number,
		recoverySeconds: number,
	}
	| {
		element: "Air",
		kind: "Push",
		description: string,
		horizontalMultiplier: number,
	}
	| {
		element: "Light",
		kind: "Weaken",
		description: string,
		horizontalMultiplier: number,
		durationSeconds: number,
	}
	| {
		element: "Dark",
		kind: "Refund",
		description: string,
		stamina: number,
	}

export type TransactionValues = { [string]: string | number | boolean }
export type TransactionOutcome = { ok: boolean, code: string?, values: TransactionValues? }
export type TransactionRequest = {
	id: string,
	expectedRevision: number,
	operation: string,
	-- Generated by the owning server service from the validated request, never trusted from a client.
	signature: string,
}
export type TransactionResult = {
	ok: boolean,
	code: string?,
	values: TransactionValues?,
	revision: number,
	replayed: boolean?,
}
export type TransactionState = {
	revision: number,
	receipts: {
		[string]: {
			expectedRevision: number,
			operation: string,
			signature: string,
			result: TransactionResult,
		},
	},
}

export type CraftingReceipt = {
	version: number,
	recipeId: string,
	stationId: string,
	craftingStationId: string,
	startedAt: number,
	completesAt: number,
	result: { definitionId: string, finishId: string, quantity: number, instanceIds: { string } },
	paid: { gold: number, materials: { [string]: number } },
	resolvedAt: number?,
}

-- Retained reservation-only records have no receipt; never infer missing payment history.
export type CraftingJob = {
	status: "Active" | "Completed" | "Cancelled",
	reservations: { equipment: number, materials: { [string]: number } },
	receipt: CraftingReceipt?,
}

export type StartCraftingRequest = {
	requestId: string,
	expectedRevision: number,
	stationInstanceId: string,
	recipeId: string,
	expectedGoldCost: number,
	expectedMaterialId: string,
	expectedMaterialQuantity: number,
	expectedDefinitionId: string,
	expectedFinishId: string,
	expectedQuantity: number,
	expectedDurationSeconds: number,
}

export type CancelCraftingRequest = {
	requestId: string,
	expectedRevision: number,
	jobId: string,
}

export type GetCraftingStationRequest = { stationInstanceId: string }
export type CraftingRecipeView = {
	recipeId: string,
	goldCost: number,
	materialId: string,
	materialQuantity: number,
	resultDefinitionId: string,
	resultFinishId: string,
	quantity: number,
	durationSeconds: number,
	canStart: boolean,
	startCode: string?,
}
export type CraftingActiveJobView = {
	jobId: string,
	recipeId: string,
	stationInstanceId: string,
	status: "Active",
	startedAt: number,
	completesAt: number,
	remainingSeconds: number,
	completionPending: boolean,
	resultDefinitionId: string,
	resultFinishId: string,
	quantity: number,
	canCancel: boolean,
	cancelRefundGold: number,
	cancelRefundMaterials: { [string]: number },
}
export type CraftingStationView = {
	sampledAt: number,
	stationInstanceId: string,
	craftingStationId: string,
	busy: boolean,
	blockingCode: string?,
	recipes: { CraftingRecipeView },
	activeJob: CraftingActiveJobView?,
}
export type CraftingStationViewResult = {
	ok: boolean,
	code: string?,
	revision: number,
	view: CraftingStationView?,
}

export type EquipmentEntry = {
	definitionId: string,
	finishId: string?,
	isStarterGrant: boolean?,
}

export type CraftingStationRecord = { id: string, craftingStationId: string }

export type GetShrineRequest = { shrineInstanceId: string }
export type ShrineWorkerView = {
	workerId: string,
	formId: string,
	level: number,
	xp: number,
	yieldPerHour: number,
}
export type ShrineSlotView = { slotId: number, worker: ShrineWorkerView? }
export type ShrineUpgradeOffer = {
	expectedLevel: number,
	level: number,
	materialId: string,
	goldCost: number,
	materialQuantity: number,
	ownedMaterialQuantity: number,
	workerSlots: number,
	storageCapacity: number,
	canUpgrade: boolean,
	upgradeCode: string?,
}
export type ShrineView = {
	shrineInstanceId: string,
	shrineId: string,
	buildSlotId: number,
	level: number,
	maxLevel: number,
	element: Element,
	materialId: string,
	stored: number,
	storageCapacity: number,
	yieldPerHour: number,
	isProducing: boolean,
	productionProgress: number,
	estimatedSecondsToNextMaterial: number?,
	slots: { ShrineSlotView },
	availableWorkers: { ShrineWorkerView },
	collectable: number,
	canCollect: boolean,
	collectCode: string?,
	canDismantle: boolean,
	dismantleCode: string?,
	upgrade: ShrineUpgradeOffer?,
	upgradeCode: string?,
}
export type ShrineViewResult = {
	ok: boolean,
	code: string?,
	revision: number,
	view: ShrineView?,
}

export type ShrineUpgradeCost = { gold: number, materialQuantity: number }
export type ShrineLevelDef = {
	capacity: number,
	workerSlots: number,
	-- Paid when entering this level, not when leaving it. Absent at the initial level.
	upgradeCost: ShrineUpgradeCost?,
}

-- Static construction, output, and level metadata; never copied into owned Shrine records.
export type ShrineDef = {
	displayName: string,
	element: Element,
	materialId: string,
	buildGoldCost: number,
	initialLevel: number,
	maxLevel: number,
	levels: { [number]: ShrineLevelDef },
}

export type ShrineRecord = {
	id: string,
	shrineId: string,
	buildSlotId: number,
	level: number,
	-- Optional only at the legacy/load boundary; prepared schema-7 records require all four.
	stored: number?,
	progress: number?,
	newWork: number?,
	workerIdsBySlot: { [string]: string }?,
}

-- One common schedule; Shrine records never own a second independently reset clock.
export type ProductionClock = {
	lastAccruedAt: number,
	nextBatchAt: number,
	lastOnlineCheckpointAt: number?,
	offlineSince: number?,
}

export type BuildShrineRequest = {
	requestId: string,
	expectedRevision: number,
	shrineId: string,
	expectedGoldCost: number,
}

export type ExpandBaseRequest = {
	requestId: string,
	expectedRevision: number,
	expectedUpgradeCount: number,
	expectedGoldCost: number,
	expectedMaterialQuantity: number,
}

export type AssignShrineWorkerRequest = {
	requestId: string,
	expectedRevision: number,
	shrineInstanceId: string,
	slotId: number,
	workerId: string,
}

export type RemoveShrineWorkerRequest = {
	requestId: string,
	expectedRevision: number,
	shrineInstanceId: string,
	slotId: number,
	expectedWorkerId: string,
}

export type CollectShrineRequest = {
	requestId: string,
	expectedRevision: number,
	shrineInstanceId: string,
	expectedMaterialId: string,
}

export type UpgradeShrineRequest = {
	requestId: string,
	expectedRevision: number,
	shrineInstanceId: string,
	expectedLevel: number,
	expectedMaterialId: string,
	expectedGoldCost: number,
	expectedMaterialQuantity: number,
}

export type DismantleShrineRequest = {
	requestId: string,
	expectedRevision: number,
	shrineInstanceId: string,
	expectedLevel: number,
}

export type EvolveMythlingRequest = {
	requestId: string,
	expectedRevision: number,
	workerId: string,
	expectedFormId: string,
	expectedTargetFormId: string,
}

export type SellMythlingRequest = {
	requestId: string,
	expectedRevision: number,
	workerId: string,
	expectedFormId: string,
	expectedGoldValue: number,
}

export type SellEquipmentRequest = {
	requestId: string,
	expectedRevision: number,
	instanceId: string,
	expectedDefinitionId: string,
	expectedFinishId: string?,
	expectedGold: number,
}

export type EquipEquipmentRequest = {
	requestId: string,
	expectedRevision: number,
	instanceId: string,
	expectedDefinitionId: string,
	expectedFinishId: string?,
}

export type UnequipEquipmentRequest = {
	requestId: string,
	expectedRevision: number,
	slot: "PrimaryWeapon" | "Shield",
	expectedInstanceId: string,
}

export type UpgradeInventoryCapacityRequest = {
	requestId: string,
	expectedRevision: number,
	category: "materials" | "mythlings" | "equipment",
	expectedUpgradeCount: number,
	expectedGoldCost: number,
	expectedMaterialQuantity: number,
}

export type DiscardMaterialRequest = {
	requestId: string,
	expectedRevision: number,
	materialId: string,
	quantity: number,
	expectedOwnedQuantity: number,
}

export type SellMaterialRequest = DiscardMaterialRequest & {
	expectedUnitGold: number,
}

export type ShopState = {
	periodId: number,
	purchased: { [string]: number },
}

export type ShopOffer = {
	offerId: string,
	offerRevision: string,
	stockKey: string,
	kind: "Material" | "Equipment",
	materialId: string?,
	definitionId: string?,
	finishId: string?,
	unitGold: number,
	stockLimit: number,
}

export type ShopPeriod = {
	periodId: number,
	startsAt: number,
	refreshAt: number,
	featuredElement: Element,
	offers: { ShopOffer },
}

export type ShopOfferView = ShopOffer & {
	remainingStock: number,
	maxPurchasable: number,
	purchaseCode: string?,
}

export type ShopUpgradeView = {
	category: "materials" | "mythlings" | "equipment",
	purchasedUpgradeCount: number,
	capacity: number,
	maxCapacity: number,
	nextCapacity: number?,
	goldCost: number?,
	materials: { { materialId: string, quantity: number, ownedQuantity: number } },
	canPurchase: boolean,
	purchaseCode: string?,
}

export type ShopView = {
	sampledAt: number,
	periodId: number,
	startsAt: number,
	refreshAt: number,
	featuredElement: Element,
	offers: { ShopOfferView },
	upgrades: { ShopUpgradeView },
}

export type ShopViewResult = {
	ok: boolean,
	code: string?,
	revision: number,
	view: ShopView?,
}

export type BuyShopOfferRequest = {
	requestId: string,
	expectedRevision: number,
	periodId: number,
	offerId: string,
	offerRevision: string,
	quantity: number,
}

-- A fresh offer view belongs to the transport response, never the durable purchase receipt.
export type BuyShopOfferResult = {
	transaction: TransactionResult,
	shop: ShopViewResult?,
}

export type BaseRecord = {
	-- Transitional prototype ledger, independent of the new Shrine build slots.
	stands: { [string]: { production: StandProduction? } },
	-- Optional only at the load boundary and in retained prototype fixtures.
	buildSlotUpgrades: number?,
	shrines: { [string]: ShrineRecord }?,
	craftingStation: CraftingStationRecord?,
}

export type BaseStatus = {
	usedShrineSlots: number,
	unlockedShrineSlots: number,
	maxShrineSlots: number,
	craftingStation: CraftingStationRecord,
}

export type BaseShrineView = {
	id: string,
	shrineId: string,
	buildSlotId: number,
	level: number,
}
export type ShrineBuildOffer = {
	shrineId: string,
	goldCost: number,
	canBuild: boolean,
	buildCode: string?,
}
export type BaseExpansionOffer = {
	expectedUpgradeCount: number,
	goldCost: number,
	materialQuantity: number,
	nextUnlockedSlots: number,
	materials: { { materialId: string, quantity: number, ownedQuantity: number } },
	canPurchase: boolean,
	purchaseCode: string?,
}
export type BaseView = {
	status: BaseStatus,
	buildSlotUpgradeCount: number,
	shrines: { BaseShrineView },
	buildOffers: { ShrineBuildOffer },
	expansion: BaseExpansionOffer?,
	expansionCode: string?,
}
export type BaseViewResult = {
	ok: boolean,
	code: string?,
	revision: number,
	view: BaseView?,
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
	consumables: { [string]: unknown }?,
	currency: { [string]: number },
	equipment: { [string]: EquipmentEntry },
	transactions: TransactionState?,
	craftingJobs: { [string]: CraftingJob }?,
	-- Created only by a successful Shop purchase; catalogue/static limits are never saved.
	shop: ShopState?,
	-- Initialized from server time before exposure, never from a static template timestamp.
	productionClock: ProductionClock?,
	combatLoadout: {
		primaryWeaponInstanceId: string?,
		shieldInstanceId: string?,
	},
	base: BaseRecord,
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
	Admin: { Feedback: RemoteEvent },
	State: { Update: RemoteEvent, Request: RemoteFunction },
	Inventory: {
		DeleteMythling: RemoteFunction,
		EvolveMythling: RemoteFunction,
		SellMythling: RemoteFunction,
		SellEquipment: RemoteFunction,
		SellMaterial: RemoteFunction,
		DiscardMaterial: RemoteFunction,
		UpgradeCapacity: RemoteFunction,
	},
	Shop: { GetShop: RemoteFunction, BuyOffer: RemoteFunction },
	Crafting: { GetStation: RemoteFunction, StartJob: RemoteFunction, CancelJob: RemoteFunction },
	Production: { GetStatus: RemoteFunction, Collect: RemoteFunction, CollectShrine: RemoteFunction },
	Base: {
		PlaceMythling: RemoteFunction,
		RemoveMythling: RemoteFunction,
		GetBase: RemoteFunction,
		BuildShrine: RemoteFunction,
		ExpandBase: RemoteFunction,
		GetShrine: RemoteFunction,
		AssignShrineWorker: RemoteFunction,
		RemoveShrineWorker: RemoteFunction,
		UpgradeShrine: RemoteFunction,
		DismantleShrine: RemoteFunction,
	},
	Combat: {
		StartAttack: RemoteEvent,
		ReportHit: RemoteEvent,
		SetShieldGuard: RemoteEvent,
		Reaction: RemoteEvent,
		Impact: RemoteEvent,
		GetLoadout: RemoteFunction,
		Equip: RemoteFunction,
		EquipEquipment: RemoteFunction,
		UnequipEquipment: RemoteFunction,
	},
	World: { Spawned: RemoteEvent, ClaimState: RemoteEvent },
}

export type AdminCommandsConfiguration = {
	commandBurst: number,
	commandRefillPerSecond: number,
	streamTimeoutSeconds: number,
	arrivalPaddingStuds: number,
	groundProbeAboveStuds: number,
	groundProbeBelowStuds: number,
	minimumGroundNormalY: number,
	islandMarkerName: string,
	destinations: { [string]: { displayName: string, islandName: string } },
}

return {}
