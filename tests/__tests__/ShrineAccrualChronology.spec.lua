--!strict
-- ServerStorage/Tests/__tests__/ShrineAccrualChronology.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local MythlingProgression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local ShrineAccrual = require(ServerScriptService.Domain.Production.ShrineAccrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local SECONDS_PER_HOUR = 3_600
local CENTURY_SECONDS = 100 * 365 * 24 * SECONDS_PER_HOUR

local FORM_IDS: { [string]: { string } } = {
	Fire = { "fire_common", "fire_rare", "fire_epic" },
	Water = { "water_common", "water_rare", "water_epic" },
	Earth = { "earth_common", "earth_rare", "earth_epic" },
}
local SMALL_SHRINE_IDS: { [string]: string } = {
	Fire = "small_fire_shrine",
	Water = "small_water_shrine",
	Earth = "small_earth_shrine",
}
local SMALL_CAPACITIES: { [string]: number } = { Fire = 3, Water = 5, Earth = 7 }
local FRACTIONS = { 0, 0.125, 0.5, 0.875 }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): ShrineAccrual.Metadata
	return {
		forms = {
			fire_common = { element = "Fire", baseYieldPerHour = 12 },
			fire_rare = { element = "Fire", baseYieldPerHour = 18 },
			fire_epic = { element = "Fire", baseYieldPerHour = 32 },
			fire_zero = { element = "Fire", baseYieldPerHour = 0 },
			water_common = { element = "Water", baseYieldPerHour = 12 },
			water_rare = { element = "Water", baseYieldPerHour = 18 },
			water_epic = { element = "Water", baseYieldPerHour = 32 },
			earth_common = { element = "Earth", baseYieldPerHour = 12 },
			earth_rare = { element = "Earth", baseYieldPerHour = 18 },
			earth_epic = { element = "Earth", baseYieldPerHour = 32 },
		},
		shrines = {
			ample_fire_shrine = {
				element = "Fire",
				materialId = "ember",
				levels = { [1] = { capacity = 100_000, workerSlots = 3 } },
			},
			daily_fire_shrine = {
				element = "Fire",
				materialId = "ember",
				levels = { [1] = { capacity = 3_600, workerSlots = 3 } },
			},
			small_fire_shrine = {
				element = "Fire",
				materialId = "ember",
				levels = { [1] = { capacity = SMALL_CAPACITIES.Fire, workerSlots = 1 } },
			},
			small_water_shrine = {
				element = "Water",
				materialId = "droplet",
				levels = { [1] = { capacity = SMALL_CAPACITIES.Water, workerSlots = 1 } },
			},
			small_earth_shrine = {
				element = "Earth",
				materialId = "stone",
				levels = { [1] = { capacity = SMALL_CAPACITIES.Earth, workerSlots = 1 } },
			},
		},
	}
end

local function oneWorkerState(
	formId: string,
	shrineId: string,
	level: number?,
	xp: number?,
	batchIntervalSeconds: number?
): ShrineAccrual.State
	local interval = batchIntervalSeconds or Production.batchIntervalSeconds
	return {
		lastAccruedAt = 0,
		nextBatchAt = interval,
		shrines = {
			hearth = {
				shrineId = shrineId,
				level = 1,
				workerIdsBySlot = { ["1"] = "worker" },
				stored = 0,
				progress = 0,
				newWork = 0,
			},
		},
		workers = {
			worker = {
				formId = formId,
				level = level or 1,
				xp = xp or 0,
				pendingXp = 0,
			},
		},
	}
end

local function accrue(
	input: ShrineAccrual.State,
	now: number,
	definitions: ShrineAccrual.Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): ShrineAccrual.State
	local result, accrualError =
		ShrineAccrual.Accrue(input, now, definitions, production, progression)
	return assert(
		result,
		`[ShrineAccrualChronology.spec] Expected accrual success: {tostring(accrualError)}`
	)
end

local function milestoneSeconds(targetLevel: number): number
	local seconds = 0
	for level = 1, targetLevel - 1 do
		seconds += MythlingProgression.xpPerLevel * level
	end
	return seconds
end

local function milestoneWork(baseYieldPerHour: number, targetLevel: number): number
	local work = 0
	for level = 1, targetLevel - 1 do
		local duration = MythlingProgression.xpPerLevel * level
		local multiplier = 1 + MythlingProgression.yieldGainPerLevel * (level - 1)
		work += baseYieldPerHour * multiplier * duration / SECONDS_PER_HOUR
	end
	return work
end

local function snapWhole(value: number): number
	local nearest = math.round(value)
	if nearest > 0 and math.abs(value - nearest) <= math.min(1e-9, 1e-12 * math.abs(value)) then
		return nearest
	end
	return value
end

