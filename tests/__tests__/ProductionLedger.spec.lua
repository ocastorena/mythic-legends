--!strict
-- ServerStorage/Tests/__tests__/ProductionLedger.spec

local HttpService = game:GetService("HttpService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ProductionLedger = require(game:GetService("ServerScriptService").Services.ProductionService.ProductionLedger)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function emptyState(at: number)
	return {
		lastAccruedAt = at,
		materials = {},
	}
end

describe("ProductionLedger.Accrue", function()
	it("retains fractions across repeated collections instead of rounding away earned work", function()
		local state = emptyState(100)
		local collected = 0
		for step = 1, 20 do
			state = ProductionLedger.Accrue(state, 100 + step * 15, "crystal", 0.5, 100)
			local nextState, output = ProductionLedger.Collect(state)
			state = nextState
			collected += output.crystal or 0
		end

		local once = ProductionLedger.Accrue(emptyState(100), 400, "crystal", 0.5, 100)
		local onceCollected, onceOutput = ProductionLedger.Collect(once)
		expect(collected).toBe(2)
		expect(collected).toBe(onceOutput.crystal)
		expect(state.materials.crystal.progress).toBeCloseTo(0.5)
		expect(state).toEqual(onceCollected)
	end)

	it("pauses empty and zero-rate intervals without losing progress or catching up later", function()
		local working = ProductionLedger.Accrue(emptyState(100), 130, "crystal", 1, 10)
		local empty = ProductionLedger.Accrue(working, 730, nil, 1, 10)
		local stopped = ProductionLedger.Accrue(empty, 1_030, "crystal", 0, 10)
		expect(empty.materials).toEqual(working.materials)
		expect(stopped.materials).toEqual(working.materials)
		expect(stopped.lastAccruedAt).toBe(1_030)

		local resumed = ProductionLedger.Accrue(stopped, 1_060, "crystal", 1, 10)
		expect(resumed.materials.crystal.stored).toBe(1)
		expect(resumed.materials.crystal.progress).toBeCloseTo(0)
	end)

	it("applies changed worker rates only to later work", function()
		local slow = ProductionLedger.Accrue(emptyState(100), 130, "crystal", 1, 10)
		local fast = ProductionLedger.Accrue(slow, 160, "crystal", 3, 10)
		local slower = ProductionLedger.Accrue(fast, 220, "crystal", 0.5, 10)
		expect(fast.materials.crystal.stored).toBe(2)
		expect(fast.materials.crystal.progress).toBeCloseTo(0)
		expect(slower.materials.crystal.stored).toBe(2)
		expect(slower.materials.crystal.progress).toBeCloseTo(0.5)
	end)

	it("keeps earned output and fractions with their original Material when workers change", function()
		local crystal = ProductionLedger.Accrue(emptyState(100), 130, "crystal", 1, 10)
		local shadow = ProductionLedger.Accrue(crystal, 220, "shadow_dust", 1, 10)
		expect(shadow.materials.crystal).toEqual(crystal.materials.crystal)
		expect(shadow.materials.shadow_dust.stored).toBe(1)
		expect(shadow.materials.shadow_dust.progress).toBeCloseTo(0.5)

		local returned = ProductionLedger.Accrue(shadow, 250, "crystal", 1, 10)
		local collected, output = ProductionLedger.Collect(returned)
		expect(output).toEqual({ crystal = 1, shadow_dust = 1 })
		expect(collected.materials.crystal.progress).toBeCloseTo(0)
		expect(collected.materials.shadow_dust.progress).toBeCloseTo(0.5)
	end)

	it("keeps unfinished work on its original stand when a worker moves", function()
		local original = ProductionLedger.Accrue(emptyState(100), 130, "crystal", 1, 10)
		local destination = emptyState(130)
		local pausedOriginal = ProductionLedger.Accrue(original, 160, nil, 0, 10)
		local workingDestination = ProductionLedger.Accrue(destination, 160, "crystal", 1, 10)
		expect(pausedOriginal.materials.crystal.stored).toBe(0)
		expect(pausedOriginal.materials.crystal.progress).toBeCloseTo(0.5)
		expect(workingDestination.materials.crystal.stored).toBe(0)
		expect(workingDestination.materials.crystal.progress).toBeCloseTo(0.5)
	end)

	it("uses shared storage across Material buckets and discards new overflow", function()
		local prior = {
			lastAccruedAt = 100,
			materials = {
				crystal = { stored = 2, progress = 0.25 },
				shadow_dust = { stored = 0, progress = 0.5 },
			},
		}
		local full = ProductionLedger.Accrue(prior, 220, "shadow_dust", 4, 3)
		expect(full.materials.crystal).toEqual(prior.materials.crystal)
		expect(full.materials.shadow_dust.stored).toBe(1)
		expect(full.materials.shadow_dust.progress).toBe(0)

		local stillFull = ProductionLedger.Accrue(full, 820, "shadow_dust", 4, 3)
		local collected, output = ProductionLedger.Collect(stillFull)
		expect(output).toEqual({ crystal = 2, shadow_dust = 1 })
		expect(collected.lastAccruedAt).toBe(820)
		local resumed = ProductionLedger.Accrue(collected, 835, "shadow_dust", 1, 3)
		expect(resumed.materials.shadow_dust.stored).toBe(0)
		expect(resumed.materials.shadow_dust.progress).toBeCloseTo(0.25)
	end)

	it("preserves existing whole and fractional output when a replacement worker lowers capacity", function()
		local prior = {
			lastAccruedAt = 100,
			materials = {
				crystal = { stored = 7, progress = 0.75 },
				shadow_dust = { stored = 2, progress = 0.5 },
			},
		}
		local smaller = ProductionLedger.Accrue(prior, 700, "crystal", 2, 3)
		expect(smaller.materials).toEqual(prior.materials)
		expect(smaller.lastAccruedAt).toBe(700)

		local collected, output = ProductionLedger.Collect(smaller)
		expect(output).toEqual({ crystal = 7, shadow_dust = 2 })
		local resumed = ProductionLedger.Accrue(collected, 715, "crystal", 1, 3)
		expect(resumed.materials.crystal.stored).toBe(1)
		expect(resumed.materials.crystal.progress).toBeCloseTo(0)
		expect(resumed.materials.shadow_dust.progress).toBeCloseTo(0.5)
	end)

	it("does not move a future cursor backwards or replay elapsed production", function()
		local prior = {
			lastAccruedAt = 200,
			materials = { crystal = { stored = 1, progress = 0.5 } },
		}
		local backwards = ProductionLedger.Accrue(prior, 100, "crystal", 1, 10)
		expect(backwards).toEqual(prior)
		local caughtUp = ProductionLedger.Accrue(backwards, 200, "crystal", 1, 10)
		expect(caughtUp).toEqual(prior)
		local later = ProductionLedger.Accrue(caughtUp, 230, "crystal", 1, 10)
		expect(later.materials.crystal.stored).toBe(2)
		expect(later.materials.crystal.progress).toBeCloseTo(0)
		expect(ProductionLedger.Accrue(later, 230, "crystal", 1, 10)).toEqual(later)
	end)

	it("preserves unfinished work through serialization and reconnect without replaying it", function()
		local online = ProductionLedger.Accrue(emptyState(100), 190, "crystal", 0.5, 100)
		local saved = HttpService:JSONDecode(HttpService:JSONEncode(online))
		local rejoined = ProductionLedger.Accrue(saved, 400, "crystal", 0.5, 100)
		local continuous = ProductionLedger.Accrue(emptyState(100), 400, "crystal", 0.5, 100)
		expect(rejoined).toEqual(continuous)
		expect(ProductionLedger.Accrue(rejoined, 400, "crystal", 0.5, 100)).toEqual(rejoined)
	end)

	it("returns independent tables without mutating the previous settlement", function()
		local bucket = table.freeze({ stored = 1, progress = 0.5 })
		local prior = table.freeze({
			lastAccruedAt = 100,
			materials = table.freeze({ crystal = bucket }),
		})
		local result = ProductionLedger.Accrue(prior, 130, "crystal", 1, 10)
		expect(result).never.toBe(prior)
		expect(result.materials).never.toBe(prior.materials)
		expect(result.materials.crystal).never.toBe(bucket)
		expect(prior.materials.crystal.stored).toBe(1)
		expect(prior.materials.crystal.progress).toBe(0.5)
		expect(prior.lastAccruedAt).toBe(100)
		expect(result.materials.crystal.stored).toBe(2)
	end)
end)

describe("ProductionLedger.Collect", function()
	it("collects whole stored output once while preserving fractions, cursor, and input tables", function()
		local prior = table.freeze({
			lastAccruedAt = 250,
			materials = table.freeze({
				crystal = table.freeze({ stored = 3, progress = 0.75 }),
				shadow_dust = table.freeze({ stored = 2, progress = 0.5 }),
			}),
		})
		local collected, output = ProductionLedger.Collect(prior)
		expect(output).toEqual({ crystal = 3, shadow_dust = 2 })
		expect(collected.lastAccruedAt).toBe(250)
		expect(collected.materials.crystal).toEqual({ stored = 0, progress = 0.75 })
		expect(collected.materials.shadow_dust).toEqual({ stored = 0, progress = 0.5 })
		expect(prior.materials.crystal.stored).toBe(3)
		expect(prior.materials.shadow_dust.stored).toBe(2)
		expect(collected).never.toBe(prior)
		expect(collected.materials).never.toBe(prior.materials)
		expect(collected.materials.crystal).never.toBe(prior.materials.crystal)

		local collectedAgain, repeatedOutput = ProductionLedger.Collect(collected)
		expect(repeatedOutput.crystal or 0).toBe(0)
		expect(repeatedOutput.shadow_dust or 0).toBe(0)
		expect(collectedAgain).toEqual(collected)
	end)
end)
