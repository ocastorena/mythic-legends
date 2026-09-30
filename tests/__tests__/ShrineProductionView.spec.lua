--!strict
-- ServerStorage/Tests/__tests__/ShrineProductionView.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Progression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function fixture(rate: number?)
	local state: ShrineAccrual.State = {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		workers = { worker = { formId = "form", level = 1, xp = 0, pendingXp = 0 } },
		shrines = {
			owned = {
				shrineId = "shrine",
				level = 1,
				stored = 0,
				progress = 0,
				newWork = 0,
				workerIdsBySlot = { ["1"] = "worker" },
			},
		},
	}
	local metadata: ShrineAccrual.Metadata = {
		forms = { form = { element = "Fire", baseYieldPerHour = rate or 12 } },
		shrines = {
			shrine = {
				element = "Fire",
				materialId = "fire_material",
				levels = { [1] = { capacity = 300, workerSlots = 3 } },
			},
		},
	}
	return { state = state, metadata = metadata }
end

local function read(
	state: ShrineAccrual.State,
	metadata: ShrineAccrual.Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): ShrineAccrual.ProductionView
	local view, problem =
		ShrineAccrual.ReadProduction(state, "owned", metadata, production, progression)
	expect(problem).toBeNil()
	return (assert(view, "[ShrineProductionView.spec] Expected production view"))
end

