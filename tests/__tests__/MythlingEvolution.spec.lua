--!strict
-- ServerStorage/Tests/__tests__/MythlingEvolution.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local MythlingEvolution = require(ServerScriptService.Domain.Production.MythlingEvolution)
local ShrineAccrual = require(ServerScriptService.Domain.Production.ShrineAccrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): MythlingEvolution.Metadata
	local definitions: MythlingEvolution.Metadata = { forms = {}, shrines = {} }
	for _, elementId in ELEMENTS do
		for form = 1, 3 do
			definitions.forms[`test_{elementId}_{form}`] = {
				element = elementId,
				baseYieldPerHour = form * 3_600,
				evolution = if form < 3
					then {
						targetFormId = `test_{elementId}_{form + 1}`,
						requiredLevel = if form == 1 then 6 else 40,
					}
					else nil,
			}
		end
		definitions.shrines[`test_{elementId}_shrine`] = {
			element = elementId,
			materialId = `test_{elementId}_material`,
			levels = { [1] = { capacity = 300, workerSlots = 1 } },
		}
	end
	return definitions
end

local function accountingMetadata(definitions: MythlingEvolution.Metadata): ShrineAccrual.Metadata
	local accounting: ShrineAccrual.Metadata = { forms = {}, shrines = definitions.shrines }
	for id, definition in definitions.forms do
		accounting.forms[id] = definition
	end
	return accounting
end

local function state(): MythlingEvolution.State
	local production: MythlingEvolution.State = {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		shrines = {},
		workers = {},
	}
	for _, elementId in ELEMENTS do
		production.workers[`worker_{elementId}`] = {
			formId = `test_{elementId}_1`,
			level = 6,
			xp = 0,
			pendingXp = 0,
		}
		production.shrines[`shrine_{elementId}`] = {
			shrineId = `test_{elementId}_shrine`,
			level = 1,
			workerIdsBySlot = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}
	end
	return production
end

local function request(elementId: string?, form: number?): MythlingEvolution.Request
	return {
		workerId = `worker_{elementId or "fire"}`,
		expectedFormId = `test_{elementId or "fire"}_{form or 1}`,
		expectedTargetFormId = `test_{elementId or "fire"}_{(form or 1) + 1}`,
	}
end

local function evolve(
	production: MythlingEvolution.State,
	now: number,
	evolutionRequest: MythlingEvolution.Request?,
	definitions: MythlingEvolution.Metadata?
): MythlingEvolution.State
	local result, evolutionError = MythlingEvolution.Evolve(
		production,
		now,
		evolutionRequest or request(),
		definitions or metadata()
	)
	assert(
		result,
		`[MythlingEvolution.spec] Expected evolution success: {tostring(evolutionError)}`
	)
	expect(evolutionError).toBeNil()
	return result
end

local function expectRejected(
	production: MythlingEvolution.State,
	now: number,
	evolutionRequest: any,
	expectedCode: string,
	definitions: MythlingEvolution.Metadata?
)
	local before = copy(production)
	local result, evolutionError =
		MythlingEvolution.Evolve(production, now, evolutionRequest, definitions or metadata())
	expect(result).toBeNil()
	expect(evolutionError).toBe(expectedCode)
	expect(production).toEqual(before)
end

local function accrue(
	production: MythlingEvolution.State,
	now: number,
	definitions: MythlingEvolution.Metadata?
): MythlingEvolution.State
	local result, accrualError =
		ShrineAccrual.Accrue(production, now, accountingMetadata(definitions or metadata()))
	assert(result, `[MythlingEvolution.spec] Expected accrual success: {tostring(accrualError)}`)
	return result
end

