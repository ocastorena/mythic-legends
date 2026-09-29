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
local ShrineAccounting = require(ServerScriptService.Services.ProductionService.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
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
