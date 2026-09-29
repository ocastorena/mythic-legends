--!strict
-- ServerStorage/Tests/__tests__/ShrineUpgrades.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local ShrineConfiguration = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineUpgrades = require(ServerScriptService.Services.BaseService.ShrineUpgrades)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): ShrineUpgrades.Metadata
	local definitions: ShrineUpgrades.Metadata = { forms = {}, shrines = {} }
	for _, elementId in ELEMENTS do
		local shrineId = `{elementId}_shrine`
		local configured = ShrineConfiguration[shrineId]
		local levels: { [number]: Types.ShrineLevelDef } = {}
		for level, definition in configured.levels do
			levels[level] = {
				capacity = definition.capacity,
				workerSlots = definition.workerSlots,
				upgradeCost = if definition.upgradeCost
					then table.clone(definition.upgradeCost)
					else nil,
			}
		end
		definitions.forms[`test_{elementId}_form`] = {
			element = configured.element,
			baseYieldPerHour = 3_600,
		}
		definitions.shrines[`test_{elementId}_shrine`] = {
			element = configured.element,
			materialId = `test_{elementId}_material`,
			maxLevel = configured.maxLevel,
			levels = levels,
		}
	end
	return definitions
end

local function accountingMetadata(definitions: ShrineUpgrades.Metadata): ShrineAccrual.Metadata
	local accounting: ShrineAccrual.Metadata = { forms = definitions.forms, shrines = {} }
	for id, definition in definitions.shrines do
		accounting.shrines[id] = definition
	end
	return accounting
end

local function state(): ShrineUpgrades.State
	local result: ShrineUpgrades.State = {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		shrines = {},
		workers = {},
	}
	for _, elementId in ELEMENTS do
		result.shrines[`shrine_{elementId}`] = {
			shrineId = `test_{elementId}_shrine`,
			level = 1,
			workerIdsBySlot = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}
		result.workers[`worker_{elementId}`] = {
			formId = `test_{elementId}_form`,
			level = 1,
			xp = 0,
			pendingXp = 0,
		}
	end
	return result
end

local function resources(
	elementId: string,
	gold: number,
	materialQuantity: number
): ShrineUpgrades.Resources
	local materials: { [string]: Types.MaterialEntry } = {}
	if materialQuantity > 0 then
		materials[`test_{elementId}_material`] = { total = materialQuantity }
	end
	return {
		gold = gold,
		materials = materials,
		inventoryUpgrades = { materials = 0 },
		craftingJobs = {},
	}
end

local function request(elementId: string, expectedLevel: number): ShrineUpgrades.Request
	local definition = ShrineConfiguration[`{elementId}_shrine`]
	local nextLevel = definition.levels[expectedLevel + 1]
	local cost = if nextLevel then nextLevel.upgradeCost else nil
	return {
		shrineInstanceId = `shrine_{elementId}`,
		expectedLevel = expectedLevel,
		expectedMaterialId = `test_{elementId}_material`,
		expectedGoldCost = if cost then cost.gold else 0,
		expectedMaterialQuantity = if cost then cost.materialQuantity else 0,
	}
end

local function upgrade(
	production: ShrineUpgrades.State,
	owned: ShrineUpgrades.Resources,
	now: number,
	upgradeRequest: ShrineUpgrades.Request,
	definitions: ShrineUpgrades.Metadata?
): ShrineUpgrades.Result
	local result, upgradeError =
		ShrineUpgrades.Upgrade(production, owned, now, upgradeRequest, definitions or metadata())
	assert(result, `[ShrineUpgrades.spec] Expected upgrade success: {tostring(upgradeError)}`)
	expect(upgradeError).toBeNil()
	return result
end

local function expectRejected(
	production: ShrineUpgrades.State,
	owned: ShrineUpgrades.Resources,
	now: number,
	upgradeRequest: any,
	expectedCode: string,
	definitions: ShrineUpgrades.Metadata?
)
	local productionBefore = copy(production)
	local resourcesBefore = copy(owned)
	local result, upgradeError =
		ShrineUpgrades.Upgrade(production, owned, now, upgradeRequest, definitions or metadata())
	expect(result).toBeNil()
	expect(upgradeError).toBe(expectedCode)
	expect(production).toEqual(productionBefore)
	expect(owned).toEqual(resourcesBefore)