describe("Shrine production view", function()
	it(
		"rounds the three trial rates to configured delivery batches without inventing item timers",
		function()
			for _, trial in
				{
					{ rate = 12, seconds = 300 },
					{ rate = 18, seconds = 200 },
					{ rate = 32, seconds = 113 },
				}
			do
				local f = fixture(trial.rate)
				local view = read(f.state, f.metadata)
				expect(view).toEqual({
					yieldPerHour = trial.rate,
					isProducing = true,
					productionProgress = 0,
					estimatedSecondsToNextMaterial = trial.seconds,
				})
			end
			local epic = fixture(32)
			epic.state.nextBatchAt = 0.5
			local view =
				read(epic.state, epic.metadata, { batchIntervalSeconds = 0.5, baseXpPerSecond = 1 })
			expect(view.estimatedSecondsToNextMaterial).toBe(112.5)
		end
	)

	it(
		"preserves the remaining fractional batch phase and combines all retained earned work",
		function()
			local f = fixture(32)
			f.state.lastAccruedAt = 100.25
			f.state.nextBatchAt = 101
			f.state.shrines.owned.progress = 0.25
			f.state.shrines.owned.newWork = 0.25
			local view = read(f.state, f.metadata)
			expect(view.productionProgress).toBe(0.5)
			expect(view.estimatedSecondsToNextMaterial).toBe(56.75)
			-- The answer is relative to the saved cursor; the cursor's absolute epoch is irrelevant.
			f.state.lastAccruedAt += 100_000
			f.state.nextBatchAt += 100_000
			expect(read(f.state, f.metadata)).toEqual(view)
		end
	)

	it(
		"retains paused progress and still shows an already-earned whole item at the next batch",
		function()
			local f = fixture()
			f.state.lastAccruedAt = 0.25
			f.state.nextBatchAt = 1
			f.state.shrines.owned.workerIdsBySlot = {}
			f.state.shrines.owned.progress = 0.4
			f.state.shrines.owned.newWork = 0.3
			local paused = read(f.state, f.metadata)
			expect(paused.yieldPerHour).toBe(0)
			expect(paused.isProducing).toBe(false)
			expect(paused.productionProgress).toBeCloseTo(0.7, 12)
			expect(paused.estimatedSecondsToNextMaterial).toBeNil()
			f.state.shrines.owned.newWork = 0.6
			local pending = read(f.state, f.metadata)
			expect(pending.productionProgress).toBe(1)
			expect(pending.isProducing).toBe(false)
			expect(pending.estimatedSecondsToNextMaterial).toBe(0.75)
			f.state.shrines.owned.newWork = 3
			expect(read(f.state, f.metadata).estimatedSecondsToNextMaterial).toBe(0.75)
		end
	)

	it(
		"keeps nominal Yield and retained progress visible at full or retained over-capacity storage",
		function()
			local f = fixture(32)
			f.state.workers.worker.level = 50
			f.state.shrines.owned.progress = 0.3
			f.state.shrines.owned.newWork = 0.4
			for _, stored in { 300, 350 } do
				f.state.shrines.owned.stored = stored
				local view = read(f.state, f.metadata)
				expect(view.yieldPerHour).toBeCloseTo(47.68, 10)
				expect(view.productionProgress).toBeCloseTo(0.7, 12)
				expect(view.isProducing).toBe(false)
				expect(view.estimatedSecondsToNextMaterial).toBeNil()
			end
			f.state.shrines.owned.newWork = 1
			expect(read(f.state, f.metadata).productionProgress).toBe(1)
		end
	)

	it(
		"uses shared linear level scaling and sums assigned workers only, even without a full team",
		function()
			local f = fixture(12)
			f.state.workers.worker.level = 50
			f.state.workers.second = { formId = "form", level = 100, xp = 0, pendingXp = 0 }
			f.state.workers.unassigned = { formId = "form", level = 100, xp = 0, pendingXp = 0 }
			f.state.shrines.owned.workerIdsBySlot["3"] = "second"
			local view = read(f.state, f.metadata)
			expect(view.yieldPerHour).toBeCloseTo(
				12 * (1 + Progression.yieldGainPerLevel * 49)
					+ 12 * (1 + Progression.yieldGainPerLevel * 99),
				10
			)
			local changed = read(
				f.state,
				f.metadata,
				nil,
				{ levelCap = 100, xpPerLevel = 120, yieldGainPerLevel = 0.02 }
			)
			expect(changed.yieldPerHour).toBeCloseTo(12 * 1.98 + 12 * 2.98, 10)
			expect(
				(changed.estimatedSecondsToNextMaterial :: number)
					< view.estimatedSecondsToNextMaterial :: number
			).toBe(true)
			local zero = fixture(0)
			expect(read(zero.state, zero.metadata)).toEqual({
				yieldPerHour = 0,
				isProducing = false,
				productionProgress = 0,
			})
		end
	)

	it(
		"corrects machine noise near integer work or batch counts but keeps meaningful fractions",
		function()
			for _, rawSeconds in { 1.0000000000000002, 3.000000000000001 } do
				local f = fixture(3600 / rawSeconds)
				expect(read(f.state, f.metadata).estimatedSecondsToNextMaterial).toBe(
					math.round(rawSeconds)
				)
			end
			local meaningful = fixture(3600 / 3.0000001)
			expect(read(meaningful.state, meaningful.metadata).estimatedSecondsToNextMaterial).toBe(
				4
			)
			local pending = fixture(0)
			pending.state.shrines.owned.progress = 1 - 5e-13
			expect(read(pending.state, pending.metadata).estimatedSecondsToNextMaterial).toBe(1)
			pending.state.shrines.owned.progress = 1 - 5e-10
			expect(read(pending.state, pending.metadata).estimatedSecondsToNextMaterial).toBeNil()
			local decimalPhase = fixture(7_200_000)
			decimalPhase.state.lastAccruedAt = 1
			decimalPhase.state.nextBatchAt = 1.1
			local view = read(
				decimalPhase.state,
				decimalPhase.metadata,
				{ batchIntervalSeconds = 0.1, baseXpPerSecond = 1 }
			)
			expect(view.estimatedSecondsToNextMaterial).toBeCloseTo(0.1, 10)
		end
	)

	it(
		"rejects invalid numbers, missing selections, and unsafe total work, Yield, or estimate arithmetic",
		function()
			local f = fixture()
			local absent, absentCode = ShrineAccrual.ReadProduction(f.state, "missing", f.metadata)
			expect(absent).toBeNil()
			expect(absentCode).toBe("ShrineNotOwned")
			local invalid, invalidCode = ShrineAccrual.ReadProduction(f.state, "", f.metadata)
			expect(invalid).toBeNil()
			expect(invalidCode).toBe("InvalidRequest")
			f.metadata.forms.form.baseYieldPerHour = 0 / 0
			local bad, badCode = ShrineAccrual.ReadProduction(f.state, "owned", f.metadata)
			expect(bad).toBeNil()
			expect(badCode).toBe("InvalidForm")
			for _, scenario in { "work", "yield", "rate", "batches" } do
				local overflow = fixture()
				local production: ShrineAccrual.ProductionConfig? = nil
				if scenario == "work" then
					overflow.state.shrines.owned.progress = 0.5
					overflow.state.shrines.owned.newWork = 9007199254740991
				elseif scenario == "yield" then
					overflow.metadata.forms.form.baseYieldPerHour = 9007199254740991
					overflow.state.workers.second =
						{ formId = "form", level = 1, xp = 0, pendingXp = 0 }
					overflow.state.shrines.owned.workerIdsBySlot["2"] = "second"
				elseif scenario == "rate" then
					overflow.metadata.forms.form.baseYieldPerHour = 1e-15
				else
					overflow.state.nextBatchAt = 1e-20
					production = { batchIntervalSeconds = 1e-20, baseXpPerSecond = 1 }
				end
				local result, problem = ShrineAccrual.ReadProduction(
					overflow.state,
					"owned",
					overflow.metadata,
					production
				)
				expect(result).toBeNil()
				expect(problem).toBe("ArithmeticOverflow")
			end
		end
	)

	it(
		"reads frozen inputs without changing state, metadata, progression, or the saved schedule",
		function()
			local f = fixture(32)
			f.state.shrines.owned.progress = 0.4
			f.state.shrines.owned.newWork = 0.1
			f.state.workers.worker.pendingXp = 0.5
			local before = copy(f)
			FreezeUtil.DeepFreeze(f.state)
			FreezeUtil.DeepFreeze(f.metadata)
			local view = read(f.state, f.metadata)
			view.yieldPerHour = 0
			view.productionProgress = 0
			expect(read(f.state, f.metadata).productionProgress).toBe(0.5)
			expect(f).toEqual(before)
		end
	)
end)
