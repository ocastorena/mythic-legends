--!strict
-- ServerStorage/Tests/__tests__/ShrineAccountingRead.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

-- Dynamic save fixtures deliberately cover malformed and retained opaque fields.
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = copy(child)
	end
	return result
end

local function fixture(formId: string?): any
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return "permanent_station"
	end, 0)
	assert(prepared, `[ShrineAccountingRead.spec] Fixture preparation failed: {tostring(problem)}`)
	data.productionClock = { lastAccruedAt = 100.25, nextBatchAt = 101 }
	data.mythlings.worker = {
		typeId = formId or "mythling_0001",
		variantId = "regular",
		claimedAt = 20,
		level = 1,
		xp = 119,
		pendingXp = 2,
		luck = 84,
		traitIds = { "retained_trait" },
	}
	data.base.shrines.first = {
		id = "first",
		shrineId = "fire_shrine",
		buildSlotId = 1,
		level = 1,
		stored = 7,
		progress = 0.75,
		newWork = 1.5,
		workerIdsBySlot = { ["1"] = "worker" },
	}
	return data
end

local function metadata(): ShrineAccrual.Metadata
	return {
		forms = { test_fire_form = { element = "Fire", baseYieldPerHour = 3_600 } },
		shrines = {
			fire_shrine = {
				element = "Fire",
				materialId = "fire_material",
				levels = { [1] = { capacity = 300, workerSlots = 1 } },
			},
		},
	}
end

local function read(data: any, definitions: ShrineAccrual.Metadata?): ShrineAccounting.Snapshot
	local result, problem = ShrineAccounting.ReadSnapshot(data, definitions)
	assert(result, `[ShrineAccountingRead.spec] Expected snapshot: {tostring(problem)}`)
	expect(problem).toBeNil()
	return result
end

local function expectRejected(data: any, expectedCode: string)
	local before = copy(data)
	local snapshot, problem = ShrineAccounting.ReadSnapshot(data)
	expect(snapshot).toBeNil()
	expect(problem).toBe(expectedCode)
	expect(data).toEqual(before)
	-- The read boundary must reject the same invalid saved state as the mutation bridge.
	local ok, mutationProblem = ShrineAccounting.SettleToDraft(data, 100.25)
	expect(ok).toBe(false)
	expect(mutationProblem).toBe(expectedCode)
	expect(data).toEqual(before)
end

