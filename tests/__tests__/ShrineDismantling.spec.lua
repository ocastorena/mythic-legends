--!strict
-- ServerStorage/Tests/__tests__/ShrineDismantling.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local ShrineConfiguration = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseState = require(ServerScriptService.Shared.BaseState)
local ShrineDismantling = require(ServerScriptService.Services.BaseService.ShrineDismantling)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): ShrineAccrual.Metadata
	local definitions: ShrineAccrual.Metadata = { forms = {}, shrines = {} }
	for _, elementId in ELEMENTS do
		local shrineId = `{elementId}_shrine`
		local configured = ShrineConfiguration[shrineId]
		definitions.forms[`test_{elementId}_form`] = {
			element = configured.element,
			baseYieldPerHour = 3_600,
		}
		definitions.shrines[shrineId] = {
			element = configured.element,
			materialId = `test_{elementId}_material`,
			levels = configured.levels,
		}
	end
	return definitions
end

local function fixture(count: number?): (ShrineAccrual.State, Types.BaseRecord)
	local production: ShrineAccrual.State = {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		shrines = {},
		workers = {},
	}
	local built: { [string]: Types.ShrineRecord } = {}
	for index, elementId in ELEMENTS do
		production.workers[`worker_{elementId}`] = {
			formId = `test_{elementId}_form`,
			level = 1,
			xp = 0,
			pendingXp = 0,
		}
		if index <= (count or #ELEMENTS) then
			local instanceId = `shrine_{elementId}`
			production.shrines[instanceId] = {
				shrineId = `{elementId}_shrine`,
				level = 1,
				workerIdsBySlot = {},
				stored = 0,
				progress = 0,
				newWork = 0,
			}
			built[instanceId] = {
				id = instanceId,
				shrineId = `{elementId}_shrine`,
				buildSlotId = index,
				level = 1,
			}
		end
	end
	return production,
		{
			stands = { retained_prototype = {} },
			buildSlotUpgrades = math.max(0, (count or #ELEMENTS) - 2),
			shrines = built,
			craftingStation = {
				id = "permanent_station",
				craftingStationId = Bases.craftingStationId,
			},
		}
end

local function request(elementId: string?, expectedLevel: number?): ShrineDismantling.Request
	return {
		shrineInstanceId = `shrine_{elementId or "fire"}`,
		expectedLevel = expectedLevel or 1,
	}
end

local function dismantle(
	production: ShrineAccrual.State,
	base: Types.BaseRecord,
	now: number,
	dismantleRequest: ShrineDismantling.Request?,
	definitions: ShrineAccrual.Metadata?
): ShrineDismantling.Result
	local result, dismantleError = ShrineDismantling.Dismantle(
		production,
		base,
		now,
		dismantleRequest or request(),
		definitions or metadata()
	)
	assert(
		result,
		`[ShrineDismantling.spec] Expected dismantling success: {tostring(dismantleError)}`
	)
	expect(dismantleError).toBeNil()
	return result
end

local function expectRejected(
	production: ShrineAccrual.State,
	base: Types.BaseRecord,
	now: number,
	dismantleRequest: any,
	expectedCode: string,
	definitions: ShrineAccrual.Metadata?
)
	local productionBefore = copy(production)
	local baseBefore = copy(base)
	local result, dismantleError = ShrineDismantling.Dismantle(
		production,
		base,
		now,
		dismantleRequest,
		definitions or metadata()
	)
	expect(result).toBeNil()
	expect(dismantleError).toBe(expectedCode)
	expect(production).toEqual(productionBefore)
	expect(base).toEqual(baseBefore)
end

local function baseAfter(base: Types.BaseRecord, result: ShrineDismantling.Result): Types.BaseRecord
	local updated = table.clone(base)
	updated.shrines = result.shrines
	return updated
end

local function builtShrines(base: Types.BaseRecord): { [string]: Types.ShrineRecord }
	return assert(base.shrines, "[ShrineDismantling.spec] Expected built Shrine map")
end

local function accrue(production: ShrineAccrual.State, now: number): ShrineAccrual.State
	local result, accrualError = ShrineAccrual.Accrue(production, now, metadata())
	assert(result, `[ShrineDismantling.spec] Expected accrual success: {tostring(accrualError)}`)
	return result
end

describe("ShrineDismantling", function()
	it("removes an empty Shrine of every element and level without granting any refund", function()
		for _, elementId in ELEMENTS do
			for level = 1, 3 do
				local production, base = fixture()
				local built = builtShrines(base)
				local instanceId = `shrine_{elementId}`
				production.shrines[instanceId].level = level
				built[instanceId].level = level
				local originalRecord = built[instanceId]
				local result = dismantle(production, base, 0, request(elementId, level))
				expect(result.production.shrines[instanceId]).toBeNil()
				expect(result.shrines[instanceId]).toBeNil()
				expect(result.production.workers).toEqual(production.workers)
				expect(result).toEqual({
					production = result.production,
					shrines = result.shrines,
					shrineInstanceId = instanceId,
					shrineId = originalRecord.shrineId,
					buildSlotId = originalRecord.buildSlotId,
					level = level,
				})
				expect(built[instanceId]).toBe(originalRecord)
			end
		end
	end)

	it("retains every purchased slot and makes the freed lowest gap reusable", function()
		for purchased = 0, 4 do
			local production, base = fixture(purchased + 2)
			local result = dismantle(production, base, 0, request("water"))
			local updated = baseAfter(base, result)
			local status = assert(
				BaseState.GetStatus(updated),
				"[ShrineDismantling.spec] Expected valid Base status"
			)
			expect(updated.buildSlotUpgrades).toBe(purchased)
			expect(status.unlockedShrineSlots).toBe(purchased + 2)
			expect(status.usedShrineSlots).toBe(purchased + 1)
			expect(status.maxShrineSlots).toBe(6)
			local slot, slotError = BaseState.GetLowestFreeShrineSlot(updated)
			expect(slot).toBe(2)
			expect(slotError).toBeNil()
			expect(updated.craftingStation).toBe(base.craftingStation)
			expect(updated.stands).toBe(base.stands)
		end
	end)

	it("preserves duplicate-element Shrine identities, slots, and legacy Base state", function()
		local production, base = fixture(2)
		local built = builtShrines(base)
		built.shrine_water.shrineId = "fire_shrine"
		built.shrine_water.level = 2
		production.shrines.shrine_water.shrineId = "fire_shrine"
		production.shrines.shrine_water.level = 2
		production.shrines.shrine_water.stored = 10
		production.shrines.shrine_water.progress = 0.25
		local before = copy(base)
		local result = dismantle(production, base, 0)
		expect(result.shrines.shrine_water).toEqual(built.shrine_water)
		expect(result.production.shrines.shrine_water).toEqual(production.shrines.shrine_water)
		expect(result.shrines.shrine_water.buildSlotId).toBe(2)
		expect(base).toEqual(before)
		local resultFields = (result :: unknown) :: { [string]: any }
		for _, field in { "base", "gold", "materials", "craftingJobs", "storedBuildings", "refund" } do
			expect(resultFields[field]).toBeNil()
		end
	end)

	it("rejects malformed or extended requests without changing either view", function()
		local production, base = fixture()
		expectRejected(production, base, 0, nil, "InvalidRequest")
		expectRejected(production, base, 0, "dismantle", "InvalidRequest")
		local cases: { any } = {
			{},
			{ shrineInstanceId = "shrine_fire" },
			{ shrineInstanceId = "", expectedLevel = 1 },
			{ shrineInstanceId = string.rep("x", 129), expectedLevel = 1 },
			{ shrineInstanceId = 1, expectedLevel = 1 },
			{ shrineInstanceId = "shrine_fire", expectedLevel = "1" },
			{ shrineInstanceId = "shrine_fire", expectedLevel = 0 },
			{ shrineInstanceId = "shrine_fire", expectedLevel = 1.5 },
			{ shrineInstanceId = "shrine_fire", expectedLevel = math.huge },
			{ shrineInstanceId = "shrine_fire", expectedLevel = 0 / 0 },
			{ shrineInstanceId = "shrine_fire", expectedLevel = 1, refund = true },
			setmetatable(request(), {}),
		}
		for _, invalidRequest in cases do
			expectRejected(production, base, 0, invalidRequest, "InvalidRequest")
		end
	end)

	it("rejects unowned, Station, stale-level, and backdated requests", function()
		local production, base = fixture()
		for _, instanceId in { "not_owned", "permanent_station" } do
			expectRejected(production, base, 0, {
				shrineInstanceId = instanceId,
				expectedLevel = 1,
			}, "ShrineNotOwned")
		end
		expectRejected(production, base, 0, request("fire", 2), "LevelChanged")
		production.lastAccruedAt = 10
		production.nextBatchAt = 11
		expectRejected(production, base, 9, request(), "BackdatedChange")
	end)

	it("rejects malformed Base capacity, records, slots, and permanent Station", function()
		local production, base = fixture()
		local cases: { Types.BaseRecord } = {}
		local missingStation = copy(base)
		missingStation.craftingStation = nil
		table.insert(cases, missingStation)
		local invalidStation = copy(base)
		assert(invalidStation.craftingStation, "[ShrineDismantling.spec] Expected Station").craftingStationId =
			"missing_station"
		table.insert(cases, invalidStation)
		local invalidUpgrade = copy(base)
		invalidUpgrade.buildSlotUpgrades = 5
		table.insert(cases, invalidUpgrade)
		local duplicateSlot = copy(base)
		builtShrines(duplicateSlot).shrine_water.buildSlotId = 1
		table.insert(cases, duplicateSlot)
		local wrongIdentity = copy(base)
		builtShrines(wrongIdentity).shrine_fire.id = "other_identity"
		table.insert(cases, wrongIdentity)
		local missingShrines = copy(base)
		missingShrines.shrines = nil
		table.insert(cases, missingShrines)
		for _, invalidBase in cases do
			expectRejected(production, invalidBase, 0, request(), "InvalidBaseState")
		end
	end)

	it("requires exact built and accounting Shrine maps including unrelated records", function()
		for variant = 1, 4 do
			local production, base = fixture()
			local built = builtShrines(base)
			if variant == 1 then
				production.shrines.shrine_water = nil
			elseif variant == 2 then
				built.shrine_water = nil
			elseif variant == 3 then
				built.shrine_water.shrineId = "fire_shrine"
			else
				built.shrine_water.level = 2
			end
			expectRejected(production, base, 0, request(), "ShrineStateMismatch")
		end
	end)

	it("requires explicit unassignment from every possible slot before dismantling", function()
		for slot = 1, 3 do
			local production, base = fixture()
			production.shrines.shrine_fire.level = 3
			builtShrines(base).shrine_fire.level = 3
			production.shrines.shrine_fire.workerIdsBySlot[tostring(slot)] = "worker_fire"
			production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
			production.shrines.shrine_fire.stored = 1
			expectRejected(production, base, 10, request("fire", 3), "ShrineOccupied")
		end
	end)

	it("blocks stored whole Materials and rolls back unrelated elapsed accrual", function()
		local production, base = fixture()
		production.shrines.shrine_fire.stored = 1
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		expectRejected(production, base, 10, request(), "MaterialsStored")
		expect(production.shrines.shrine_water.stored).toBe(0)
		expect(production.workers.worker_water.xp).toBe(0)
		expect(production.lastAccruedAt).toBe(0)
	end)

	it("settles a due unfinished batch before deciding whether storage is empty", function()
		local production, base = fixture()
		production.shrines.shrine_fire.progress = 0.75
		production.shrines.shrine_fire.newWork = 0.5
		production.workers.worker_fire.pendingXp = 0.5
		expectRejected(production, base, 1, request(), "MaterialsStored")
		expect(production.shrines.shrine_fire.stored).toBe(0)
		expect(production.workers.worker_fire.pendingXp).toBe(0.5)
	end)

	it(
		"discards unfinished work before a boundary but preserves pending XP without its source",
		function()
			local production, base = fixture(1)
			production.lastAccruedAt = 0.5
			production.shrines.shrine_fire.progress = 0.75
			production.shrines.shrine_fire.newWork = 0.5
			production.workers.worker_fire.xp = 119.75
			production.workers.worker_fire.pendingXp = 0.5
			local result = dismantle(production, base, 0.75)
			expect(result.production.shrines).toEqual({})
			expect(result.shrines).toEqual({})
			expect(result.production.lastAccruedAt).toBe(0.75)
			expect(result.production.nextBatchAt).toBe(1)
			expect(result.production.workers.worker_fire.xp).toBe(119.75)
			expect(result.production.workers.worker_fire.pendingXp).toBe(0.5)
			local settled = accrue(result.production, 1)
			expect(settled.workers.worker_fire.level).toBe(2)
			expect(settled.workers.worker_fire.xp).toBe(0.25)
			expect(settled.workers.worker_fire.pendingXp).toBe(0)
			expect(accrue(settled, 1)).toEqual(settled)
			expect(accrue(settled, 10).workers.worker_fire).toEqual(settled.workers.worker_fire)
		end
	)

	it(
		"settles unrelated workers, accepts frozen inputs, and detaches every returned record",
		function()
			local production, base = fixture()
			production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
			production.shrines.shrine_fire.progress = 0.25
			production.workers.worker_fire.pendingXp = 0.5
			local definitions = metadata()
			local productionBefore = copy(production)
			local baseBefore = copy(base)
			FreezeUtil.DeepFreeze(production)
			FreezeUtil.DeepFreeze(base)
			FreezeUtil.DeepFreeze(definitions)
			local result = dismantle(production, base, 1.5, request(), definitions)
			expect(result.production.shrines.shrine_water.stored).toBe(1)
			expect(result.production.shrines.shrine_water.newWork).toBe(0.5)
			expect(result.production.workers.worker_water.xp).toBe(1)
			expect(result.production.workers.worker_water.pendingXp).toBe(0.5)
			expect(result.production.workers.worker_fire.xp).toBe(0.5)
			expect(result.production.workers.worker_fire.pendingXp).toBe(0)
			expect(production).toEqual(productionBefore)
			expect(base).toEqual(baseBefore)
			expect(result.production).never.toBe(production)
			expect(result.shrines).never.toBe(base.shrines)
			for id, record in result.shrines do
				expect(record).never.toBe(builtShrines(base)[id])
			end
			for id, shrine in result.production.shrines do
				expect(shrine).never.toBe(production.shrines[id])
				expect(shrine.workerIdsBySlot).never.toBe(production.shrines[id].workerIdsBySlot)
			end
			for id, worker in result.production.workers do
				expect(worker).never.toBe(production.workers[id])
			end
			result.shrines.shrine_water.level = 2
			result.production.workers.worker_water.xp = 99
			expect(builtShrines(base).shrine_water.level).toBe(1)
			expect(production.workers.worker_water.xp).toBe(0)
		end
	)

	it(
		"matches online and offline settlement across JSON reconnect and rejects repeated removal",
		function()
			local production, base = fixture()
			production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
			local online = copy(production)
			for second = 1, 10 do
				online = accrue(online, second)
			end
			local onlineResult = dismantle(online, copy(base), 10.5)
			local offlineResult = dismantle(copy(production), copy(base), 10.5)
			expect(offlineResult).toEqual(onlineResult)
			local restored = copy(offlineResult)
			expect(restored).toEqual(offlineResult)
			local updatedBase = baseAfter(copy(base), restored)
			expectRejected(restored.production, updatedBase, 10.5, request(), "ShrineNotOwned")
			local resumed = accrue(restored.production, 20)
			expect(resumed).toEqual(accrue(offlineResult.production, 20))
			expect(resumed.shrines.shrine_water.stored).toBe(20)
			expect(resumed.workers.worker_water.xp).toBe(20)

			local replacement = copy(builtShrines(base).shrine_fire)
			replacement.id = "replacement_fire"
			builtShrines(updatedBase).replacement_fire = replacement
			restored.production.shrines.replacement_fire = copy(production.shrines.shrine_fire)
			expectRejected(restored.production, updatedBase, 10.5, request(), "ShrineNotOwned")
			expect(builtShrines(updatedBase).replacement_fire.buildSlotId).toBe(1)
		end
	)

	it("rejects invalid accounting and rolls back if profile-wide settlement overflows", function()
		local production, base = fixture()
		production.shrines.shrine_fire.progress = -0.1
		expectRejected(production, base, 0, request(), "InvalidShrine")
		production.shrines.shrine_fire.progress = 0
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		production.workers.worker_water.pendingXp = 2 ^ 53 - 1
		expectRejected(production, base, 1, request(), "ArithmeticOverflow")
	end)

	it("uses injected batch timing and progression without forcing a completion", function()
		local production, base = fixture()
		production.nextBatchAt = 2
		production.shrines.shrine_fire.progress = 0.5
		production.shrines.shrine_fire.newWork = 0.75
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		local productionConfig = { batchIntervalSeconds = 2, baseXpPerSecond = 3 }
		local progressionConfig = { levelCap = 100, xpPerLevel = 10, yieldGainPerLevel = 0.1 }
		local result, dismantleError = ShrineDismantling.Dismantle(
			production,
			base,
			1.5,
			request(),
			metadata(),
			productionConfig,
			progressionConfig
		)
		assert(
			result,
			`[ShrineDismantling.spec] Expected custom configuration: {tostring(dismantleError)}`
		)
		expect(result.production.nextBatchAt).toBe(2)
		expect(result.production.shrines.shrine_water.stored).toBe(0)
		expect(result.production.shrines.shrine_water.newWork).toBe(1.5)
		expect(result.production.workers.worker_water.xp).toBe(0)
		expect(result.production.workers.worker_water.pendingXp).toBe(4.5)
	end)
end)