describe("MythlingEvolution", function()
	it("requires the configured level 6 and 40 gates for each synthetic elemental chain", function()
		for _, elementId in ELEMENTS do
			for form, requiredLevel in { 6, 40 } do
				local production = state()
				local workerId = `worker_{elementId}`
				production.workers[workerId].formId = `test_{elementId}_{form}`
				production.workers[workerId].level = requiredLevel - 1
				expectRejected(production, 0, request(elementId, form), "LevelTooLow")
				production.workers[workerId].level = requiredLevel
				production.workers[workerId].xp = 12.5
				local result = evolve(production, 0, request(elementId, form))
				expect(result.workers[workerId].formId).toBe(`test_{elementId}_{form + 1}`)
				expect(result.workers[workerId].level).toBe(requiredLevel)
				expect(result.workers[workerId].xp).toBe(12.5)
			end
		end
	end)

	it("settles the due XP boundary before eligibility without granting early evolution", function()
		local production = state()
		production.workers.worker_fire.level = 5
		production.workers.worker_fire.xp = 599
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		expectRejected(production, 0.5, request(), "LevelTooLow")
		local result = evolve(production, 1)
		expect(result.workers.worker_fire.level).toBe(6)
		expect(result.workers.worker_fire.xp).toBe(0)
		expect(result.workers.worker_fire.pendingXp).toBe(0)
		expect(result.workers.worker_fire.formId).toBe("test_fire_2")
		expect(result.shrines.shrine_fire.stored).toBe(1)
		expect(result.shrines.shrine_fire.progress).toBeCloseTo(0.04, 10)
		expect(result.nextBatchAt).toBe(2)
	end)

	it(
		"awards already-earned pending XP to an unassigned worker before checking its level",
		function()
			local production = state()
			production.workers.worker_fire.level = 5
			production.workers.worker_fire.xp = 599.5
			production.workers.worker_fire.pendingXp = 0.5
			expectRejected(production, 0.5, request(), "LevelTooLow")
			local result = evolve(production, 1)
			expect(result.workers.worker_fire.level).toBe(6)
			expect(result.workers.worker_fire.xp).toBe(0)
			expect(result.workers.worker_fire.pendingXp).toBe(0)
			expect(result.shrines.shrine_fire.stored).toBe(0)
			expect(result.shrines.shrine_fire.workerIdsBySlot).toEqual({})
		end
	)

	it("keeps mid-batch old-form work and applies new Yield only after the change", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.shrines.shrine_fire.progress = 0.25
		production.shrines.shrine_fire.stored = 7
		local result = evolve(production, 0.5)
		expect(result.shrines.shrine_fire.progress).toBe(0.25)
		expect(result.shrines.shrine_fire.stored).toBe(7)
		expect(result.shrines.shrine_fire.newWork).toBeCloseTo(0.525, 10)
		expect(result.workers.worker_fire.xp).toBe(0)
		expect(result.workers.worker_fire.pendingXp).toBe(0.5)
		expect(result.lastAccruedAt).toBe(0.5)
		expect(result.nextBatchAt).toBe(1)
		local completed = accrue(result, 1)
		expect(completed.shrines.shrine_fire.stored).toBe(8)
		expect(completed.shrines.shrine_fire.progress).toBeCloseTo(0.825, 10)
		expect(completed.shrines.shrine_fire.newWork).toBe(0)
		expect(completed.workers.worker_fire.xp).toBe(1)
		expect(completed.workers.worker_fire.pendingXp).toBe(0)
	end)

	it("allows eligible evolution while full without backfilling production or new XP", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.shrines.shrine_fire.stored = 300
		production.shrines.shrine_fire.progress = 0.25
		production.workers.worker_fire.xp = 17
		production.workers.worker_fire.pendingXp = 0.5
		local result = evolve(production, 10)
		expect(result.shrines.shrine_fire.stored).toBe(300)
		expect(result.shrines.shrine_fire.progress).toBe(0.25)
		expect(result.shrines.shrine_fire.newWork).toBe(0)
		expect(result.workers.worker_fire.xp).toBe(17.5)
		expect(result.workers.worker_fire.pendingXp).toBe(0)
		expect(accrue(result, 20).workers.worker_fire).toEqual(result.workers.worker_fire)
	end)

	it("retains assignments, owned identity, and inactive legacy values without rerolls", function()
		for _, assigned in { false, true } do
			local production = state()
			if assigned then
				production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
			end
			-- Opaque saved fields are outside the accounting type but must survive its copies.
			local legacy = production.workers.worker_fire :: any
			legacy.luck = 23.5
			legacy.traitId = "legacy_insomniac"
			legacy.acquiredAt = 987_654
			local expected = copy(production)
			expected.workers.worker_fire.formId = "test_fire_2"
			local result = evolve(production, 0)
			expect(result).toEqual(expected)
			expect(result.workers.worker_fire).never.toBe(production.workers.worker_fire)
			expect((result.workers.worker_water :: any).luck).toBeNil()
			expect((result.workers.worker_water :: any).traitId).toBeNil()
		end
	end)

	it("permits two manual same-time evolutions with no retraining or progression spend", function()
		local production = state()
		production.workers.worker_fire.level = 40
		production.workers.worker_fire.xp = 55.25
		production.workers.worker_fire.pendingXp = 0.75
		local first = evolve(production, 0)
		local second = evolve(first, 0, request("fire", 2))
		expect(first.workers.worker_fire.formId).toBe("test_fire_2")
		expect(second.workers.worker_fire.formId).toBe("test_fire_3")
		expect(second.workers.worker_fire.level).toBe(40)
		expect(second.workers.worker_fire.xp).toBe(55.25)
		expect(second.workers.worker_fire.pendingXp).toBe(0.75)
		expectRejected(second, 0, request(), "FormChanged")
		expectRejected(second, 0, request("fire", 3), "NoEvolution")
	end)

	it(
		"does not auto-evolve trained forms and lets terminal forms train to the normal cap",
		function()
			local production = state()
			production.workers.worker_fire.level = 40
			production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
			expect(accrue(production, 10).workers.worker_fire.formId).toBe("test_fire_1")
			production.workers.worker_fire.formId = "test_fire_3"
			production.workers.worker_fire.level = 99
			production.workers.worker_fire.xp = 11_879.5
			local capped = accrue(production, 1)
			expect(capped.workers.worker_fire.level).toBe(100)
			expect(capped.workers.worker_fire.xp).toBe(0.5)
			local later = accrue(capped, 2)
			expect(later.workers.worker_fire.xp).toBe(0.5)
			expect(later.shrines.shrine_fire.stored > capped.shrines.shrine_fire.stored).toBe(true)
			expectRejected(capped, 1, request("fire", 3), "NoEvolution")
			production = state()
			production.workers.worker_fire.formId = "test_fire_2"
			production.workers.worker_fire.level = 1
			expectRejected(production, 0, request("fire", 2), "LevelTooLow")
		end
	)

	it(
		"follows optional links independently of rarity, stage, and increasing-Yield catalogue rules",
		function()
			local production = state()
			local definitions = metadata()
			local source = definitions.forms.test_fire_1 :: any
			source.rarity = "Mythical"
			source.evolutionStage = 3
			local target = definitions.forms.test_fire_2 :: any
			target.rarity = "Mythical"
			target.evolutionStage = 1
			target.baseYieldPerHour = 0
			target.evolution = nil
			local result = evolve(production, 0, request(), definitions)
			expect(result.workers.worker_fire.formId).toBe("test_fire_2")
			expectRejected(result, 0, request("fire", 2), "NoEvolution", definitions)
			definitions.forms.test_fire_1.evolution = nil
			expectRejected(production, 0, request(), "NoEvolution", definitions)
		end
	)

	it("rejects malformed and extended requests before changing accounting", function()
		local production = state()
		expectRejected(production, 0, nil, "InvalidRequest")
		expectRejected(production, 0, "evolve", "InvalidRequest")
		for _, field in { "workerId", "expectedFormId", "expectedTargetFormId" } do
			for _, badValue in { "", string.rep("x", 129), 5, false } do
				local malformed = request() :: any
				malformed[field] = badValue
				expectRejected(production, 0, malformed, "InvalidRequest")
			end
			local missing = request() :: any
			missing[field] = nil
			expectRejected(production, 0, missing, "InvalidRequest")
		end
		local extra = request() :: any
		extra.targetLevel = 100
		expectRejected(production, 0, extra, "InvalidRequest")
		expectRejected(production, 0, setmetatable(request(), {}), "InvalidRequest")
	end)

	it(
		"rejects stale forms or targets, unknown workers, invalid state, and backdated changes",
		function()
			local production = state()
			local missing = request()
			missing.workerId = "not_owned"
			expectRejected(production, 0, missing, "WorkerNotOwned")
			expectRejected(production, 0, request("fire", 2), "FormChanged")
			local staleTarget = request()
			staleTarget.expectedTargetFormId = "test_fire_3"
			expectRejected(production, 0, staleTarget, "EvolutionTargetChanged")
			production.lastAccruedAt = 10
			production.nextBatchAt = 11
			expectRejected(production, 9, request(), "BackdatedChange")
			production.shrines.shrine_fire.progress = -0.1
			expectRejected(production, 10, request(), "InvalidShrine")
		end
	)

	it("rejects malformed reachable links, missing targets, cycles, and element changes", function()
		local cases: { MythlingEvolution.Metadata } = {}
		for _, badLevel in { 0, 101, 1.5, math.huge, 0 / 0 } do
			local definitions = metadata()
			assert(
				definitions.forms.test_fire_1.evolution,
				"[MythlingEvolution.spec] Missing fixture link"
			).requiredLevel =
				badLevel
			table.insert(cases, definitions)
		end
		for _, badTarget in { "", string.rep("x", 129), "missing", "test_fire_1", "test_water_2" } do
			local definitions = metadata()
			assert(
				definitions.forms.test_fire_1.evolution,
				"[MythlingEvolution.spec] Missing fixture link"
			).targetFormId =
				badTarget
			table.insert(cases, definitions)
		end
		for _, badYield in { -1, math.huge, 0 / 0, 2 ^ 53 } do
			local definitions = metadata()
			definitions.forms.test_fire_2.baseYieldPerHour = badYield
			table.insert(cases, definitions)
		end
		local malformedLink = metadata()
		local malformedForm = malformedLink.forms.test_fire_1 :: any
		malformedForm.evolution = false
		table.insert(cases, malformedLink)
		local missingLevel = metadata()
		local missingLevelForm = missingLevel.forms.test_fire_1 :: any
		missingLevelForm.evolution = { targetFormId = "test_fire_2" }
		table.insert(cases, missingLevel)
		local cycle = metadata()
		assert(cycle.forms.test_fire_2.evolution, "[MythlingEvolution.spec] Missing fixture link").targetFormId =
			"test_fire_1"
		table.insert(cases, cycle)
		local deeperCycle = metadata()
		deeperCycle.forms.test_fire_3.evolution =
			{ targetFormId = "test_fire_2", requiredLevel = 50 }
		table.insert(cases, deeperCycle)
		local changedElement = metadata()
		changedElement.forms.test_fire_3.element = "water"
		table.insert(cases, changedElement)
		local malformedElement = metadata()
		malformedElement.forms.test_fire_2.element = ""
		table.insert(cases, malformedElement)
		for _, definitions in cases do
			expectRejected(state(), 0, request(), "InvalidEvolutionDefinition", definitions)
		end
	end)

	it("rolls back target scaled-Yield overflow and errors in old-state accrual", function()
		local production = state()
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		local definitions = metadata()
		definitions.forms.test_fire_2.baseYieldPerHour = 2 ^ 53 - 1
		expectRejected(production, 1, request(), "ArithmeticOverflow", definitions)
		production.workers.worker_water.pendingXp = 2 ^ 53 - 1
		expectRejected(production, 1, request(), "ArithmeticOverflow")
	end)

	it("matches online and offline old-form settlement through real JSON reconnect", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		local online = copy(production)
		for second = 1, 10 do
			online = accrue(online, second)
		end
		local onlineResult = evolve(online, 10.5)
		local offlineResult = evolve(copy(production), 10.5)
		-- Coalesced and repeated batches can differ by machine-scale fractional roundoff.
		-- Compare only that fraction with tolerance; all other earned state remains exact.
		local comparable = copy(offlineResult)
		for id, shrine in comparable.shrines do
			expect(shrine.progress).toBeCloseTo(onlineResult.shrines[id].progress, 10)
			shrine.progress = onlineResult.shrines[id].progress
		end
		expect(comparable).toEqual(onlineResult)
		expect(offlineResult.workers.worker_water.xp).toBe(10)
		expect(offlineResult.workers.worker_water.pendingXp).toBe(0.5)
		local restored = copy(offlineResult)
		expect(restored).toEqual(offlineResult)
		expect(accrue(restored, 20)).toEqual(accrue(offlineResult, 20))
		expectRejected(restored, 10.5, request(), "FormChanged")
	end)

	it("accepts frozen inputs and returns detached accounting without mutating metadata", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		local definitions = metadata()
		local before = copy(production)
		local metadataBefore = copy(definitions)
		FreezeUtil.DeepFreeze(production)
		FreezeUtil.DeepFreeze(definitions)
		local result = evolve(production, 0, request(), definitions)
		expect(production).toEqual(before)
		expect(definitions).toEqual(metadataBefore)
		expect(result).never.toBe(production)
		expect(result.workers).never.toBe(production.workers)
		expect(result.shrines).never.toBe(production.shrines)
		for id, worker in result.workers do
			expect(worker).never.toBe(production.workers[id])
		end
		for id, shrine in result.shrines do
			expect(shrine).never.toBe(production.shrines[id])
			expect(shrine.workerIdsBySlot).never.toBe(production.shrines[id].workerIdsBySlot)
		end
		result.workers.worker_fire.xp = 99
		result.shrines.shrine_fire.workerIdsBySlot["1"] = nil
		expect(production.workers.worker_fire.xp).toBe(0)
		expect(production.shrines.shrine_fire.workerIdsBySlot["1"]).toBe("worker_fire")
	end)

	it("uses injected thresholds, XP, batch timing, and level scaling", function()
		local production = state()
		for _, worker in production.workers do
			worker.level = 1
		end
		production.nextBatchAt = 2
		production.workers.worker_fire.xp = 9
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		local definitions = metadata()
		definitions.forms.test_fire_1.evolution =
			{ targetFormId = "test_fire_2", requiredLevel = 2 }
		definitions.forms.test_fire_2.evolution =
			{ targetFormId = "test_fire_3", requiredLevel = 4 }
		local productionConfig = { batchIntervalSeconds = 2, baseXpPerSecond = 3 }
		local progressionConfig = { levelCap = 4, xpPerLevel = 10, yieldGainPerLevel = 0.2 }
		local result, evolutionError = MythlingEvolution.Evolve(
			production,
			2,
			request(),
			definitions,
			productionConfig,
			progressionConfig
		)
		assert(
			result,
			`[MythlingEvolution.spec] Expected configured evolution: {tostring(evolutionError)}`
		)
		expect(result.workers.worker_fire.level).toBe(2)
		expect(result.workers.worker_fire.xp).toBe(5)
		expect(result.workers.worker_fire.formId).toBe("test_fire_2")
		expect(result.shrines.shrine_fire.stored).toBe(2)
		expect(result.nextBatchAt).toBe(4)
		local later, accrualError = ShrineAccrual.Accrue(
			result,
			4,
			accountingMetadata(definitions),
			productionConfig,
			progressionConfig
		)
		assert(
			later,
			`[MythlingEvolution.spec] Expected configured accrual: {tostring(accrualError)}`
		)
		expect(later.shrines.shrine_fire.stored).toBe(6)
		expect(later.shrines.shrine_fire.progress).toBeCloseTo(0.8, 10)
		expect(later.workers.worker_fire.xp).toBe(11)
	end)
end)