describe("ShrineAccounting.ReadSnapshot", function()
	it("reads the saved cursor without resolving earned whole output or pending levels", function()
		local data = fixture()
		local before = copy(data)
		local first = read(data)
		local second = read(data)
		expect(first.state.lastAccruedAt).toBe(100.25)
		expect(first.state.nextBatchAt).toBe(101)
		expect(first.state.shrines.first).toEqual({
			shrineId = "fire_shrine",
			level = 1,
			stored = 7,
			progress = 0.75,
			newWork = 1.5,
			workerIdsBySlot = { ["1"] = "worker" },
		})
		expect(first.state.workers.worker).toEqual({
			formId = "mythling_0001",
			level = 1,
			xp = 119,
			pendingXp = 2,
		})
		expect(second.state).toEqual(first.state)
		expect(second.state).never.toBe(first.state)
		expect(data).toEqual(before)
	end)

	it("recursively freezes only detached accounting tables, not live profile records", function()
		local data = fixture()
		local result = read(data)
		for _, value in
			{
				result,
				result.state,
				result.state.shrines,
				result.state.shrines.first,
				result.state.shrines.first.workerIdsBySlot,
				result.state.workers,
				result.state.workers.worker,
			}
		do
			expect(table.isfrozen(value)).toBe(true)
		end
		for _, value in
			{
				data,
				data.base,
				data.base.shrines,
				data.base.shrines.first,
				data.base.shrines.first.workerIdsBySlot,
				data.mythlings,
				data.mythlings.worker,
				data.mythlings.worker.traitIds,
				data.productionClock,
			}
		do
			expect(table.isfrozen(value)).toBe(false)
		end
		expect(result.state.shrines).never.toBe(data.base.shrines)
		expect(result.state.shrines.first).never.toBe(data.base.shrines.first)
		expect(result.state.shrines.first.workerIdsBySlot).never.toBe(
			data.base.shrines.first.workerIdsBySlot
		)
		expect(result.state.workers.worker).never.toBe(data.mythlings.worker)
		data.base.shrines.first.stored = 99
		data.base.shrines.first.workerIdsBySlot["1"] = nil
		data.mythlings.worker.xp = 3
		data.productionClock.lastAccruedAt = 100.5
		expect(result.state.shrines.first.stored).toBe(7)
		expect(result.state.shrines.first.workerIdsBySlot["1"]).toBe("worker")
		expect(result.state.workers.worker.xp).toBe(119)
		expect(result.state.lastAccruedAt).toBe(100.25)
	end)

	it("accepts a frozen profile for reads while keeping the mutation bridge draft-only", function()
		local data = fixture()
		FreezeUtil.DeepFreeze(data)
		local before = copy(data)
		expect(read(data).state.shrines.first.stored).toBe(7)
		local ok, problem = ShrineAccounting.SettleToDraft(data, 100.25)
		expect(ok).toBe(false)
		expect(problem).toBe("InvalidProfileDraft")
		expect(data).toEqual(before)
	end)

	it("uses immutable default metadata and borrows custom metadata without freezing it", function()
		local defaults = read(fixture()).metadata
		expect(table.isfrozen(defaults)).toBe(true)
		expect(table.isfrozen(defaults.forms.mythling_0001)).toBe(true)
		expect(table.isfrozen(defaults.shrines.fire_shrine.levels[1])).toBe(true)
		local definitions = metadata()
		local before = copy(definitions)
		local result = read(fixture("test_fire_form"), definitions)
		expect(result.metadata).toBe(definitions)
		expect(definitions).toEqual(before)
		expect(table.isfrozen(definitions)).toBe(false)
		expect(table.isfrozen(definitions.forms.test_fire_form)).toBe(false)
		expect(table.isfrozen(definitions.shrines.fire_shrine.levels[1])).toBe(false)
		FreezeUtil.DeepFreeze(definitions)
		expect(read(fixture("test_fire_form"), definitions).metadata).toBe(definitions)
		for _, raw in { false, 7, {}, { forms = {}, shrines = false } } do
			local malformed = (raw :: unknown) :: ShrineAccrual.Metadata
			local rejected, problem = ShrineAccounting.ReadSnapshot(fixture(), malformed)
			expect(rejected).toBeNil()
			expect(problem).toBe("InvalidMetadata")
		end
	end)

	it("validates custom tuning at the saved cursor without applying its faster rates", function()
		local data = fixture("test_fire_form")
		data.mythlings.worker.xp = 9
		local definitions = metadata()
		local production = { batchIntervalSeconds = 2, baseXpPerSecond = 500 }
		local progression = { levelCap = 10, xpPerLevel = 10, yieldGainPerLevel = 0.5 }
		local before = copy(data)
		local result, problem =
			ShrineAccounting.ReadSnapshot(data, definitions, production, progression)
		assert(result, `[ShrineAccountingRead.spec] Expected custom tuning: {tostring(problem)}`)
		expect(result.state.workers.worker.xp).toBe(9)
		expect(result.state.workers.worker.pendingXp).toBe(2)
		expect(result.state.shrines.first.newWork).toBe(1.5)
		expect(data).toEqual(before)
		expect(table.isfrozen(production)).toBe(false)
		expect(table.isfrozen(progression)).toBe(false)
		production.batchIntervalSeconds = 0.5
		local rejected, invalidCursor =
			ShrineAccounting.ReadSnapshot(data, definitions, production, progression)
		expect(rejected).toBeNil()
		expect(invalidCursor).toBe("InvalidState")
		production.batchIntervalSeconds = 2
		progression.xpPerLevel = 0
		local invalid, invalidTuning =
			ShrineAccounting.ReadSnapshot(data, definitions, production, progression)
		expect(invalid).toBeNil()
		expect(invalidTuning).toBe("InvalidConfiguration")
		expect(data).toEqual(before)
	end)

	it("preserves opaque inactive legacy records while excluding them from accounting", function()
		for _, hasZeroCredit in { false, true } do
			local data = fixture()
			data.mythlings.legacy = {
				typeId = "dragon",
				standId = 1,
				luck = 70,
				traitIds = { "legacy_trait" },
				pendingXp = if hasZeroCredit then 0 else nil,
			}
			local before = copy(data)
			local result = read(data)
			expect(result.state.workers.legacy).toBeNil()
			expect(data).toEqual(before)
			expect(table.isfrozen(data.mythlings.legacy)).toBe(false)
		end
	end)

	local invalidSaves: { { code: string, change: (any) -> () } } = {
		{
			code = "UnsupportedVersion",
			change = function(data)
				data.version = 6
			end,
		},
		{
			code = "MissingProductionClock",
			change = function(data)
				data.productionClock = nil
			end,
		},
		{
			code = "InvalidProductionClock",
			change = function(data)
				data.productionClock.lastAccruedAt = -1
			end,
		},
		{
			code = "InvalidProductionClock",
			change = function(data)
				data.productionClock.lastOnlineCheckpointAt = 101
			end,
		},
		{
			code = "InvalidState",
			change = function(data)
				data.productionClock.nextBatchAt = 100.25
			end,
		},
		{
			code = "InvalidBaseState",
			change = function(data)
				data.base.craftingStation = nil
			end,
		},
		{
			code = "InvalidBaseState",
			change = function(data)
				data.base.shrines.first.id = "another"
			end,
		},
		{
			code = "InvalidBaseState",
			change = function(data)
				data.base.shrines.first.buildSlotId = 3
			end,
		},
		{
			code = "InvalidShrineProduction",
			change = function(data)
				data.base.shrines.first.newWork = nil
			end,
		},
		{
			code = "InvalidShrine",
			change = function(data)
				data.base.shrines.first.progress = 1
			end,
		},
		{
			code = "InvalidAssignment",
			change = function(data)
				data.base.shrines.first.workerIdsBySlot = { ["01"] = "worker" }
			end,
		},
		{
			code = "InvalidAssignment",
			change = function(data)
				data.mythlings.worker.typeId = "mythling_0004"
			end,
		},
		{
			code = "IncompleteMythlingProgression",
			change = function(data)
				data.mythlings.worker.pendingXp = nil
			end,
		},
		{
			code = "InvalidWorker",
			change = function(data)
				data.mythlings.worker.level = 0
			end,
		},
		{
			code = "UnresolvedLevel",
			change = function(data)
				data.mythlings.worker.xp = 120
			end,
		},
		{
			code = "LegacyStandConflict",
			change = function(data)
				data.mythlings.worker.standId = 1
			end,
		},
		{
			code = "UnresolvedMythlingForm",
			change = function(data)
				data.mythlings.worker.typeId = "dragon"
			end,
		},
	}
	it("rejects malformed saved state with mutation-parity errors and no repair", function()
		for _, case in invalidSaves do
			local data = fixture()
			case.change(data)
			expectRejected(data, case.code)
		end
	end)

	it(
		"validates other Shrines and unassigned workers rather than only selected records",
		function()
			local data = fixture()
			data.base.shrines.second = copy(data.base.shrines.first)
			data.base.shrines.second.id = "second"
			data.base.shrines.second.buildSlotId = 2
			expectRejected(data, "InvalidAssignment")
			data = fixture()
			data.mythlings.other = copy(data.mythlings.worker)
			data.mythlings.other.standId = 1
			expectRejected(data, "LegacyStandConflict")
			data = fixture()
			data.mythlings.legacy = { typeId = "dragon", pendingXp = 0.1 }
			expectRejected(data, "UnresolvedMythlingForm")
		end
	)
end)
