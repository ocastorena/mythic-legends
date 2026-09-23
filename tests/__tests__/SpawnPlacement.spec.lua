--!strict
-- ServerStorage/Tests/__tests__/SpawnPlacement.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local SpawnPlacement =
	require(game:GetService("ServerScriptService").Services.MythlingSpawnService.SpawnPlacement)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect
local ARENA: SpawnPlacement.Bounds = { radius = 153, sides = 16, apothem = 150 }

describe("SpawnPlacement ring clearance", function()
	it("keeps the entire ring and configured clearance inside a circular boundary", function()
		local circle: SpawnPlacement.Bounds = { radius = 150 }
		expect(SpawnPlacement.IsValid(118, 0, 20, circle, {}, 2, 12)).toBe(true)
		expect(SpawnPlacement.IsValid(118.01, 0, 20, circle, {}, 2, 12)).toBe(false)
		expect(SpawnPlacement.IsValid(0, 0, 151, circle, {}, 2, 0)).toBe(false)
	end)

	it("tests polygon side clearance rather than a circumscribed circle", function()
		expect(SpawnPlacement.IsValid(118, 0, 20, ARENA, {}, 2, 12)).toBe(true)
		expect(SpawnPlacement.IsValid(120, 0, 20, ARENA, {}, 2, 12)).toBe(false)
		local diagonal = 118 / math.sqrt(2)
		expect(SpawnPlacement.IsValid(diagonal + 0.1, diagonal + 0.1, 20, ARENA, {}, 2, 12)).toBe(
			false
		)
	end)

	it("protects every occupied ring including prefill entries", function()
		local occupied = { { x = 0, z = 0, radius = 20 } }
		expect(SpawnPlacement.IsValid(41.99, 0, 20, ARENA, occupied, 2, 12)).toBe(false)
		expect(SpawnPlacement.IsValid(42, 0, 20, ARENA, occupied, 2, 12)).toBe(true)
		expect(SpawnPlacement.IsValid(42, 0, 25, ARENA, occupied, 2, 12)).toBe(false)
	end)

	it("deterministically fits all twelve current rings when random placement fails", function()
		local occupied: { SpawnPlacement.Ring } = {}
		for _ = 1, 12 do
			local x, z = SpawnPlacement.FindFallback(20, ARENA, occupied, 2, 12, 4)
			expect(x ~= nil and z ~= nil).toBe(true)
			assert(x and z, "Expected a valid fallback position")
			expect(SpawnPlacement.IsValid(x, z, 20, ARENA, occupied, 2, 12)).toBe(true)
			table.insert(occupied, { x = x, z = z, radius = 20 })
		end
		expect(#occupied).toBe(12)
	end)

	it("refills multiple vacated spaces while remaining contests keep their positions", function()
		local occupied: { SpawnPlacement.Ring } = {}
		for _ = 1, 12 do
			local x, z = SpawnPlacement.FindFallback(20, ARENA, occupied, 2, 12, 4)
			assert(x and z, "Expected a valid prefill position")
			table.insert(occupied, { x = x, z = z, radius = 20 })
		end
		for _ = 1, 8 do
			table.remove(occupied, 1)
		end
		local unchanged = occupied[1]
		for _ = 1, 8 do
			local x, z = SpawnPlacement.FindFallback(20, ARENA, occupied, 2, 12, 4)
			assert(x and z, "Expected a valid replacement position")
			expect(SpawnPlacement.IsValid(x, z, 20, ARENA, occupied, 2, 12)).toBe(true)
			table.insert(occupied, { x = x, z = z, radius = 20 })
		end
		expect(occupied[1]).toBe(unchanged)
		expect(#occupied).toBe(12)
	end)

	it("fails closed if valid placement is impossible", function()
		local x, z = SpawnPlacement.FindFallback(20, { radius = 30 }, {}, 2, 12, 4)
		expect(x).toBe(nil)
		expect(z).toBe(nil)
	end)
end)
