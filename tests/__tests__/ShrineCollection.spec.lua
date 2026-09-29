--!strict
-- ServerStorage/Tests/__tests__/ShrineCollection.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineCollection = require(ServerScriptService.Services.ProductionService.ShrineCollection)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }
local MATERIAL_LIMITS = { 12, 24, 36 }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): ShrineCollection.Metadata
	local definitions: ShrineCollection.Metadata = { forms = {}, shrines = {} }
	for _, elementId in ELEMENTS do
		local displayElement = string.upper(string.sub(elementId, 1, 1)) .. string.sub(elementId, 2)
		definitions.forms[`test_{elementId}_form`] = {
			element = displayElement,
			baseYieldPerHour = 3_600,
		}
		definitions.shrines[`test_{elementId}_shrine`] = {
			element = displayElement,
			materialId = `test_{elementId}_material`,
			levels = {
				[1] = { capacity = 10, workerSlots = 1 },
				[2] = { capacity = 20, workerSlots = 2 },
				[3] = { capacity = 30, workerSlots = 3 },
			},
		}
	end
	return definitions
end

local function productionState(): ShrineCollection.State
	local result: ShrineCollection.State = {
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

local function inventoryState(): ShrineCollection.InventoryState
	return {
		materials = {},
		inventoryUpgrades = { materials = 0 },
		craftingJobs = {},
	}
end

local function request(elementId: string): ShrineCollection.Request
	return {
		shrineInstanceId = `shrine_{elementId}`,
		expectedMaterialId = `test_{elementId}_material`,
	}
end

local function collect(
	production: ShrineCollection.State,
	inventory: ShrineCollection.InventoryState,
	now: number,
	collectionRequest: ShrineCollection.Request,
	definitions: ShrineCollection.Metadata?
): ShrineCollection.Result
	local result, collectionError = ShrineCollection.Collect(
		production,
		inventory,
		now,
		collectionRequest,
		definitions or metadata()
	)
	assert(
		result,
		`[ShrineCollection.spec] Expected collection success: {tostring(collectionError)}`
	)
	expect(collectionError).toBeNil()
	return result
end

local function expectRejected(
	production: ShrineCollection.State,
	inventory: ShrineCollection.InventoryState,
	now: number,
	collectionRequest: any,
	expectedCode: string,
	definitions: ShrineCollection.Metadata?
)
	local productionBefore = copy(production)
	local inventoryBefore = copy(inventory)
	local result, collectionError = ShrineCollection.Collect(
		production,
		inventory,
		now,
		collectionRequest,
		definitions or metadata()
	)
	expect(result).toBeNil()
	expect(collectionError).toBe(expectedCode)
	expect(production).toEqual(productionBefore)
	expect(inventory).toEqual(inventoryBefore)
end

local function fillMaterialSlots(inventory: ShrineCollection.InventoryState, count: number)
	for index = 1, count do
		inventory.materials[`test_filler_{index}`] = { total = 1_000 }
	end
end

local function inventoryAfter(
	prior: ShrineCollection.InventoryState,
	materials: { [string]: Types.MaterialEntry }
): ShrineCollection.InventoryState
	return {
		materials = materials,
		inventoryUpgrades = prior.inventoryUpgrades,
		craftingJobs = prior.craftingJobs,
	}
end

describe("ShrineCollection", function()
	it("collects each of the six configured synthetic Materials as whole quantities", function()
		for _, elementId in ELEMENTS do
			local production = productionState()
			local inventory = inventoryState()
			local shrineInstanceId = `shrine_{elementId}`
			local materialId = `test_{elementId}_material`
			production.shrines[shrineInstanceId].stored = 5

			local result = collect(production, inventory, 0, request(elementId))

			expect(result.shrineInstanceId).toBe(shrineInstanceId)
			expect(result.materialId).toBe(materialId)
			expect(result.collected).toBe(5)
			expect(result.remaining).toBe(0)
			expect(result.production.shrines[shrineInstanceId].stored).toBe(0)
			expect(result.materials).toEqual({ [materialId] = { total = 5 } })
			expect(production.shrines[shrineInstanceId].stored).toBe(5)
			expect(inventory.materials).toEqual({})
		end
	end)

	it("partially collects only compatible 1,000-unit stack room", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 5
		local inventory = inventoryState()
		inventory.materials.test_fire_material = { total = 999 }
		fillMaterialSlots(inventory, 11)

		local result = collect(production, inventory, 0, request("fire"))

		expect(result.collected).toBe(1)
		expect(result.remaining).toBe(4)
		expect(result.materials.test_fire_material.total).toBe(1_000)
		expect(result.production.shrines.shrine_fire.stored).toBe(4)
	end)

	it("keeps different Material stacks separate when every slot is occupied", function()
		local production = productionState()
		production.shrines.shrine_water.stored = 1
		local inventory = inventoryState()
		inventory.materials.test_fire_material = { total = 999 }
		fillMaterialSlots(inventory, 11)

		expectRejected(production, inventory, 0, request("water"), "InventoryFull")
	end)

	it(
		"honors matching and other-type Active refund reservations without consuming them",
		function()
			local matchingProduction = productionState()
			matchingProduction.shrines.shrine_fire.stored = 100
			local matchingInventory = inventoryState()
			matchingInventory.materials.test_fire_material = { total = 200 }
			fillMaterialSlots(matchingInventory, 11)
			matchingInventory.craftingJobs = {
				active = {
					status = "Active",
					reservations = {
						equipment = 0,
						materials = { test_fire_material = 750 },
					},
				},
			}
			local matchingJobsBefore = copy(matchingInventory.craftingJobs)

			local matching = collect(matchingProduction, matchingInventory, 0, request("fire"))

			expect(matching.collected).toBe(50)
			expect(matching.remaining).toBe(50)
			expect(matching.materials.test_fire_material.total).toBe(250)
			expect(matchingInventory.craftingJobs).toEqual(matchingJobsBefore)

			local otherProduction = productionState()
			otherProduction.shrines.shrine_fire.stored = 1_500
			local otherInventory = inventoryState()
			fillMaterialSlots(otherInventory, 10)
			otherInventory.craftingJobs = {
				active = {
					status = "Active",
					reservations = {
						equipment = 0,
						materials = { test_water_material = 1_000 },
					},
				},
			}
			local otherJobsBefore = copy(otherInventory.craftingJobs)

			local other = collect(otherProduction, otherInventory, 0, request("fire"))

			expect(other.collected).toBe(1_000)
			expect(other.remaining).toBe(500)
			expect(other.materials.test_fire_material.total).toBe(1_000)
			expect(otherInventory.craftingJobs).toEqual(otherJobsBefore)
		end
	)

	it("ignores Completed and Cancelled reservations while preserving their records", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 1_000
		local inventory = inventoryState()
		fillMaterialSlots(inventory, 11)
		inventory.craftingJobs = {
			completed = {
				status = "Completed",
				reservations = {
					equipment = 100,
					materials = { test_fire_material = 100_000 },
				},
			},
			cancelled = {
				status = "Cancelled",
				reservations = {
					equipment = 100,
					materials = { test_water_material = 100_000 },
				},
			},
		}
		local jobsBefore = copy(inventory.craftingJobs)

		local result = collect(production, inventory, 0, request("fire"))

		expect(result.collected).toBe(1_000)
		expect(result.remaining).toBe(0)
		expect(inventory.craftingJobs).toEqual(jobsBefore)
	end)

	it("uses all three purchased Material-capacity tiers", function()
		for upgradeLevel, limit in MATERIAL_LIMITS do
			local production = productionState()
			production.shrines.shrine_fire.stored = 1_500
			local inventory = inventoryState()
			inventory.inventoryUpgrades = { materials = upgradeLevel - 1 }
			fillMaterialSlots(inventory, limit - 1)

			local result = collect(production, inventory, 0, request("fire"))

			expect(result.collected).toBe(1_000)
			expect(result.remaining).toBe(500)
			expect(result.materials.test_fire_material.total).toBe(1_000)
		end
	end)

	it("rejects malformed, stale, unknown, and changed-output requests without mutation", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 5
		local inventory = inventoryState()
		expectRejected(production, inventory, 0, nil, "InvalidRequest")
		expectRejected(production, inventory, 0, "collect", "InvalidRequest")
		expectRejected(production, inventory, 0, {
			shrineInstanceId = "shrine_fire",
			expectedMaterialId = "test_fire_material",
			extra = true,
		}, "InvalidRequest")
		expectRejected(production, inventory, 0, {
			shrineInstanceId = "missing_shrine",
			expectedMaterialId = "test_fire_material",
		}, "ShrineNotOwned")
		expectRejected(production, inventory, 0, {
			shrineInstanceId = "shrine_fire",
			expectedMaterialId = "stale_material",
		}, "MaterialChanged")

		local backdated = productionState()
		backdated.lastAccruedAt = 10
		backdated.nextBatchAt = 11
		backdated.shrines.shrine_fire.stored = 5
		expectRejected(backdated, inventory, 9, request("fire"), "BackdatedChange")

		local malformedState = productionState()
		malformedState.shrines.shrine_fire.progress = -0.1
		expectRejected(malformedState, inventory, 0, request("fire"), "InvalidShrine")
	end)

	it("propagates strict Inventory-state, reservation, and upgrade validation", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 5

		local invalidOwned = inventoryState()
		invalidOwned.materials.test_fire_material = { total = 0.5 }
		expectRejected(production, invalidOwned, 0, request("fire"), "InvalidInventoryState")

		local invalidReservations = inventoryState()
		invalidReservations.craftingJobs = {
			bad = {
				status = "Active",
				reservations = { equipment = 0.5, materials = { test_fire_material = 1 } },
			},
		}
		expectRejected(production, invalidReservations, 0, request("fire"), "InvalidReservations")

		local invalidUpgrade = inventoryState()
		invalidUpgrade.inventoryUpgrades = { materials = 1.5 }
		expectRejected(production, invalidUpgrade, 0, request("fire"), "InvalidInventoryUpgrade")
	end)

	it("reports NothingToCollect before InventoryFull for only fractional work", function()
		local production = productionState()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		local inventory = inventoryState()
		fillMaterialSlots(inventory, 12)

		expectRejected(production, inventory, 0.5, request("fire"), "NothingToCollect")

		local completed = productionState()
		completed.shrines.shrine_fire.stored = 1
		expectRejected(completed, inventory, 0, request("fire"), "InventoryFull")
	end)

	it("grants the batch-filling XP before transfer without awarding XP for collection", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 9
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"

		local result = collect(production, inventoryState(), 1, request("fire"))

		expect(result.collected).toBe(10)
		expect(result.remaining).toBe(0)
		expect(result.production.shrines.shrine_fire.stored).toBe(0)
		expect(result.production.shrines.shrine_fire.progress).toBe(0)
		expect(result.production.shrines.shrine_fire.newWork).toBe(0)
		expect(result.production.workers.worker_fire.xp).toBe(1)
		expect(result.production.workers.worker_fire.pendingXp).toBe(0)
		expect(result.production.lastAccruedAt).toBe(1)
		expect(result.production.nextBatchAt).toBe(2)
	end)

	it("resumes at collection time after a full pause without backfilling", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 10
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		local inventory = inventoryState()

		local emptied = collect(production, inventory, 10, request("fire"))
		expect(emptied.collected).toBe(10)
		expect(emptied.production.workers.worker_fire.xp).toBe(0)
		expect(emptied.production.lastAccruedAt).toBe(10)
		local updatedInventory = inventoryAfter(inventory, emptied.materials)

		local afterOneSecond = collect(emptied.production, updatedInventory, 11, request("fire"))
		expect(afterOneSecond.collected).toBe(1)
		expect(afterOneSecond.materials.test_fire_material.total).toBe(11)
		expect(afterOneSecond.production.workers.worker_fire.xp).toBe(1)
	end)

	it("settles unrelated Shrines and workers in the same pre-collection pass", function()
		local production = productionState()
		production.shrines.shrine_water.stored = 2
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"

		local result = collect(production, inventoryState(), 1, request("water"))

		expect(result.collected).toBe(2)
		expect(result.production.shrines.shrine_water.stored).toBe(0)
		expect(result.production.shrines.shrine_fire.stored).toBe(1)
		expect(result.production.workers.worker_fire.xp).toBe(1)
		expect(result.production.lastAccruedAt).toBe(1)
		expect(result.production.nextBatchAt).toBe(2)
	end)

	it("a same-timestamp repeat cannot collect or produce twice", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 2
		local inventory = inventoryState()
		local first = collect(production, inventory, 0, request("fire"))
		local updatedInventory = inventoryAfter(inventory, first.materials)

		expectRejected(first.production, updatedInventory, 0, request("fire"), "NothingToCollect")
		expect(first.materials.test_fire_material.total).toBe(2)
	end)

	it("resumes identically from a JSON roundtrip of a mid-batch collection result", function()
		local production = productionState()
		production.shrines.shrine_fire.stored = 5
		production.shrines.shrine_fire.progress = 0.25
		production.shrines.shrine_fire.newWork = 0.125
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.workers.worker_fire.pendingXp = 0.5
		local inventory = inventoryState()

		local midway = collect(production, inventory, 0.5, request("fire"))
		local uninterruptedInventory = inventoryAfter(inventory, midway.materials)
		local uninterrupted = collect(midway.production, uninterruptedInventory, 1, request("fire"))
		local serializedProduction = copy(midway.production)
		local serializedInventory = copy(uninterruptedInventory)
		local resumed = collect(serializedProduction, serializedInventory, 1, request("fire"))

		expect(resumed).toEqual(uninterrupted)
		expect(resumed.collected).toBe(1)
		expect(resumed.production.shrines.shrine_fire.progress).toBe(0.375)
		expect(resumed.production.workers.worker_fire.xp).toBe(1.5)
	end)

	it(
		"preserves accounting and inventory metadata while returning detached JSON-safe state",
		function()
			local production = productionState()
			production.shrines.shrine_fire.stored = 5
			production.shrines.shrine_fire.progress = 0.25
			production.shrines.shrine_fire.newWork = 0.125
			production.workers.worker_fire.pendingXp = 0.5
			local inventory = inventoryState()
			inventory.materials.test_water_material = { total = 3 }
			inventory.inventoryUpgrades = { materials = 1 }
			inventory.craftingJobs = {
				completed = {
					status = "Completed",
					reservations = { equipment = 0, materials = { test_fire_material = 5 } },
				},
			}
			local definitions = metadata()
			local productionBefore = copy(production)
			local inventoryBefore = copy(inventory)
			local metadataBefore = copy(definitions)
			FreezeUtil.DeepFreeze(production)
			FreezeUtil.DeepFreeze(inventory)
			FreezeUtil.DeepFreeze(definitions)

			local result = collect(production, inventory, 0, request("fire"), definitions)

			expect(production).toEqual(productionBefore)
			expect(inventory).toEqual(inventoryBefore)
			expect(definitions).toEqual(metadataBefore)
			expect(result.production.shrines.shrine_fire.progress).toBe(0.25)
			expect(result.production.shrines.shrine_fire.newWork).toBe(0.125)
			expect(result.production.workers.worker_fire.pendingXp).toBe(0.5)
			expect(result.production.lastAccruedAt).toBe(0)
			expect(result.production.nextBatchAt).toBe(1)
			expect(result.materials).toEqual({
				test_water_material = { total = 3 },
				test_fire_material = { total = 5 },
			})
			expect(result.production).never.toBe(production)
			expect(result.materials).never.toBe(inventory.materials)
			expect(result.materials.test_water_material).never.toBe(
				inventory.materials.test_water_material
			)
			expect(HttpService:JSONDecode(HttpService:JSONEncode(result))).toEqual(result)
			result.materials.test_water_material.total = 4
			expect(inventory.materials.test_water_material.total).toBe(3)

			local dynamicResult = (result :: unknown) :: { [string]: any }
			local dynamicProduction = (result.production :: unknown) :: { [string]: any }
			expect(dynamicResult.inventoryUpgrades).toBeNil()
			expect(dynamicResult.craftingJobs).toBeNil()
			expect(dynamicProduction.stands).toBeNil()
			expect(dynamicProduction.craftingStation).toBeNil()
		end
	)
end)