local function elapsedXpFromLevel(startLevel: number, level: number, xp: number): number
	local elapsed = xp
	for completedLevel = startLevel, level - 1 do
		elapsed += MythlingProgression.xpPerLevel * completedLevel
	end
	return elapsed
end

local function workForElapsed(
	baseYieldPerHour: number,
	startLevel: number,
	startXp: number,
	elapsedSeconds: number
): number
	local level = startLevel
	local xp = startXp
	local remaining = elapsedSeconds
	local work = 0
	while remaining > 0 do
		local untilLevel = MythlingProgression.xpPerLevel * level - xp
		local duration = math.min(remaining, untilLevel)
		local multiplier = 1 + MythlingProgression.yieldGainPerLevel * (level - 1)
		work += baseYieldPerHour * multiplier * duration / SECONDS_PER_HOUR
		xp += duration
		remaining -= duration
		if xp >= MythlingProgression.xpPerLevel * level then
			xp -= MythlingProgression.xpPerLevel * level
			level += 1
		end
	end
	return work
end

local function expectClose(left: number, right: number, message: string)
	assert(
		math.abs(left - right) <= 1e-8,
		`[ShrineAccrualChronology.spec] {message}: expected {right}, received {left}`
	)
end

describe("ShrineAccrual chronological launch tuning", function()
	it("matches independently summed 12/18/32 Yield through levels 6, 40, and 100", function()
		local definitions = metadata()
		for _, form in
			{
				{ id = "fire_common", baseYieldPerHour = 12 },
				{ id = "fire_rare", baseYieldPerHour = 18 },
				{ id = "fire_epic", baseYieldPerHour = 32 },
			}
		do
			for _, targetLevel in { 6, 40, 100 } do
				local duration = milestoneSeconds(targetLevel)
				local expectedWork = snapWhole(milestoneWork(form.baseYieldPerHour, targetLevel))
				local result =
					accrue(oneWorkerState(form.id, "ample_fire_shrine"), duration, definitions)
				local shrine = result.shrines.hearth
				local worker = result.workers.worker
				local expectedStored = math.floor(expectedWork)

				expect(worker.level).toBe(targetLevel)
				expect(worker.xp).toBe(0)
				expect(worker.pendingXp).toBe(0)
				expect(shrine.stored).toBe(expectedStored)
				expectClose(
					shrine.progress,
					expectedWork - expectedStored,
					`{form.id} level {targetLevel} fractional work`
				)
				expect(shrine.newWork).toBe(0)
				expect(result.lastAccruedAt).toBe(duration)
				expect(result.nextBatchAt).toBe(duration + Production.batchIntervalSeconds)
			end
		end

		expect(milestoneSeconds(6)).toBe(1_800)
		expect(milestoneSeconds(40)).toBe(93_600)
		expect(milestoneSeconds(100)).toBe(594_000)
	end)

	it("fills a level-3 store with three leveling Epics near 24.2 hours, then pauses", function()
		local definitions = metadata()
		local initial = oneWorkerState("fire_epic", "daily_fire_shrine", 50, 0)
		initial.shrines.hearth.workerIdsBySlot = {
			["1"] = "worker_a",
			["2"] = "worker_b",
			["3"] = "worker_c",
		}
		initial.workers = {
			worker_a = { formId = "fire_epic", level = 50, xp = 0, pendingXp = 0 },
			worker_b = { formId = "fire_epic", level = 50, xp = 0, pendingXp = 0 },
			worker_c = { formId = "fire_epic", level = 50, xp = 0, pendingXp = 0 },
		}

		local filled = accrue(copy(initial), 30 * SECONDS_PER_HOUR, definitions)
		expect(filled.shrines.hearth.stored).toBe(3_600)
		local worker = filled.workers.worker_a
		local eligibleSeconds = elapsedXpFromLevel(50, worker.level, worker.xp)
		local eligibleHours = eligibleSeconds / SECONDS_PER_HOUR
		expect(eligibleHours > 24.1 and eligibleHours < 24.3).toBe(true)
		expect(worker).toEqual(filled.workers.worker_b)
		expect(worker).toEqual(filled.workers.worker_c)
		expect(3 * workForElapsed(32, 50, 0, eligibleSeconds) >= 3_600).toBe(true)
		expect(3 * workForElapsed(32, 50, 0, eligibleSeconds - 1) < 3_600).toBe(true)

		local afterCentury = accrue(filled, CENTURY_SECONDS, definitions)
		expect(afterCentury.shrines.hearth).toEqual(filled.shrines.hearth)
		expect(afterCentury.workers).toEqual(filled.workers)
		expect(afterCentury.lastAccruedAt).toBe(CENTURY_SECONDS)
		expect(afterCentury.nextBatchAt).toBe(CENTURY_SECONDS + 1)

		local directCentury = accrue(copy(initial), CENTURY_SECONDS, definitions)
		expect(directCentury.shrines.hearth).toEqual(afterCentury.shrines.hearth)
		expect(directCentury.workers).toEqual(afterCentury.workers)
	end)

	it("matches per-second accrual across 20 seeded multi-Shrine offline cases", function()
		local definitions = metadata()
		local seed = 7_314_159
		local function nextInt(maximum: number): number
			seed = (seed * 48_271) % 2_147_483_647
			return seed % maximum
		end

		for case = 1, 20 do
			local shrineCount = 2 + nextInt(2)
			local initial: ShrineAccrual.State = {
				lastAccruedAt = 0,
				nextBatchAt = 1,
				shrines = {},
				workers = {},
			}
			for index = 1, shrineCount do
				local element = ({ "Fire", "Water", "Earth" })[index]
				local workerId = `worker_{index}`
				local shrineInstanceId = `shrine_{index}`
				local level = 1 + nextInt(60)
				local threshold = MythlingProgression.xpPerLevel * level
				local fraction = FRACTIONS[1 + nextInt(#FRACTIONS)]
				local formId = FORM_IDS[element][1 + nextInt(3)]
				local capacity = SMALL_CAPACITIES[element]
				initial.workers[workerId] = {
					formId = formId,
					level = level,
					xp = nextInt(threshold) + fraction,
					pendingXp = nextInt(4) + FRACTIONS[1 + nextInt(#FRACTIONS)],
				}
				initial.shrines[shrineInstanceId] = {
					shrineId = SMALL_SHRINE_IDS[element],
					level = 1,
					workerIdsBySlot = { ["1"] = workerId },
					stored = nextInt(capacity),
					progress = FRACTIONS[1 + nextInt(#FRACTIONS)],
					newWork = FRACTIONS[1 + nextInt(#FRACTIONS)] / 4,
				}
			end

			local offline = accrue(copy(initial), 600, definitions)
			local online = copy(initial)
			for second = 1, 600 do
				online = accrue(online, second, definitions)
			end

			expect(offline.lastAccruedAt).toBe(online.lastAccruedAt)
			expect(offline.nextBatchAt).toBe(online.nextBatchAt)
			for id, offlineShrine in offline.shrines do
				local onlineShrine = online.shrines[id]
				expect(offlineShrine.stored).toBe(onlineShrine.stored)
				expectClose(
					offlineShrine.progress,
					onlineShrine.progress,
					`case {case} {id} progress`
				)
				expectClose(
					offlineShrine.newWork,
					onlineShrine.newWork,
					`case {case} {id} new work`
				)
			end
			for id, offlineWorker in offline.workers do
				local onlineWorker = online.workers[id]
				expect(offlineWorker.level).toBe(onlineWorker.level)
				expectClose(offlineWorker.xp, onlineWorker.xp, `case {case} {id} XP`)
				expectClose(
					offlineWorker.pendingXp,
					onlineWorker.pendingXp,
					`case {case} {id} pending XP`
				)
			end
		end
	end)

	it("retains mid-batch form work and progression with configurable sub-unit XP", function()
		local definitions = metadata()
		local production = { batchIntervalSeconds = 10, baseXpPerSecond = 0.25 }
		local initial = oneWorkerState("fire_common", "ample_fire_shrine", 6, 12.25, 10)
		local beforeEvolution = accrue(initial, 4, definitions, production)
		expect(beforeEvolution.shrines.hearth.newWork).toBeCloseTo(0.014)
		expect(beforeEvolution.workers.worker.pendingXp).toBe(1)
		expect(beforeEvolution.workers.worker.level).toBe(6)
		expect(beforeEvolution.workers.worker.xp).toBe(12.25)

		beforeEvolution.workers.worker.formId = "fire_epic"
		local evolved = accrue(beforeEvolution, 10, definitions, production)
		expect(evolved.shrines.hearth.stored).toBe(0)
		expect(evolved.shrines.hearth.progress).toBeCloseTo(0.07)
		expect(evolved.shrines.hearth.newWork).toBe(0)
		expect(evolved.workers.worker.formId).toBe("fire_epic")
		expect(evolved.workers.worker.level).toBe(6)
		expect(evolved.workers.worker.xp).toBeCloseTo(14.75)
		expect(evolved.workers.worker.pendingXp).toBe(0)
	end)

	it("awards working XP when a valid form has zero Yield", function()
		local definitions = metadata()
		local result = accrue(
			oneWorkerState("fire_zero", "ample_fire_shrine"),
			MythlingProgression.xpPerLevel,
			definitions
		)
		expect(result.shrines.hearth.stored).toBe(0)
		expect(result.shrines.hearth.progress).toBe(0)
		expect(result.workers.worker.level).toBe(2)
		expect(result.workers.worker.xp).toBe(0)
	end)
end)
