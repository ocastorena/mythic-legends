--!strict
-- ServerStorage/Tests/__tests__/ShrineAccounting.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Types = require(ReplicatedStorage.Shared.Types)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Projection = require(ServerScriptService.Services.DataService.Projection)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local ShrineAssignments = require(ServerScriptService.Services.BaseService.ShrineAssignments)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

-- Dynamic fixtures exercise malformed saves and preserve opaque fields without weakening APIs.
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

local function stationId(): string
	return "permanent_station"
end

local function neverGenerate(): string
	error("[ShrineAccounting.spec] Preparation must retain the existing Station")
end

local function fixture(formId: string?): any
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, stationId, 0)
	assert(prepared, `[ShrineAccounting.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = 25
	data.profile.createdAt = 100
	data.profile.lastLoginAt = 200
	data.mythlings.worker = {
		typeId = formId or "mythling_0001",
		variantId = "retained_variant",
		claimedAt = 25,
		level = 1,
		xp = 0,
		pendingXp = 0,
	}
	data.base.shrines.first = {
		id = "first",
		shrineId = "fire_shrine",
		buildSlotId = 1,
		level = 1,
		stored = 0,
		progress = 0,
		newWork = 0,
		workerIdsBySlot = { ["1"] = "worker" },
	}
	return data
end

local function metadata(rate: number?): ShrineAccrual.Metadata
	return {
		forms = { test_fire_form = { element = "Fire", baseYieldPerHour = rate or 3_600 } },
		shrines = {
			fire_shrine = {
				element = "Fire",
				materialId = "fire_material",
				levels = {
					[1] = { capacity = 300, workerSlots = 1 },
					[2] = { capacity = 1_200, workerSlots = 2 },
					[3] = { capacity = 3_600, workerSlots = 3 },
				},
			},
		},
	}
end

local function settle(data: any, now: number, definitions: ShrineAccrual.Metadata?)
	local ok, problem = ShrineAccounting.SettleToDraft(data, now, definitions)
	assert(ok, `[ShrineAccounting.spec] Expected settlement: {tostring(problem)}`)
	expect(problem).toBeNil()
end

local function expectRejected(data: any, now: number, definitions: ShrineAccrual.Metadata?)
	local before = copy(data)
	local base, shrines, first, workers, worker, clock =
		data.base,
		data.base.shrines,
		data.base.shrines.first,
		data.mythlings,
		data.mythlings.worker,
		data.productionClock
	local ok, problem = ShrineAccounting.SettleToDraft(data, now, definitions)
	expect(ok).toBe(false)
	expect(type(problem)).toBe("string")
	expect(data).toEqual(before)
	expect(data.base).toBe(base)
	expect(data.base.shrines).toBe(shrines)
	expect(data.base.shrines.first).toBe(first)
	expect(data.mythlings).toBe(workers)
	expect(data.mythlings.worker).toBe(worker)
	expect(data.productionClock).toBe(clock)
end

local function request(revision: number, token: string): Types.TransactionRequest
	return {
		id = `{revision}:{token}`,
		expectedRevision = revision,
		operation = "Test.SettleShrines",
		signature = `now={token}`,
	}
end

local function active(): boolean
	return true
end

local function transactionMutator(now: number): Transactions.Mutator
	return function(draft: Types.PlayerDoc): Types.TransactionOutcome
		local ok, problem = ShrineAccounting.SettleToDraft(draft, now)
		return { ok = ok, code = problem, values = if ok then { settledAt = now } else nil }
	end
end

describe("ShrineAccounting.SettleToDraft", function()
	it("uses real form and Shrine defaults to settle only due work and activity XP", function()
		local data = fixture()
		settle(data, 0.5)
		expect(data.base.shrines.first.stored).toBe(0)
		expect(data.base.shrines.first.progress).toBe(0)
		expect(data.base.shrines.first.newWork).toBeCloseTo(12 * 0.5 / 3_600)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.worker.pendingXp).toBe(0.5)
		expect(data.productionClock).toEqual({ lastAccruedAt = 0.5, nextBatchAt = 1 })

		settle(data, 1)
		expect(data.base.shrines.first.stored).toBe(0)
		expect(data.base.shrines.first.progress).toBeCloseTo(
			MythlingForms.mythling_0001.baseYieldPerHour / 3_600
		)
		expect(data.base.shrines.first.newWork).toBe(0)
		expect(data.mythlings.worker.level).toBe(1)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(data.productionClock).toEqual({ lastAccruedAt = 1, nextBatchAt = 2 })
		local settled = copy(data)
		settle(data, 1)
		expect(data).toEqual(settled)
		expect(data.materials).toEqual({})
		expect(data.currency.gold).toBe(100)
	end)

	it("preserves ownership, slot gaps, opaque metadata, and unrelated profile state", function()
		local data = fixture("test_fire_form")
		data.base.buildSlotUpgrades = 2
		data.base.shrines.first.level = 3
		data.base.shrines.first.workerIdsBySlot = { ["3"] = "worker" }
		data.base.shrines.first.stored = 5
		data.base.shrines.first.progress = 0.25
		data.base.shrines.first.futureState = { enabled = true }
		data.mythlings.worker.luck = 92
		data.mythlings.worker.traitIds = { "legacy_lucky", "legacy_insomniac" }
		data.mythlings.worker.futureField = { retained = "owned" }
		data.productionClock.futureField = { retained = "clock" }
		data.currency.gold = 9_876
		data.materials.fire_material = { total = 30 }
		data.inventoryUpgrades = { materials = 1, equipment = 2, mythlings = 1 }
		data.craftingJobs = {
			job = {
				status = "Active",
				deadline = 4000,
				reservations = { equipment = 1, materials = { fire_material = 5 } },
			},
		}
		data.base.stands["1"] = {
			production = {
				lastAccruedAt = 100,
				materials = { essence = { stored = 9, progress = 0.3 } },
			},
		}
		data.mythlings.legacy = {
			typeId = "dragon",
			variantId = "regular",
			claimedAt = 5,
			standId = 1,
			luck = 3,
			traitIds = { "old_trait" },
		}
		local expected = copy(data)
		expected.base.shrines.first.stored = 7
		expected.mythlings.worker.xp = 2
		expected.productionClock.lastAccruedAt = 2
		expected.productionClock.nextBatchAt = 3
		settle(data, 2, metadata())
		expect(data).toEqual(expected)
	end)

	it(
		"matches split settlements with one long settlement through levels and serialized reconnect",
		function()
			local single = fixture()
			local split = fixture()
			settle(single, 1_800.25)
			for _, now in { 0.5, 59.7, 120, 300.25, 900.5 } do
				settle(split, now)
			end
			local clockBeforeReconnect = copy(split.productionClock)
			split = HttpService:JSONDecode(HttpService:JSONEncode(split))
			expect((ProfileSchema.Prepare(split, neverGenerate, 5_000))).toBe(true)
			expect(split.productionClock).toEqual(clockBeforeReconnect)
			settle(split, 1_800.25)
			expect(split.mythlings.worker.level).toBe(single.mythlings.worker.level)
			expect(split.mythlings.worker.level).toBe(6)
			expect(split.mythlings.worker.xp).toBeCloseTo(single.mythlings.worker.xp)
			expect(split.mythlings.worker.pendingXp).toBeCloseTo(single.mythlings.worker.pendingXp)
			expect(split.base.shrines.first.stored).toBe(single.base.shrines.first.stored)
			expect(split.base.shrines.first.progress).toBeCloseTo(
				single.base.shrines.first.progress
			)
			expect(split.base.shrines.first.newWork).toBeCloseTo(single.base.shrines.first.newWork)
			expect(split.productionClock).toEqual(single.productionClock)
		end
	)

	it("settles pending owned XP once even when its source Shrine no longer exists", function()
		local data = fixture()
		data.base.shrines = {}
		data.mythlings.worker.xp = 119.5
		data.mythlings.worker.pendingXp = 0.75
		data.productionClock.lastAccruedAt = 0.5
		settle(data, 1)
		expect(data.mythlings.worker.level).toBe(2)
		expect(data.mythlings.worker.xp).toBeCloseTo(0.25)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(data.base.shrines).toEqual({})
		settle(data, 100)
		expect(data.mythlings.worker.level).toBe(2)
		expect(data.mythlings.worker.xp).toBeCloseTo(0.25)
	end)

	it("retains whole output above current capacity and never credits its full interval", function()
		local data = fixture()
		data.base.shrines.first.stored = 400
		data.base.shrines.first.progress = 0.25
		settle(data, 100)
		expect(data.base.shrines.first.stored).toBe(400)
		expect(data.base.shrines.first.progress).toBe(0.25)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.productionClock.lastAccruedAt).toBe(100)
	end)

	it("preserves skipped unassigned legacy forms with absent or zero pending credit", function()
		for _, useZero in { false, true } do
			local data = fixture()
			data.mythlings.legacy = {
				typeId = "dragon",
				variantId = "regular",
				claimedAt = 20,
				standId = 1,
				pendingXp = if useZero then 0 else nil,
				luck = 97,
			}
			local expected = copy(data.mythlings.legacy)
			settle(data, 2)
			expect(data.mythlings.legacy).toEqual(expected)
			expect(data.mythlings.legacy.level).toBeNil()
			expect(data.mythlings.legacy.xp).toBeNil()
		end
	end)

	for _, field in { "level", "xp", "pendingXp" } do
		it(`does not invent missing {field} for a known owned form`, function()
			local data = fixture()
			data.mythlings.worker[field] = nil
			expectRejected(data, 1)
		end)
	end

	it("rejects known-form stand assignments even when no Shrine references that worker", function()
		local data = fixture()
		data.mythlings.worker.standId = 1
		data.base.shrines.first.workerIdsBySlot = {}
		expectRejected(data, 1)
	end)

	it("rejects unknown assigned forms without rewriting their saved identity", function()
		local data = fixture("dragon")
		expectRejected(data, 1)
	end)

	local invalidUnknownCredit: { unknown } = { 0.1, -1, math.huge, 0 / 0, "0", false }
	for index, pending in invalidUnknownCredit do
		it(`rejects unknown-form pending credit case {index}`, function()
			local data = fixture()
			data.mythlings.legacy =
				{ typeId = "dragon", variantId = "regular", claimedAt = 0, pendingXp = pending }
			expectRejected(data, 1)
		end)
	end

	it(
		"requires the prepared current schema and complete accounting instead of repairing it",
		function()
			local data = fixture()
			data.version = 6
			expectRejected(data, 1)
			data = fixture()
			data.productionClock = nil
			expectRejected(data, 1)
			data = fixture()
			data.base.shrines.first.newWork = nil
			expectRejected(data, 1)
			data = fixture()
			data.base.craftingStation = nil
			expectRejected(data, 1)
		end
	)

	it(
		"rejects corrupt clocks, backdated settlement, or invalid metadata without partial changes",
		function()
			local data = fixture()
			data.productionClock.lastAccruedAt = 1
			data.productionClock.nextBatchAt = 2
			expectRejected(data, 0.5)
			data = fixture()
			data.productionClock.nextBatchAt = 0
			expectRejected(data, 1)
			data = fixture("test_fire_form")
			local definitions = metadata()
			definitions.forms.test_fire_form.baseYieldPerHour = -1
			expectRejected(data, 1, definitions)
		end
	)

	it("validates all assignment links and elements before committing any earned work", function()
		local data = fixture()
		data.base.shrines.first.workerIdsBySlot = { ["1"] = "not_owned" }
		expectRejected(data, 1)
		data = fixture()
		data.mythlings.worker.typeId = "mythling_0004"
		expectRejected(data, 1)
		data = fixture()
		data.base.shrines.second = copy(data.base.shrines.first)
		data.base.shrines.second.id = "second"
		data.base.shrines.second.buildSlotId = 2
		expectRejected(data, 1)
		data = fixture()
		data.base.shrines.first.workerIdsBySlot = { ["01"] = "worker" }
		expectRejected(data, 1)
	end)

	it(
		"rejects canonical identity and build-slot corruption before settling valid workers",
		function()
			local data = fixture()
			data.base.shrines.first.id = "different_identity"
			expectRejected(data, 1)
			data = fixture()
			data.base.shrines.first.buildSlotId = 3
			expectRejected(data, 1)
			data = fixture()
			data.base.shrines.second = copy(data.base.shrines.first)
			data.base.shrines.second.id = "second"
			data.base.shrines.second.workerIdsBySlot = {}
			expectRejected(data, 1)
		end
	)

	it("rolls back arithmetic overflow while retaining all prior output and pending XP", function()
		local data = fixture()
		data.base.shrines.first.stored = 9
		data.base.shrines.first.progress = 0.75
		data.mythlings.worker.xp = 100
		data.mythlings.worker.pendingXp = 9_007_199_254_740_990
		expectRejected(data, 1)
	end)

	it("rejects frozen or metatable-backed roots without mutating nested state", function()
		local data = fixture()
		FreezeUtil.DeepFreeze(data)
		expectRejected(data, 1)
		data = fixture()
		setmetatable(data, {})
		expectRejected(data, 1)
	end)

	it("can replace frozen nested accounting records without mutating borrowed inputs", function()
		local data = fixture()
		local base, worker, clock = data.base, data.mythlings.worker, data.productionClock
		FreezeUtil.DeepFreeze(data.base)
		FreezeUtil.DeepFreeze(data.mythlings)
		FreezeUtil.DeepFreeze(data.productionClock)
		settle(data, 1)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.productionClock.lastAccruedAt).toBe(1)
		expect(data.base).never.toBe(base)
		expect(data.mythlings.worker).never.toBe(worker)
		expect(data.productionClock).never.toBe(clock)
		expect(base.shrines.first.progress).toBe(0)
		expect(worker.xp).toBe(0)
		expect(clock.lastAccruedAt).toBe(0)
		expect(data.base.shrines.first.workerIdsBySlot).toBe(base.shrines.first.workerIdsBySlot)
	end)

	it(
		"keeps owned pending XP private without dropping existing projected Mythling fields",
		function()
			local data = fixture()
			data.mythlings.worker.pendingXp = 0.5
			data.mythlings.worker.futureVisibleField = "retained"
			local expected = copy(data.mythlings.worker)
			expected.pendingXp = nil
			local projection = Projection.Build(data)
			expect(projection.mythlings.worker).toEqual(expected)
			expect(projection.productionClock).toBeNil()
			expect(projection.base.shrines.first.stored).toBeNil()
			expect(projection.mythlings.worker).never.toBe(data.mythlings.worker)
			projection.mythlings.worker.level = 99
			expect(data.mythlings.worker.level).toBe(1)
			expect(data.mythlings.worker.pendingXp).toBe(0.5)
		end
	)
end)

local bridges: { { name: string, apply: typeof(ShrineAccounting.ChangeAssignmentsToDraft) } } = {
	{ name = "ChangeAssignmentsToDraft", apply = ShrineAccounting.ChangeAssignmentsToDraft },
	{ name = "ChangeStorageToDraft", apply = ShrineAccounting.ChangeStorageToDraft },
}
for _, bridge in bridges do
	describe(`ShrineAccounting.{bridge.name}`, function()
		it(
			"provides a fresh frozen snapshot and leaves the draft untouched on reducer rejection",
			function()
				local data = fixture()
				local previous: ShrineAccrual.State? = nil
				for _, stored in { 0, 12 } do
					data.base.shrines.first.stored = stored
					local before = copy(data)
					local base, workers, clock = data.base, data.mythlings, data.productionClock
					local ok, problem = bridge.apply(data, 0.5, function(state)
						expect(state).never.toBe(previous)
						expect(state.shrines).never.toBe(data.base.shrines)
						expect(state.workers).never.toBe(data.mythlings)
						expect(state.shrines.first.stored).toBe(stored)
						for _, value in
							{
								state,
								state.shrines,
								state.shrines.first,
								state.shrines.first.workerIdsBySlot,
								state.workers,
								state.workers.worker,
							}
						do
							expect(table.isfrozen(value)).toBe(true)
						end
						previous = state
						return nil, "RejectedByReducer"
					end)
					expect(ok).toBe(false)
					expect(problem).toBe("RejectedByReducer")
					expect(data).toEqual(before)
					expect(data.base).toBe(base)
					expect(data.mythlings).toBe(workers)
					expect(data.productionClock).toBe(clock)
					expect(table.isfrozen(data.base.shrines.first)).toBe(false)
				end
			end
		)

		local unsupportedChanges: { { name: string, mutate: (ShrineAccrual.State) -> () } } = {
			{
				name = "added Shrine",
				mutate = function(state)
					state.shrines.extra = copy(state.shrines.first)
					state.shrines.extra.workerIdsBySlot = {}
				end,
			},
			{
				name = "removed Shrine",
				mutate = function(state)
					state.shrines.first = nil
				end,
			},
			{
				name = "added worker",
				mutate = function(state)
					state.workers.extra = copy(state.workers.worker)
				end,
			},
			{
				name = "removed worker",
				mutate = function(state)
					state.shrines.first.workerIdsBySlot = {}
					state.workers.worker = nil
				end,
			},
			{
				name = "changed form",
				mutate = function(state)
					state.workers.worker.formId = "other_fire_form"
				end,
			},
			{
				name = "changed Shrine definition",
				mutate = function(state)
					state.shrines.first.shrineId = "other_fire_shrine"
				end,
			},
			{
				name = "changed Shrine level",
				mutate = function(state)
					state.shrines.first.level = 2
				end,
			},
			{
				name = "wrong returned time",
				mutate = function(state)
					state.lastAccruedAt = 0.25
				end,
			},
		}
		for _, case in unsupportedChanges do
			it(`rejects a valid-looking {case.name} without installing any accounting`, function()
				local data = fixture("test_fire_form")
				local definitions = metadata()
				definitions.forms.other_fire_form = copy(definitions.forms.test_fire_form)
				definitions.shrines.other_fire_shrine = copy(definitions.shrines.fire_shrine)
				local before = copy(data)
				local ok, problem = bridge.apply(
					data,
					0.5,
					function(state, now, config, production, progression)
						local result =
							ShrineAccrual.Accrue(state, now, config, production, progression)
						assert(result, "[ShrineAccounting.spec] Expected valid accrual")
						case.mutate(result)
						expect(ShrineAccrual.Validate(result, now, config, production, progression)).toBeNil()
						return result, nil
					end,
					definitions
				)
				expect(ok).toBe(false)
				expect(problem).toBe("InvalidAccountingChange")
				expect(data).toEqual(before)
			end)
		end

		it("revalidates returned accounting instead of merging invalid output", function()
			local data = fixture()
			local before = copy(data)
			local ok, problem = bridge.apply(data, 0.5, function(state)
				local result: ShrineAccrual.State = copy(state)
				result.lastAccruedAt = 0.5
				result.shrines.first.progress = -1
				return result, nil
			end)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidShrine")
			expect(data).toEqual(before)
		end)
	end)
end

describe("ShrineAccounting.ChangeAssignmentsToDraft", function()
	it(
		"composes real assignment reducers while retaining canonical and unrelated fields",
		function()
			local data = fixture("test_fire_form")
			data.base.shrines.first.stored = 12
			data.base.shrines.first.progress = 0.25
			data.base.shrines.first.futureField = { retained = "shrine" }
			data.mythlings.worker.luck = 91
			data.mythlings.worker.traitIds = { "legacy_lucky" }
			data.productionClock.futureField = { retained = "clock" }
			data.currency.gold = 456
			data.materials.fire_material = { total = 42 }
			local expected = copy(data)
			expected.base.shrines.first.newWork = 0.5
			expected.base.shrines.first.workerIdsBySlot = {}
			expected.mythlings.worker.pendingXp = 0.5
			expected.productionClock.lastAccruedAt = 0.5
			local oldSlots = data.base.shrines.first.workerIdsBySlot
			local ok, problem = ShrineAccounting.ChangeAssignmentsToDraft(
				data,
				0.5,
				function(state, now, config, production, progression)
					return ShrineAssignments.Remove(state, now, {
						shrineInstanceId = "first",
						slotId = 1,
						expectedWorkerId = "worker",
					}, config, production, progression)
				end,
				metadata()
			)
			expect(ok).toBe(true)
			expect(problem).toBeNil()
			expect(data).toEqual(expected)
			expect(oldSlots).toEqual({ ["1"] = "worker" })
			expect(data.base.shrines.first.workerIdsBySlot).never.toBe(oldSlots)

			expected.base.shrines.first.workerIdsBySlot = { ["1"] = "worker" }
			ok, problem = ShrineAccounting.ChangeAssignmentsToDraft(
				data,
				0.5,
				function(state, now, config, production, progression)
					return ShrineAssignments.Assign(state, now, {
						shrineInstanceId = "first",
						slotId = 1,
						workerId = "worker",
					}, config, production, progression)
				end,
				metadata()
			)
			expect(ok).toBe(true)
			expect(problem).toBeNil()
			expect(data).toEqual(expected)
		end
	)
end)

describe("ShrineAccounting.ChangeStorageToDraft", function()
	local assignmentChanges: { { name: string, mutate: (ShrineAccrual.State) -> () } } = {
		{
			name = "added assignment",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["2"] = "extra"
			end,
		},
		{
			name = "removed assignment",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["1"] = nil
			end,
		},
		{
			name = "worker moved within a Shrine",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["1"] = nil
				state.shrines.first.workerIdsBySlot["2"] = "worker"
			end,
		},
		{
			name = "worker moved between Shrines",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["1"] = nil
				state.shrines.second.workerIdsBySlot["1"] = "worker"
			end,
		},
		{
			name = "replacement worker",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["1"] = "extra"
			end,
		},
	}
	for _, case in assignmentChanges do
		it(`rejects a valid-looking {case.name} without staging storage or progression`, function()
			local data = fixture("test_fire_form")
			data.base.shrines.first.level = 2
			data.base.shrines.first.stored = 10
			data.base.shrines.second = copy(data.base.shrines.first)
			data.base.shrines.second.id = "second"
			data.base.shrines.second.buildSlotId = 2
			data.base.shrines.second.workerIdsBySlot = {}
			data.mythlings.extra = copy(data.mythlings.worker)
			local before = copy(data)
			local base, assignments, workers, clock =
				data.base,
				data.base.shrines.first.workerIdsBySlot,
				data.mythlings,
				data.productionClock
			local ok, problem = ShrineAccounting.ChangeStorageToDraft(
				data,
				1.5,
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.shrines.first.stored -= 5
					case.mutate(result)
					expect(ShrineAccrual.Validate(result, now, config, production, progression)).toBeNil()
					return result, nil
				end,
				metadata()
			)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidAccountingChange")
			expect(data).toEqual(before)
			expect(data.base).toBe(base)
			expect(data.base.shrines.first.workerIdsBySlot).toBe(assignments)
			expect(data.mythlings).toBe(workers)
			expect(data.productionClock).toBe(clock)
		end)
	end

	it(
		"merges storage and accounting while retaining assignments and unrelated saved state",
		function()
			local data = fixture("test_fire_form")
			data.base.shrines.first.stored = 12
			data.base.shrines.first.progress = 0.25
			data.base.shrines.first.futureField = { retained = "shrine" }
			data.mythlings.worker.luck = 91
			data.mythlings.worker.traitIds = { "legacy_lucky" }
			data.productionClock.futureField = { retained = "clock" }
			data.currency.gold = 456
			data.materials.fire_material = { total = 42 }
			data.inventoryUpgrades = { materials = 1 }
			data.craftingJobs = {
				active = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
				},
			}
			local expected = copy(data)
			expected.base.shrines.first.stored = 8
			expected.base.shrines.first.newWork = 0.5
			expected.mythlings.worker.xp = 1
			expected.mythlings.worker.pendingXp = 0.5
			expected.productionClock.lastAccruedAt = 1.5
			expected.productionClock.nextBatchAt = 2
			local originalBase, originalWorker, originalClock =
				data.base, data.mythlings.worker, data.productionClock
			local assignments, materials, jobs, upgrades =
				data.base.shrines.first.workerIdsBySlot,
				data.materials,
				data.craftingJobs,
				data.inventoryUpgrades
			FreezeUtil.DeepFreeze(data.base)
			FreezeUtil.DeepFreeze(data.mythlings)
			FreezeUtil.DeepFreeze(data.productionClock)
			local ok, problem = ShrineAccounting.ChangeStorageToDraft(
				data,
				1.5,
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.shrines.first.stored -= 5
					return result, nil
				end,
				metadata()
			)
			expect(ok).toBe(true)
			expect(problem).toBeNil()
			expect(data).toEqual(expected)
			expect(data.base.shrines.first.workerIdsBySlot).toBe(assignments)
			expect(data.materials).toBe(materials)
			expect(data.craftingJobs).toBe(jobs)
			expect(data.inventoryUpgrades).toBe(upgrades)
			expect(originalBase.shrines.first.stored).toBe(12)
			expect(originalBase.shrines.first.newWork).toBe(0)
			expect(originalWorker.xp).toBe(0)
			expect(originalWorker.pendingXp).toBe(0)
			expect(originalClock.lastAccruedAt).toBe(0)
			expect(originalClock.nextBatchAt).toBe(1)
		end
	)
end)

describe("ShrineAccounting.ChangeShrineLevelToDraft", function()
	local invalidChanges: { { name: string, mutate: (ShrineAccrual.State) -> () } } = {
		{
			name = "no level increase",
			mutate = function(state)
				state.shrines.first.level = 1
			end,
		},
		{
			name = "skipped level",
			mutate = function(state)
				state.shrines.first.level = 3
			end,
		},
		{
			name = "other Shrine level",
			mutate = function(state)
				state.shrines.second.level = 2
			end,
		},
		{
			name = "added assignment",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["2"] = "extra"
			end,
		},
		{
			name = "removed assignment",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["1"] = nil
			end,
		},
		{
			name = "moved assignment",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot["1"] = nil
				state.shrines.first.workerIdsBySlot["2"] = "worker"
			end,
		},
		{
			name = "changed definition",
			mutate = function(state)
				state.shrines.second.shrineId = "other_shrine"
			end,
		},
		{
			name = "changed form",
			mutate = function(state)
				state.workers.worker.formId = "other_form"
			end,
		},
		{
			name = "added Shrine",
			mutate = function(state)
				state.shrines.extra = copy(state.shrines.second)
			end,
		},
		{
			name = "removed Shrine",
			mutate = function(state)
				state.shrines.second = nil
			end,
		},
		{
			name = "added worker",
			mutate = function(state)
				state.workers.added = copy(state.workers.extra)
			end,
		},
		{
			name = "removed worker",
			mutate = function(state)
				state.workers.extra = nil
			end,
		},
	}
	for _, case in invalidChanges do
		it(`rejects {case.name} with no partial draft writes`, function()
			local data = fixture("test_fire_form")
			data.base.shrines.second = copy(data.base.shrines.first)
			data.base.shrines.second.id = "second"
			data.base.shrines.second.buildSlotId = 2
			data.base.shrines.second.workerIdsBySlot = {}
			data.mythlings.extra = copy(data.mythlings.worker)
			local definitions = metadata()
			definitions.shrines.other_shrine = copy(definitions.shrines.fire_shrine)
			definitions.forms.other_form = copy(definitions.forms.test_fire_form)
			local before = copy(data)
			local base, workers, clock = data.base, data.mythlings, data.productionClock
			local ok, problem = ShrineAccounting.ChangeShrineLevelToDraft(
				data,
				1.5,
				"first",
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.shrines.first.level = 2
					case.mutate(result)
					expect(ShrineAccrual.Validate(result, now, config, production, progression)).toBeNil()
					return result, nil
				end,
				definitions
			)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidAccountingChange")
			expect(data).toEqual(before)
			expect(data.base).toBe(base)
			expect(data.mythlings).toBe(workers)
			expect(data.productionClock).toBe(clock)
		end)
	end

	it("requires an owned selected Shrine before calling the reducer", function()
		local ids: { any } = { "", "missing", string.rep("x", 129), false, 7 }
		for _, id in ids do
			local data = fixture()
			local before = copy(data)
			local called = false
			local ok, problem = ShrineAccounting.ChangeShrineLevelToDraft(data, 1, id, function()
				called = true
				return nil, "UnexpectedCall"
			end)
			expect(ok).toBe(false)
			expect(problem).toBe(if id == "missing" then "ShrineNotOwned" else "InvalidRequest")
			expect(called).toBe(false)
			expect(data).toEqual(before)
		end
	end)

	it(
		"rejects levels outside canonical Base limits even if injected accounting accepts them",
		function()
			local data = fixture("test_fire_form")
			data.base.shrines.first.level = 3
			local before = copy(data)
			local definitions = metadata()
			definitions.shrines.fire_shrine.levels[4] = { capacity = 5_000, workerSlots = 4 }
			local ok, problem = ShrineAccounting.ChangeShrineLevelToDraft(
				data,
				0,
				"first",
				function(state)
					local result: ShrineAccrual.State = copy(state)
					result.shrines.first.level = 4
					return result, nil
				end,
				definitions
			)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidBaseState")
			expect(data).toEqual(before)
		end
	)

	it("stages only a single level and accounting, retaining borrowed immutable data", function()
		local data = fixture("test_fire_form")
		data.base.shrines.first.progress = 0.25
		data.base.shrines.first.futureField = { retained = true }
		data.mythlings.worker.luck = 99
		data.mythlings.worker.traitIds = { "legacy_lucky" }
		local expected = copy(data)
		expected.base.shrines.first.level = 2
		expected.base.shrines.first.stored = 1
		expected.base.shrines.first.newWork = 0.5
		expected.mythlings.worker.xp = 1
		expected.mythlings.worker.pendingXp = 0.5
		expected.productionClock.lastAccruedAt = 1.5
		expected.productionClock.nextBatchAt = 2
		local assignments = data.base.shrines.first.workerIdsBySlot
		local originalBase, originalWorkers, originalClock =
			data.base, data.mythlings, data.productionClock
		FreezeUtil.DeepFreeze(originalBase)
		FreezeUtil.DeepFreeze(originalWorkers)
		FreezeUtil.DeepFreeze(originalClock)
		local ok, problem = ShrineAccounting.ChangeShrineLevelToDraft(
			data,
			1.5,
			"first",
			function(state, now, config, production, progression)
				expect(table.isfrozen(state)).toBe(true)
				expect(table.isfrozen(state.shrines.first)).toBe(true)
				local result = ShrineAccrual.Accrue(state, now, config, production, progression)
				assert(result, "[ShrineAccounting.spec] Expected valid accrual")
				result.shrines.first.level += 1
				return result, nil
			end,
			metadata()
		)
		expect(ok).toBe(true)
		expect(problem).toBeNil()
		expect(data).toEqual(expected)
		expect(data.base.shrines.first.workerIdsBySlot).toBe(assignments)
		expect(originalBase.shrines.first.level).toBe(1)
		expect(originalBase.shrines.first.stored).toBe(0)
		expect(originalWorkers.worker.xp).toBe(0)
		expect(originalClock.lastAccruedAt).toBe(0)
	end)
end)

describe("ShrineAccounting.RemoveShrineToDraft", function()
	local invalidChanges: { { name: string, mutate: (ShrineAccrual.State, ShrineAccrual.State) -> () } } =
		{
			{
				name = "retained selection",
				mutate = function(state, before)
					state.shrines.first = copy(before.shrines.first)
				end,
			},
			{
				name = "removed other Shrine",
				mutate = function(state)
					state.shrines.second = nil
				end,
			},
			{
				name = "new Shrine",
				mutate = function(state)
					state.shrines.third = copy(state.shrines.second)
					state.shrines.third.workerIdsBySlot = {}
				end,
			},
			{
				name = "changed survivor level",
				mutate = function(state)
					state.shrines.second.level = 2
				end,
			},
			{
				name = "removed surviving assignment",
				mutate = function(state)
					state.shrines.second.workerIdsBySlot = {}
				end,
			},
			{
				name = "changed survivor definition",
				mutate = function(state)
					state.shrines.second.shrineId = "other_shrine"
				end,
			},
			{
				name = "changed worker form",
				mutate = function(state)
					state.workers.worker.formId = "other_form"
				end,
			},
			{
				name = "deleted unassigned worker",
				mutate = function(state)
					state.workers.unassigned = nil
				end,
			},
			{
				name = "granted worker",
				mutate = function(state)
					state.workers.granted = copy(state.workers.worker)
				end,
			},
		}
	for _, case in invalidChanges do
		it(`rejects {case.name} without deleting any canonical state`, function()
			local data = fixture("test_fire_form")
			data.base.shrines.second = copy(data.base.shrines.first)
			data.base.shrines.second.id = "second"
			data.base.shrines.second.buildSlotId = 2
			data.base.shrines.first.workerIdsBySlot = {}
			data.mythlings.unassigned = copy(data.mythlings.worker)
			local definitions = metadata()
			definitions.forms.other_form = copy(definitions.forms.test_fire_form)
			definitions.shrines.other_shrine = copy(definitions.shrines.fire_shrine)
			local before = copy(data)
			local base, workers, clock = data.base, data.mythlings, data.productionClock
			local ok, problem = ShrineAccounting.RemoveShrineToDraft(
				data,
				1,
				"first",
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.shrines.first = nil
					case.mutate(result, state)
					expect(ShrineAccrual.Validate(result, now, config, production, progression)).toBeNil()
					return result, nil
				end,
				definitions
			)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidAccountingChange")
			expect(data).toEqual(before)
			expect(data.base).toBe(base)
			expect(data.mythlings).toBe(workers)
			expect(data.productionClock).toBe(clock)
		end)
	end

	it("requires an owned selection before calling the trusted reducer", function()
		local ids: { any } = { "", "missing", false, 9, string.rep("x", 129) }
		for _, id in ids do
			local data = fixture()
			local before = copy(data)
			local called = false
			local ok, problem = ShrineAccounting.RemoveShrineToDraft(data, 0, id, function()
				called = true
				return nil, "UnexpectedCall"
			end)
			expect(ok).toBe(false)
			expect(problem).toBe(if id == "missing" then "ShrineNotOwned" else "InvalidRequest")
			expect(called).toBe(false)
			expect(data).toEqual(before)
		end
	end)

	it(
		"removes a frozen source record while retaining all worker credit and unrelated fields",
		function()
			local data = fixture("test_fire_form")
			data.base.shrines.first.workerIdsBySlot = {}
			data.base.shrines.first.newWork = 0.5
			data.mythlings.worker.pendingXp = 0.5
			data.mythlings.worker.luck = 17
			data.productionClock = { lastAccruedAt = 0.5, nextBatchAt = 1 }
			local expected = copy(data)
			expected.base.shrines.first = nil
			expected.productionClock.lastAccruedAt = 0.75
			local sourceBase = data.base
			FreezeUtil.DeepFreeze(data.base)
			FreezeUtil.DeepFreeze(data.mythlings)
			FreezeUtil.DeepFreeze(data.productionClock)
			local ok, problem = ShrineAccounting.RemoveShrineToDraft(
				data,
				0.75,
				"first",
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.shrines.first = nil
					return result, nil
				end,
				metadata()
			)
			expect(ok).toBe(true)
			expect(problem).toBeNil()
			expect(data).toEqual(expected)
			expect(sourceBase.shrines.first.newWork).toBe(0.5)
			settle(data, 1, metadata())
			expect(data.mythlings.worker.xp).toBe(0.5)
			expect(data.mythlings.worker.pendingXp).toBe(0)
			expect(data.base.shrines).toEqual({})
		end
	)
end)

describe("ShrineAccounting.ChangeWorkerFormToDraft", function()
	local invalidChanges: { { name: string, mutate: (ShrineAccrual.State) -> () } } = {
		{
			name = "unchanged form",
			mutate = function(state)
				state.workers.worker.formId = "test_fire_form"
			end,
		},
		{
			name = "different target",
			mutate = function(state)
				state.workers.worker.formId = "other_form"
			end,
		},
		{
			name = "another worker's form",
			mutate = function(state)
				state.workers.other.formId = "next_form"
			end,
		},
		{
			name = "added worker",
			mutate = function(state)
				state.workers.added = copy(state.workers.other)
			end,
		},
		{
			name = "removed worker",
			mutate = function(state)
				state.workers.other = nil
			end,
		},
		{
			name = "removed assignment",
			mutate = function(state)
				state.shrines.first.workerIdsBySlot = {}
			end,
		},
		{
			name = "changed level",
			mutate = function(state)
				state.shrines.first.level = 2
			end,
		},
		{
			name = "changed definition",
			mutate = function(state)
				state.shrines.first.shrineId = "other_shrine"
			end,
		},
		{
			name = "removed Shrine",
			mutate = function(state)
				state.shrines.first = nil
			end,
		},
		{
			name = "added Shrine",
			mutate = function(state)
				state.shrines.extra = copy(state.shrines.first)
				state.shrines.extra.workerIdsBySlot = {}
			end,
		},
	}
	for _, case in invalidChanges do
		it(`rejects {case.name} without any draft writes`, function()
			local data = fixture("test_fire_form")
			data.mythlings.other = copy(data.mythlings.worker)
			local definitions = metadata()
			definitions.forms.next_form = { element = "Fire", baseYieldPerHour = 7_200 }
			definitions.forms.other_form = { element = "Fire", baseYieldPerHour = 10_800 }
			definitions.shrines.other_shrine = copy(definitions.shrines.fire_shrine)
			local before = copy(data)
			local base, workers, clock = data.base, data.mythlings, data.productionClock
			local ok, problem = ShrineAccounting.ChangeWorkerFormToDraft(
				data,
				1,
				"worker",
				"next_form",
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.workers.worker.formId = "next_form"
					case.mutate(result)
					expect(ShrineAccrual.Validate(result, now, config, production, progression)).toBeNil()
					return result, nil
				end,
				definitions
			)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidAccountingChange")
			expect(data).toEqual(before)
			expect(data.base).toBe(base)
			expect(data.mythlings).toBe(workers)
			expect(data.productionClock).toBe(clock)
		end)
	end

	it("requires a known owned worker and valid target ID before invoking the reducer", function()
		local cases: { { workerId: any, targetFormId: any, code: string } } = {
			{ workerId = "missing", targetFormId = "mythling_0002", code = "WorkerNotOwned" },
			{ workerId = "worker", targetFormId = "", code = "InvalidRequest" },
			{ workerId = false, targetFormId = "mythling_0002", code = "InvalidRequest" },
		}
		for _, case in cases do
			local data = fixture()
			local before = copy(data)
			local called = false
			local ok, problem = ShrineAccounting.ChangeWorkerFormToDraft(
				data,
				0,
				case.workerId,
				case.targetFormId,
				function()
					called = true
					return nil, "UnexpectedCall"
				end
			)
			expect(ok).toBe(false)
			expect(problem).toBe(case.code)
			expect(called).toBe(false)
			expect(data).toEqual(before)
		end
	end)
end)

describe("ShrineAccounting.RemoveWorkerToDraft", function()
	local invalidChanges: { { name: string, mutate: (ShrineAccrual.State, ShrineAccrual.State) -> () } } =
		{
			{
				name = "retained selected worker",
				mutate = function(state, before)
					state.workers.worker = copy(before.workers.worker)
				end,
			},
			{
				name = "deleted other worker",
				mutate = function(state)
					state.workers.other = nil
				end,
			},
			{
				name = "granted worker",
				mutate = function(state)
					state.workers.added = copy(state.workers.other)
				end,
			},
			{
				name = "changed other form",
				mutate = function(state)
					state.workers.other.formId = "other_form"
				end,
			},
			{
				name = "new assignment",
				mutate = function(state)
					state.shrines.first.workerIdsBySlot["1"] = "other"
				end,
			},
			{
				name = "upgraded Shrine",
				mutate = function(state)
					state.shrines.first.level = 2
				end,
			},
			{
				name = "changed Shrine definition",
				mutate = function(state)
					state.shrines.first.shrineId = "other_shrine"
				end,
			},
			{
				name = "dismantled Shrine",
				mutate = function(state)
					state.shrines.first = nil
				end,
			},
			{
				name = "created Shrine",
				mutate = function(state)
					state.shrines.added = copy(state.shrines.first)
				end,
			},
		}
	for _, case in invalidChanges do
		it(`rejects {case.name} without staged accounting or deletion`, function()
			local data = fixture("test_fire_form")
			data.base.shrines.first.workerIdsBySlot = {}
			data.mythlings.other = copy(data.mythlings.worker)
			data.mythlings.other.pendingXp = 0.5
			local definitions = metadata()
			definitions.forms.other_form = copy(definitions.forms.test_fire_form)
			definitions.shrines.other_shrine = copy(definitions.shrines.fire_shrine)
			local before = copy(data)
			local base, workers, clock = data.base, data.mythlings, data.productionClock
			local ok, problem = ShrineAccounting.RemoveWorkerToDraft(
				data,
				1,
				"worker",
				function(state, now, config, production, progression)
					local result = ShrineAccrual.Accrue(state, now, config, production, progression)
					assert(result, "[ShrineAccounting.spec] Expected valid accrual")
					result.workers.worker = nil
					case.mutate(result, state)
					expect(ShrineAccrual.Validate(result, now, config, production, progression)).toBeNil()
					return result, nil
				end,
				definitions
			)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidAccountingChange")
			expect(data).toEqual(before)
			expect(data.base).toBe(base)
			expect(data.mythlings).toBe(workers)
			expect(data.productionClock).toBe(clock)
		end)
	end

	it("never makes opaque prototype ownership eligible for canonical removal", function()
		local data = fixture()
		data.mythlings.legacy = { typeId = "prototype", variantId = "retained", claimedAt = 1 }
		local before = copy(data)
		local called = false
		local ok, problem = ShrineAccounting.RemoveWorkerToDraft(data, 0, "legacy", function()
			called = true
			return nil, "UnexpectedCall"
		end)
		expect(ok).toBe(false)
		expect(problem).toBe("WorkerNotOwned")
		expect(called).toBe(false)
		expect(data).toEqual(before)
	end)

	it("rejects invalid selected IDs before invoking the trusted reducer", function()
		local ids: { any } = { "", false, 3, string.rep("x", 129) }
		for _, id in ids do
			local data = fixture()
			local before = copy(data)
			local called = false
			local ok, problem = ShrineAccounting.RemoveWorkerToDraft(data, 0, id, function()
				called = true
				return nil, "UnexpectedCall"
			end)
			expect(ok).toBe(false)
			expect(problem).toBe("InvalidRequest")
			expect(called).toBe(false)
			expect(data).toEqual(before)
		end
	end)
end)

describe("ShrineAccounting transaction integration", function()
	it(
		"commits exactly once while retaining live references and rejecting stale revisions",
		function()
			local data = fixture()
			local base, shrines, first, assignments, workers, worker, clock, station =
				data.base,
				data.base.shrines,
				data.base.shrines.first,
				data.base.shrines.first.workerIdsBySlot,
				data.mythlings,
				data.mythlings.worker,
				data.productionClock,
				data.base.craftingStation
			local calls = 0
			local mutation = transactionMutator(300)
			local function counted(draft: Types.PlayerDoc): Types.TransactionOutcome
				calls += 1
				return mutation(draft)
			end
			local originalRequest = request(0, "first")
			local result = Transactions.Run(data, originalRequest, counted, active)
			expect(result.ok).toBe(true)
			expect(result.revision).toBe(1)
			expect(data.base).toBe(base)
			expect(data.base.shrines).toBe(shrines)
			expect(data.base.shrines.first).toBe(first)
			expect(data.base.shrines.first.workerIdsBySlot).toBe(assignments)
			expect(data.mythlings).toBe(workers)
			expect(data.mythlings.worker).toBe(worker)
			expect(data.productionClock).toBe(clock)
			expect(data.base.craftingStation).toBe(station)
			local afterCommit = copy(data)
			local replay = Transactions.Run(data, originalRequest, counted, active)
			expect(replay.ok).toBe(true)
			expect(replay.replayed).toBe(true)
			expect(data).toEqual(afterCommit)
			expect(calls).toBe(1)
			local stale = Transactions.Run(data, request(0, "stale"), counted, active)
			expect(stale.code).toBe("StaleRevision")
			expect(data).toEqual(afterCommit)
			expect(calls).toBe(1)

			local reloaded = HttpService:JSONDecode(HttpService:JSONEncode(data))
			expect((ProfileSchema.Prepare(reloaded, neverGenerate, 1_000))).toBe(true)
			local replayAfterReload = Transactions.Run(reloaded, originalRequest, counted, active)
			expect(replayAfterReload.replayed).toBe(true)
			expect(reloaded).toEqual(afterCommit)
			expect(calls).toBe(1)
		end
	)

	it("discards the settled draft if the session is lost before transaction commit", function()
		local data = fixture()
		local before = copy(data)
		local hasSession = true
		local result = Transactions.Run(data, request(0, "lost"), function(draft)
			local ok, problem = ShrineAccounting.SettleToDraft(draft, 300)
			expect(ok).toBe(true)
			hasSession = false
			return { ok = ok, code = problem }
		end, function()
			return hasSession
		end)
		expect(result.ok).toBe(false)
		expect(result.code).toBe("DataUnavailable")
		expect(data).toEqual(before)
	end)

	it(
		"records a rejected accounting result without committing gameplay or replaying the mutation",
		function()
			local data = fixture()
			data.mythlings.worker.pendingXp = nil
			local before = copy(data)
			before.transactions = nil
			local calls = 0
			local function reject(draft: Types.PlayerDoc): Types.TransactionOutcome
				calls += 1
				local ok, problem = ShrineAccounting.SettleToDraft(draft, 300)
				return { ok = ok, code = problem }
			end
			local originalRequest = request(0, "invalid")
			local result = Transactions.Run(data, originalRequest, reject, active)
			expect(result.ok).toBe(false)
			expect(result.revision).toBe(1)
			local after = copy(data)
			after.transactions = nil
			expect(after).toEqual(before)
			local replay = Transactions.Run(data, originalRequest, reject, active)
			expect(replay.replayed).toBe(true)
			expect(replay.code).toBe(result.code)
			expect(calls).toBe(1)
		end
	)
end)
