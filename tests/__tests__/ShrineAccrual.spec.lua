--!strict
-- ServerStorage/Tests/__tests__/ShrineAccrual.spec

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ShrineAccrual = require(ServerScriptService.Domain.Production.ShrineAccrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): ShrineAccrual.Metadata
	return {
		forms = {
			test_fire_slow = { element = "Fire", baseYieldPerHour = 360 },
			test_fire_medium = { element = "Fire", baseYieldPerHour = 720 },
			test_fire_normal = { element = "Fire", baseYieldPerHour = 3_600 },
			test_fire_fast = { element = "Fire", baseYieldPerHour = 7_200 },
			test_fire_overflow = { element = "Fire", baseYieldPerHour = 10_800 },
			test_water = { element = "Water", baseYieldPerHour = 360 },
		},
		shrines = {
			test_fire_shrine = {
				element = "Fire",
				materialId = "test_ember",
				levels = {
					[1] = { capacity = 10, workerSlots = 1 },
					[2] = { capacity = 20, workerSlots = 2 },
				},
			},
			test_tiny_fire_shrine = {
				element = "Fire",
				materialId = "test_spark",
				levels = {
					[1] = { capacity = 2, workerSlots = 1 },
				},
			},
			test_large_fire_shrine = {
				element = "Fire",
				materialId = "test_cinder",
				levels = {
					[1] = { capacity = 1_000, workerSlots = 1 },
				},
			},
			test_water_shrine = {
				element = "Water",
				materialId = "test_droplet",
				levels = {
					[1] = { capacity = 10, workerSlots = 1 },
				},
			},
		},
	}
end

local function state(formId: string?): ShrineAccrual.State
	return {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		shrines = {
			hearth = {
				shrineId = "test_fire_shrine",
				level = 1,
				workerIds = { "worker_a" },
				stored = 0,
				progress = 0,
				newWork = 0,
			},
		},
		workers = {
			worker_a = {
				formId = formId or "test_fire_slow",
				level = 1,
				xp = 0,
				pendingXp = 0,
			},
		},
	}
end

local function accrue(
	input: ShrineAccrual.State,
	now: number,
	definitions: ShrineAccrual.Metadata?
): ShrineAccrual.State
	local result, accrualError = ShrineAccrual.Accrue(input, now, definitions or metadata())
	assert(result, `[ShrineAccrual.spec] Expected accrual success: {tostring(accrualError)}`)
	expect(accrualError).toBeNil()
	return result
end