end

local function resourcesAfter(
	prior: ShrineUpgrades.Resources,
	result: ShrineUpgrades.Result
): ShrineUpgrades.Resources
	return {
		gold = result.gold,
		materials = result.materials,
		inventoryUpgrades = prior.inventoryUpgrades,
		craftingJobs = prior.craftingJobs,
	}
end

local function accrue(
	input: ShrineUpgrades.State,
	now: number,
	definitions: ShrineUpgrades.Metadata
): ShrineUpgrades.State
	local result, accrualError = ShrineAccrual.Accrue(input, now, accountingMetadata(definitions))
	assert(result, `[ShrineUpgrades.spec] Expected accrual success: {tostring(accrualError)}`)
	return result
end

describe("ShrineUpgrades", function()
	it(
		"keeps the approved three-level prices, capacities, slots, and pre-upgrade fit for all six elements",
		function()
			for _, elementId in ELEMENTS do
				local definition = ShrineConfiguration[`{elementId}_shrine`]
				expect(definition.maxLevel).toBe(3)
				expect(definition.levels[1]).toEqual({ capacity = 300, workerSlots = 1 })
				expect(definition.levels[2]).toEqual({
					capacity = 1_200,
					workerSlots = 2,
					upgradeCost = { gold = 1_000, materialQuantity = 400 },
				})
				expect(definition.levels[3]).toEqual({
					capacity = 3_600,
					workerSlots = 3,
					upgradeCost = { gold = 15_000, materialQuantity = 4_000 },
				})
				for targetLevel = 2, 3 do
					local cost = definition.levels[targetLevel].upgradeCost
					assert(cost, "[ShrineUpgrades.spec] Expected configured upgrade cost")
					local quantity = cost.materialQuantity
					local slots = math.ceil(quantity / Inventory.materialStackLimit)
					expect(slots <= Inventory.capacityByCategory.materials[1]).toBe(true)
				end
			end
		end
	)

	it("upgrades every element from level 1 to 2 with exact configured payment", function()
		for _, elementId in ELEMENTS do
			local production = state()
			production.shrines[`shrine_{elementId}`].workerIdsBySlot["1"] = `worker_{elementId}`
			local owned = resources(elementId, 1_000, 400)
			owned.materials.test_unrelated_material = { total = 17 }

			local result = upgrade(production, owned, 0, request(elementId, 1))

			expect(result.previousLevel).toBe(1)
			expect(result.level).toBe(2)
			expect(result.goldSpent).toBe(1_000)
			expect(result.materialsSpent).toBe(400)
			expect(result.gold).toBe(0)
			expect(result.materialId).toBe(`test_{elementId}_material`)
			expect(result.materials[`test_{elementId}_material`]).toBeNil()
			expect(result.materials.test_unrelated_material.total).toBe(17)
			expect(result.production.shrines[`shrine_{elementId}`].workerIdsBySlot).toEqual({
				["1"] = `worker_{elementId}`,
			})
			expect(result.production.shrines[`shrine_{elementId}`].workerIdsBySlot["2"]).toBeNil()
			expect(production.shrines[`shrine_{elementId}`].level).toBe(1)
			expect(owned.gold).toBe(1_000)
		end
	end)

	it(
		"supports both sequential transitions, rejects stale replay, and stops at max level",
		function()
			local production = state()
			local owned = resources("fire", 16_000, 4_400)
			local firstRequest = request("fire", 1)
			local first = upgrade(production, owned, 0, firstRequest)
			local afterFirst = resourcesAfter(owned, first)

			expectRejected(first.production, afterFirst, 0, firstRequest, "LevelChanged")
			local second = upgrade(first.production, afterFirst, 0, request("fire", 2))
			expect(second.previousLevel).toBe(2)
			expect(second.level).toBe(3)
			expect(second.goldSpent).toBe(15_000)
			expect(second.materialsSpent).toBe(4_000)
			expect(second.gold).toBe(0)
			expect(second.materials.test_fire_material).toBeNil()
			expectRejected(
				second.production,
				resourcesAfter(afterFirst, second),
				0,
				request("fire", 3),
				"MaxLevel"
			)
		end
	)

	it(
		"rejects malformed, backdated, unowned, stale-level, material, and price requests",
		function()
			local production = state()
			local owned = resources("fire", 1_000, 400)
			expectRejected(production, owned, 0, nil, "InvalidRequest")
			expectRejected(production, owned, 0, "upgrade", "InvalidRequest")
			local extra = request("fire", 1) :: any
			extra.targetLevel = 3
			expectRejected(production, owned, 0, extra, "InvalidRequest")
			local withMetatable = request("fire", 1) :: any
			setmetatable(withMetatable, {})
			expectRejected(production, owned, 0, withMetatable, "InvalidRequest")

			local missing = request("fire", 1)
			missing.shrineInstanceId = "missing_shrine"
			expectRejected(production, owned, 0, missing, "ShrineNotOwned")
			expectRejected(production, owned, 0, request("fire", 2), "LevelChanged")
			local changedMaterial = request("fire", 1)
			changedMaterial.expectedMaterialId = "stale_material"
			expectRejected(production, owned, 0, changedMaterial, "MaterialChanged")
			local changedGold = request("fire", 1)
			changedGold.expectedGoldCost += 1
			expectRejected(production, owned, 0, changedGold, "PriceChanged")
			local changedQuantity = request("fire", 1)
			changedQuantity.expectedMaterialQuantity += 1
			expectRejected(production, owned, 0, changedQuantity, "PriceChanged")

			local backdated = state()
			backdated.lastAccruedAt = 10
			backdated.nextBatchAt = 11
			expectRejected(backdated, owned, 9, request("fire", 1), "BackdatedChange")
			local invalidState = state()
			invalidState.shrines.shrine_fire.progress = -0.1
			expectRejected(invalidState, owned, 0, request("fire", 1), "InvalidShrine")
		end
	)

	it("rejects every malformed part of the configured upgrade path", function()
		local production = state()
		local owned = resources("fire", 1_000, 400)
		local cases: { ShrineUpgrades.Metadata } = {}

		local missingLevel = metadata()
		missingLevel.shrines.test_fire_shrine.levels[3] = nil
		table.insert(cases, missingLevel)
		local wrongMaximum = metadata()
		wrongMaximum.shrines.test_fire_shrine.maxLevel = 4
		table.insert(cases, wrongMaximum)
		local costAtLevelOne = metadata()
		costAtLevelOne.shrines.test_fire_shrine.levels[1].upgradeCost = {
			gold = 1,
			materialQuantity = 1,
		}
		table.insert(cases, costAtLevelOne)
		local nonIncreasingCapacity = metadata()
		nonIncreasingCapacity.shrines.test_fire_shrine.levels[2].capacity = 300
		table.insert(cases, nonIncreasingCapacity)
		local wrongSlots = metadata()
		wrongSlots.shrines.test_fire_shrine.levels[2].workerSlots = 3
		table.insert(cases, wrongSlots)
		local freeTarget = metadata()
		local freeTargetCost = freeTarget.shrines.test_fire_shrine.levels[2].upgradeCost
		assert(freeTargetCost, "[ShrineUpgrades.spec] Expected level-2 cost fixture")
		freeTargetCost.gold = 0
		table.insert(cases, freeTarget)
		local extraLevel = metadata()
		extraLevel.shrines.test_fire_shrine.levels[4] = {
			capacity = 7_200,
			workerSlots = 4,
			upgradeCost = { gold = 1, materialQuantity = 1 },
		}
		table.insert(cases, extraLevel)

		for _, definitions in cases do
			expectRejected(
				production,
				owned,
				0,
				request("fire", 1),
				"InvalidUpgradeConfiguration",
				definitions
			)
		end
	end)

	it("validates Inventory records, currency, and affordability before settlement", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"

		local invalidInventory = resources("fire", 1_000, 400)
		invalidInventory.materials.test_fire_material.total = 399.5
		expectRejected(
			production,
			invalidInventory,
			10,
			request("fire", 1),
			"InvalidInventoryState"
		)
		local invalidReservations = resources("fire", 1_000, 400)
		invalidReservations.craftingJobs = {
			bad = {
				status = "Active",
				reservations = { equipment = 0.5, materials = {} },
			},
		}
		expectRejected(
			production,
			invalidReservations,
			10,
			request("fire", 1),
			"InvalidReservations"
		)
		local invalidUpgrade = resources("fire", 1_000, 400)
		invalidUpgrade.inventoryUpgrades = { materials = 1.5 }
		expectRejected(
			production,
			invalidUpgrade,
			10,
			request("fire", 1),
			"InvalidInventoryUpgrade"
		)
		for _, badGold in { -1, 0.5, math.huge, 0 / 0 } do
			local invalidGold = resources("fire", 1_000, 400)
			invalidGold.gold = badGold
			expectRejected(production, invalidGold, 10, request("fire", 1), "InvalidCurrency")
		end
		local missingGold = resources("fire", 1_000, 400)
		local dynamicMissingGold = missingGold :: any
		dynamicMissingGold.gold = nil
		expectRejected(production, missingGold, 10, request("fire", 1), "InvalidCurrency")
		expectRejected(
			production,
			resources("fire", 999, 400),
			10,
			request("fire", 1),
			"InsufficientGold"
		)
		expectRejected(
			production,
			resources("fire", 1_000, 399),
			10,
			request("fire", 1),
			"InsufficientMaterials"
		)
	end)

	it("spends owned Materials without consuming output or matching refund reservations", function()
		local outputOnly = state()
		outputOnly.shrines.shrine_fire.stored = 400
		expectRejected(
			outputOnly,
			resources("fire", 1_000, 0),
			0,
			request("fire", 1),
			"InsufficientMaterials"
		)

		local reservationOnly = resources("fire", 1_000, 0)
		reservationOnly.craftingJobs = {
			active = {
				status = "Active",
				reservations = {
					equipment = 0,
					materials = { test_fire_material = 400 },
				},
			},
		}
		expectRejected(state(), reservationOnly, 0, request("fire", 1), "InsufficientMaterials")

		local owned = resources("fire", 1_000, 400)
		owned.craftingJobs = copy(reservationOnly.craftingJobs)
		local jobsBefore = copy(owned.craftingJobs)
		local result = upgrade(state(), owned, 0, request("fire", 1))
		expect(result.materials.test_fire_material).toBeNil()
		expect(owned.craftingJobs).toEqual(jobsBefore)
		expect(owned.materials.test_fire_material.total).toBe(400)
	end)

	it("rolls back payment and level changes if detached accrual cannot complete", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.workers.worker_fire.pendingXp = 2 ^ 53 - 1
		expectRejected(
			production,
			resources("fire", 1_000, 400),
			1,
			request("fire", 1),
			"ArithmeticOverflow"
		)
	end)

	it("settles mid-batch work under the old level while preserving accounting", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.shrines.shrine_fire.stored = 10
		production.shrines.shrine_fire.progress = 0.25
		production.shrines.shrine_fire.newWork = 0.125
		production.workers.worker_fire.pendingXp = 0.5

		local result = upgrade(production, resources("fire", 1_000, 400), 0.5, request("fire", 1))

		local shrine = result.production.shrines.shrine_fire
		expect(shrine.level).toBe(2)
		expect(shrine.stored).toBe(10)
		expect(shrine.progress).toBe(0.25)
		expect(shrine.newWork).toBe(0.625)
		expect(shrine.workerIdsBySlot).toEqual({ ["1"] = "worker_fire" })
		expect(shrine.workerIdsBySlot["2"]).toBeNil()
		expect(result.production.workers.worker_fire.xp).toBe(0)
		expect(result.production.workers.worker_fire.pendingXp).toBe(1)
		expect(result.production.lastAccruedAt).toBe(0.5)
		expect(result.production.nextBatchAt).toBe(1)
	end)

	it("resumes only after a mid-batch full-storage upgrade without backfilling", function()
		local production = state()
		production.shrines.shrine_fire.stored = 300
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		local owned = resources("fire", 16_000, 4_400)

		local first = upgrade(production, owned, 0.5, request("fire", 1))
		expect(first.production.workers.worker_fire.xp).toBe(0)
		expect(first.production.lastAccruedAt).toBe(0.5)
		local second =
			upgrade(first.production, resourcesAfter(owned, first), 1, request("fire", 2))
		expect(second.production.shrines.shrine_fire.stored).toBe(300)
		expect(second.production.shrines.shrine_fire.progress).toBe(0.5)
		expect(second.production.workers.worker_fire.xp).toBe(0.5)
	end)

	it("discards the batch overflow that filled old capacity before increasing it", function()
		local production = state()
		production.shrines.shrine_fire.stored = 299
		production.shrines.shrine_fire.progress = 0.75
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"

		local result = upgrade(production, resources("fire", 1_000, 400), 10, request("fire", 1))

		expect(result.production.shrines.shrine_fire.level).toBe(2)
		expect(result.production.shrines.shrine_fire.stored).toBe(300)
		expect(result.production.shrines.shrine_fire.progress).toBe(0)
		expect(result.production.shrines.shrine_fire.newWork).toBe(0)
		expect(result.production.workers.worker_fire.xp).toBe(1)
	end)

	it("settles unrelated Shrines and workers in the same old-state pass", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"

		local result = upgrade(production, resources("fire", 1_000, 400), 1, request("fire", 1))

		expect(result.production.shrines.shrine_fire.stored).toBe(1)
		expect(result.production.shrines.shrine_water.stored).toBe(1)
		expect(result.production.workers.worker_fire.xp).toBe(1)
		expect(result.production.workers.worker_water.xp).toBe(1)
	end)

	it("matches online settlement and offline settlement, then resumes from real JSON", function()
		local definitions = metadata()
		local initial = state()
		initial.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		local owned = resources("fire", 16_000, 4_400)

		local onlineState = copy(initial)
		for second = 1, 10 do
			onlineState = accrue(onlineState, second, definitions)
		end
		local online = upgrade(onlineState, copy(owned), 10.5, request("fire", 1), definitions)
		local offline = upgrade(copy(initial), copy(owned), 10.5, request("fire", 1), definitions)
		expect(offline).toEqual(online)
		expect(offline.production.shrines.shrine_fire.newWork).toBe(0.5)
		expect(offline.production.workers.worker_fire.pendingXp).toBe(0.5)

		local nextResources = resourcesAfter(owned, offline)
		local uninterrupted =
			upgrade(offline.production, nextResources, 20.25, request("fire", 2), definitions)
		local restoredProduction = copy(offline.production)
		local restoredResources = copy(nextResources)
		local restoredMetadata = copy(definitions)
		local resumed = upgrade(
			restoredProduction,
			restoredResources,
			20.25,
			request("fire", 2),
			restoredMetadata
		)
		expect(resumed).toEqual(uninterrupted)
		expect(resumed.production.shrines.shrine_fire.stored).toBe(20)
		expect(resumed.production.workers.worker_fire.xp).toBe(20)
		expect(resumed.production.shrines.shrine_fire.newWork).toBe(0.25)
		expect(resumed.production.workers.worker_fire.pendingXp).toBe(0.25)
	end)

	it("accepts frozen inputs and returns detached plain serializable output", function()
		local production = state()
		local owned = resources("fire", 1_000, 400)
		owned.materials.test_water_material = { total = 7 }
		owned.craftingJobs = {
			completed = {
				status = "Completed",
				reservations = { equipment = 0, materials = { test_fire_material = 5 } },
			},
		}
		local definitions = metadata()
		local productionBefore = copy(production)
		local resourcesBefore = copy(owned)
		local metadataBefore = copy(definitions)
		FreezeUtil.DeepFreeze(production)
		FreezeUtil.DeepFreeze(owned)
		FreezeUtil.DeepFreeze(definitions)

		local result = upgrade(production, owned, 0, request("fire", 1), definitions)

		expect(production).toEqual(productionBefore)
		expect(owned).toEqual(resourcesBefore)
		expect(definitions).toEqual(metadataBefore)
		expect(result.production).never.toBe(production)
		expect(result.materials).never.toBe(owned.materials)
		expect(result.materials.test_water_material).never.toBe(owned.materials.test_water_material)
		expect(HttpService:JSONDecode(HttpService:JSONEncode(result))).toEqual(result)
		result.materials.test_water_material.total = 8
		expect(owned.materials.test_water_material.total).toBe(7)

		local dynamicResult = (result :: unknown) :: { [string]: any }
		expect(dynamicResult.inventoryUpgrades).toBeNil()
		expect(dynamicResult.craftingJobs).toBeNil()
		expect(dynamicResult.targetLevel).toBeNil()
	end)
end)
