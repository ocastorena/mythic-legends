--!strict
-- ServerStorage/Tests/__tests__/ShopStock.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ShopStock = require(game:GetService("ServerScriptService").Services.ShopService.ShopStock)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

describe("ShopStock", function()
	it("rejects invalid current periods without interpreting an absent save as a reset", function()
		for _, period in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53 } do
			local purchased, problem = ShopStock.Read(nil, period)
			expect(purchased).toBeNil()
			expect(problem).toBe("InvalidShopState")
		end
	end)

	it("treats absent stock as empty without creating saved state", function()
		local purchased, problem = ShopStock.Read(nil, 0)
		expect(purchased).toEqual({})
		expect(problem).toBeNil()
		local later = ShopStock.Read(nil, 100)
		expect(later).toEqual({})
		expect(later).never.toBe(purchased)
	end)

	it(
		"retains unknown valid usage and over-limit quantities in a detached current-period view",
		function()
			local saved = {
				periodId = 7,
				purchased = { material_fire = 12, retired_offer = 2, untouched = 0 },
			}
			local purchased, problem = ShopStock.Read(saved, 7)
			expect(problem).toBeNil()
			expect(purchased).toEqual(saved.purchased)
			expect(purchased).never.toBe(saved.purchased)
			assert(purchased, "[ShopStock.spec] Expected usage").material_fire = 0
			expect(saved.purchased.material_fire).toBe(12)
		end
	)

	it(
		"virtually restocks only on a newer period without mutating or accumulating old allowances",
		function()
			local saved = { periodId = 2, purchased = { material_fire = 10, retired_offer = 3 } }
			for _, period in { 3, 100, 2 ^ 53 - 1 } do
				local purchased, problem = ShopStock.Read(saved, period)
				expect(problem).toBeNil()
				expect(purchased).toEqual({})
				expect(saved).toEqual({
					periodId = 2,
					purchased = { material_fire = 10, retired_offer = 3 },
				})
			end
		end
	)

	it("rejects a backwards clock without clearing future purchased stock", function()
		local saved = { periodId = 8, purchased = { material_fire = 4 } }
		local purchased, problem = ShopStock.Read(saved, 7)
		expect(purchased).toBeNil()
		expect(problem).toBe("ShopClockBehind")
		expect(saved).toEqual({ periodId = 8, purchased = { material_fire = 4 } })
	end)

	it("does not repair partial, malformed, or unknown-root state even after refresh", function()
		local invalid: { unknown } = {
			false,
			1,
			"shop",
			{},
			{ periodId = 0 },
			{ purchased = {} },
			{ periodId = 0, purchased = false },
			{ periodId = -1, purchased = {} },
			{ periodId = 0.5, purchased = {} },
			{ periodId = 2 ^ 53, purchased = {} },
			{ periodId = math.huge, purchased = {} },
			{ periodId = 0 / 0, purchased = {} },
			{ periodId = 0, purchased = {}, reset = true },
			{ periodId = 0, purchased = { [1] = 1 } },
			{ periodId = 0, purchased = { [""] = 1 } },
			{ periodId = 0, purchased = { [string.rep("x", 129)] = 1 } },
			{ periodId = 0, purchased = { stock = -1 } },
			{ periodId = 0, purchased = { stock = 0.5 } },
			{ periodId = 0, purchased = { stock = "1" } },
			{ periodId = 0, purchased = { stock = 2 ^ 53 } },
			{ periodId = 0, purchased = { stock = math.huge } },
			{ periodId = 0, purchased = { stock = 0 / 0 } },
			setmetatable({ periodId = 0, purchased = {} }, {}),
			{ periodId = 0, purchased = setmetatable({}, {}) },
		}
		for _, saved in invalid do
			for _, period in { 0, 99 } do
				local purchased, problem = ShopStock.Read(saved, period)
				expect(purchased).toBeNil()
				expect(problem).toBe("InvalidShopState")
			end
		end
	end)
end)