local function expectRejected(input: any, now: any, definitions: any)
	local result, accrualError = ShrineAccrual.Accrue(input, now, definitions)
	expect(result).toBeNil()
	expect(type(accrualError)).toBe("string")
	expect(#(accrualError :: string) > 0).toBe(true)
end

describe("ShrineAccrual", function()
	it("retains tiny positive Yield rather than rounding every batch down to zero", function()
		local definitions = metadata()
		definitions.forms.test_fire_slow.baseYieldPerHour = 3.6e-10
		local initial = state()
		local progression = { levelCap = 100, xpPerLevel = 120, yieldGainPerLevel = 0 }
		local production = { batchIntervalSeconds = 1, baseXpPerSecond = 0 }
		local online = initial
		for second = 1, 100 do
			online = assert(
				ShrineAccrual.Accrue(online, second, definitions, production, progression),
				"[ShrineAccrual.spec] Expected tiny-Yield accrual"
			)
		end
		local offline = assert(
			ShrineAccrual.Accrue(initial, 100, definitions, production, progression),
			"[ShrineAccrual.spec] Expected tiny-Yield offline accrual"
		)
		expect(online.shrines.hearth.progress > 0).toBe(true)
		expect(online.shrines.hearth.progress / 1e-11).toBeCloseTo(1, 10)
		expect(offline.shrines.hearth.progress / 1e-11).toBeCloseTo(1, 10)
	end)

	it(
		"combines retained progress, prior new work, and fractional current work at a batch",
		function()
			local input = state()
			input.shrines.hearth.progress = 0.8
			input.shrines.hearth.newWork = 0.1

			local result = accrue(input, 1)

			expect(result.shrines.hearth.stored).toBe(1)
			expect(result.shrines.hearth.progress).toBeCloseTo(0)
			expect(result.shrines.hearth.newWork).toBe(0)
			expect(result.workers.worker_a.xp).toBe(1)
			expect(result.workers.worker_a.pendingXp).toBe(0)
		end
	)

	it("preserves each input set's production and XP when workers change mid-batch", function()
		local firstInput = state("test_fire_normal")
		firstInput.workers.worker_b = {
			formId = "test_fire_fast",
			level = 1,
			xp = 0,
			pendingXp = 0,
		}
		local halfway = accrue(firstInput, 0.5)
		expect(halfway.shrines.hearth.newWork).toBeCloseTo(0.5)
		expect(halfway.workers.worker_a.pendingXp).toBeCloseTo(0.5)

		halfway.shrines.hearth.workerIds = { "worker_b" }
		local resolved = accrue(halfway, 1)

		expect(resolved.shrines.hearth.stored).toBe(1)
		expect(resolved.shrines.hearth.progress).toBeCloseTo(0.5)
		expect(resolved.shrines.hearth.newWork).toBe(0)
		expect(resolved.workers.worker_a.xp).toBeCloseTo(0.5)
		expect(resolved.workers.worker_a.pendingXp).toBe(0)
		expect(resolved.workers.worker_b.xp).toBeCloseTo(0.5)
		expect(resolved.workers.worker_b.pendingXp).toBe(0)
	end)

	it("keeps unfinished production at its original Shrine when a worker moves", function()
		local input = state("test_fire_normal")
		input.shrines.destination = {
			shrineId = "test_fire_shrine",
			level = 1,
			workerIds = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}
		local halfway = accrue(input, 0.5)
		halfway.shrines.hearth.workerIds = {}
		halfway.shrines.destination.workerIds = { "worker_a" }

		local resolved = accrue(halfway, 1)

		expect(resolved.shrines.hearth.progress).toBeCloseTo(0.5)
		expect(resolved.shrines.destination.progress).toBeCloseTo(0.5)
		expect(resolved.workers.worker_a.xp).toBe(1)
	end)

	it("awards pending worker XP even after its source Shrine is deleted", function()
		local halfway = accrue(state("test_fire_normal"), 0.5)
		expect(halfway.workers.worker_a.pendingXp).toBeCloseTo(0.5)
		halfway.shrines.hearth = nil

		local resolved = accrue(halfway, 1)

		expect(resolved.shrines.hearth).toBeNil()
		expect(resolved.workers.worker_a.xp).toBeCloseTo(0.5)
		expect(resolved.workers.worker_a.pendingXp).toBe(0)
	end)

	it("sums concurrent worker Yield while granting each worker independent XP", function()
		local input = state()
		input.shrines.hearth.level = 2
		input.shrines.hearth.workerIds = { "worker_a", "worker_b" }
		input.workers.worker_b = {
			formId = "test_fire_medium",
			level = 1,
			xp = 0,
			pendingXp = 0,
		}

		local result = accrue(input, 1)

		expect(result.shrines.hearth.stored).toBe(0)
		expect(result.shrines.hearth.progress).toBeCloseTo(0.3)
		expect(result.workers.worker_a.xp).toBe(1)
		expect(result.workers.worker_b.xp).toBe(1)
	end)

	it("grants the filling batch's XP, discards overflow, then pauses while full", function()
		local input = state("test_fire_overflow")
		input.shrines.hearth.shrineId = "test_tiny_fire_shrine"
		input.shrines.hearth.stored = 1
		input.shrines.hearth.progress = 0.8

		local filled = accrue(input, 1)

		expect(filled.shrines.hearth.stored).toBe(2)
		expect(filled.shrines.hearth.progress).toBe(0)
		expect(filled.shrines.hearth.newWork).toBe(0)
		expect(filled.workers.worker_a.xp).toBe(1)
		local paused = accrue(filled, 10)
		expect(paused.shrines.hearth).toEqual(filled.shrines.hearth)
		expect(paused.workers.worker_a).toEqual(filled.workers.worker_a)
		expect(paused.lastAccruedAt).toBe(10)
		expect(paused.nextBatchAt).toBe(11)
	end)

	it("preserves retained progress and over-capacity storage after a balance reduction", function()
		local input = state("test_fire_normal")
		input.shrines.hearth.shrineId = "test_tiny_fire_shrine"
		input.shrines.hearth.stored = 3
		input.shrines.hearth.progress = 0.75

		local result = accrue(input, 10)

		expect(result.shrines.hearth.stored).toBe(3)
		expect(result.shrines.hearth.progress).toBe(0.75)
		expect(result.shrines.hearth.newWork).toBe(0)
		expect(result.workers.worker_a.xp).toBe(0)
		expect(result.workers.worker_a.pendingXp).toBe(0)
	end)

	it("never catches up intervals spent empty or full after work can resume", function()
		local empty = state()
		empty.shrines.hearth.workerIds = {}
		local emptyElapsed = accrue(empty, 10)
		emptyElapsed.shrines.hearth.workerIds = { "worker_a" }
		local emptyResumed = accrue(emptyElapsed, 11)
		expect(emptyResumed.shrines.hearth.progress).toBeCloseTo(0.1)
		expect(emptyResumed.workers.worker_a.xp).toBe(1)

		local full = state()
		full.shrines.hearth.stored = 10
		local fullElapsed = accrue(full, 10)
		fullElapsed.shrines.hearth.stored = 0
		local fullResumed = accrue(fullElapsed, 11)
		expect(fullResumed.shrines.hearth.progress).toBeCloseTo(0.1)
		expect(fullResumed.workers.worker_a.xp).toBe(1)
	end)

	it("produces identical results through one-second online ticks and one offline span", function()
		local initial = state()
		initial.shrines.hearth.shrineId = "test_large_fire_shrine"
		local online = copy(initial)
		for second = 1, 360 do
			online = accrue(online, second)
		end
		local offline = accrue(copy(initial), 360)

		expect(offline.lastAccruedAt).toBe(online.lastAccruedAt)
		expect(offline.nextBatchAt).toBe(online.nextBatchAt)
		expect(offline.shrines.hearth.stored).toBe(online.shrines.hearth.stored)
		expect(offline.shrines.hearth.progress).toBeCloseTo(online.shrines.hearth.progress)
		expect(offline.shrines.hearth.newWork).toBeCloseTo(online.shrines.hearth.newWork)
		expect(offline.workers.worker_a).toEqual(online.workers.worker_a)
		expect(offline.workers.worker_a.level).toBe(3)
		expect(offline.workers.worker_a.xp).toBe(0)
	end)

	it("coalesces a century of empty elapsed time without changing earned state", function()
		local input = state()
		input.shrines.hearth.workerIds = {}
		local hundredYears = 100 * 365 * 24 * 60 * 60

		local result = accrue(input, hundredYears)

		expect(result.lastAccruedAt).toBe(hundredYears)
		expect(result.nextBatchAt).toBe(hundredYears + 1)
		expect(result.shrines.hearth.stored).toBe(0)
		expect(result.shrines.hearth.progress).toBe(0)
		expect(result.shrines.hearth.newWork).toBe(0)
		expect(result.workers.worker_a).toEqual(input.workers.worker_a)
	end)

	it("applies a level earned at one boundary only to later production batches", function()
		local input = state()
		input.workers.worker_a.xp = 119

		local result = accrue(input, 2)

		expect(result.workers.worker_a.level).toBe(2)
		expect(result.workers.worker_a.xp).toBe(1)
		expect(result.workers.worker_a.pendingXp).toBe(0)
		expect(result.shrines.hearth.progress).toBeCloseTo(0.201)
	end)

	it("honors earned pending XP at the cap but adds no new capped-time XP", function()
		local input = state("test_fire_normal")
		input.shrines.hearth.shrineId = "test_large_fire_shrine"
		input.shrines.hearth.workerIds = {}
		input.workers.worker_a.level = 99
		input.workers.worker_a.xp = 11_879
		input.workers.worker_a.pendingXp = 2

		local capped = accrue(input, 1)

		expect(capped.workers.worker_a.level).toBe(100)
		expect(capped.workers.worker_a.xp).toBe(1)
		expect(capped.workers.worker_a.pendingXp).toBe(0)
		capped.shrines.hearth.workerIds = { "worker_a" }
		local later = accrue(capped, 11)
		expect(later.workers.worker_a.level).toBe(100)
		expect(later.workers.worker_a.xp).toBe(1)
		expect(later.workers.worker_a.pendingXp).toBe(0)
		expect(later.shrines.hearth.stored > capped.shrines.hearth.stored).toBe(true)
	end)

	it("round-trips plain saved state and never replays an already-settled timestamp", function()
		local initial = state()
		local first = accrue(initial, 10)
		local encoded = HttpService:JSONEncode(first)
		local restored = (HttpService:JSONDecode(encoded) :: unknown) :: ShrineAccrual.State
		expect(restored).toEqual(first)

		local repeated = accrue(restored, 10)
		expect(repeated).toEqual(restored)
		expect(repeated).never.toBe(restored)
		expect(repeated.shrines).never.toBe(restored.shrines)
		expect(repeated.workers).never.toBe(restored.workers)
		local continued = accrue(repeated, 20)
		local uninterrupted = accrue(copy(initial), 20)
		expect(continued).toEqual(uninterrupted)
	end)

	it(
		"returns detached no-op states for repeated and older times without mutating inputs",
		function()
			local input = state()
			input.lastAccruedAt = 10
			input.nextBatchAt = 11
			input.shrines.hearth.progress = 0.25
			input.workers.worker_a.pendingXp = 0.5
			local before = copy(input)

			for _, now in { 10, 9 } do
				local result = accrue(input, now)
				expect(result).toEqual(input)
				expect(result).never.toBe(input)
				expect(result.shrines.hearth).never.toBe(input.shrines.hearth)
				expect(result.workers.worker_a).never.toBe(input.workers.worker_a)
				result.shrines.hearth.progress = 0.75
				result.workers.worker_a.xp = 50
				expect(input).toEqual(before)
			end
		end
	)

	it("never mutates input state or metadata during ordinary accrual", function()
		local input = state()
		local definitions = metadata()
		local stateBefore = copy(input)
		local metadataBefore = copy(definitions)

		local result = accrue(input, 1, definitions)

		expect(input).toEqual(stateBefore)
		expect(definitions).toEqual(metadataBefore)
		expect(result).never.toBe(input)
		expect(result.shrines.hearth).never.toBe(input.shrines.hearth)
		expect(result.workers.worker_a).never.toBe(input.workers.worker_a)
	end)

	it("rejects unknown definitions and element-mismatched assignments", function()
		local unknownShrine = state()
		unknownShrine.shrines.hearth.shrineId = "missing_shrine"
		expectRejected(unknownShrine, 1, metadata())

		local unknownForm = state("missing_form")
		expectRejected(unknownForm, 1, metadata())

		local mismatch = state("test_water")
		expectRejected(mismatch, 1, metadata())
	end)

	it("rejects malformed state and invalid metadata without partial results", function()
		local negativeProgress = state()
		negativeProgress.shrines.hearth.progress = -0.01
		expectRejected(negativeProgress, 1, metadata())

		local invalidTime = state()
		invalidTime.lastAccruedAt = 0 / 0
		expectRejected(invalidTime, 1, metadata())

		local unresolvedBoundary = state()
		unresolvedBoundary.nextBatchAt = unresolvedBoundary.lastAccruedAt
		expectRejected(unresolvedBoundary, 1, metadata())

		local unresolvedLevel = state()
		unresolvedLevel.workers.worker_a.xp = 120
		expectRejected(unresolvedLevel, 1, metadata())

		local invalidMetadata = metadata()
		invalidMetadata.forms.test_fire_slow.baseYieldPerHour = -1
		expectRejected(state(), 1, invalidMetadata)

		expectRejected(state(), 0 / 0, metadata())
	end)

	it("rejects duplicate, cross-Shrine, and over-capacity worker assignments", function()
		local duplicate = state()
		duplicate.shrines.hearth.level = 2
		duplicate.shrines.hearth.workerIds = { "worker_a", "worker_a" }
		expectRejected(duplicate, 1, metadata())

		local crossShrine = state()
		crossShrine.shrines.second = {
			shrineId = "test_fire_shrine",
			level = 1,
			workerIds = { "worker_a" },
			stored = 0,
			progress = 0,
			newWork = 0,
		}
		expectRejected(crossShrine, 1, metadata())

		local tooMany = state()
		tooMany.workers.worker_b = {
			formId = "test_fire_slow",
			level = 1,
			xp = 0,
			pendingXp = 0,
		}
		tooMany.shrines.hearth.workerIds = { "worker_a", "worker_b" }
		expectRejected(tooMany, 1, metadata())
	end)
end)
