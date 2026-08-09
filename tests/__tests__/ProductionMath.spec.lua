--!strict
-- ServerStorage/Tests/__tests__/ProductionMath.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ProductionMath = require(game:GetService("ServerScriptService").Services.ProductionService.ProductionMath)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("ProductionMath.StoredAmount", function()
	it("accrues by rate and caps stored production", function()
		expect(ProductionMath.StoredAmount(160, 100, 2, 10)).toBe(2)
		expect(ProductionMath.StoredAmount(1_000, 100, 2, 10)).toBe(10)
	end)

	it("preserves fractional accrual until a whole Material is available", function()
		expect(ProductionMath.StoredAmount(129, 100, 2, 10)).toBe(0)
		expect(ProductionMath.StoredAmount(130, 100, 2, 10)).toBe(1)
	end)

	it("never returns negative production for future timestamps or invalid tuning", function()
		expect(ProductionMath.StoredAmount(100, 200, 2, 10)).toBe(0)
		expect(ProductionMath.StoredAmount(200, 100, -2, 10)).toBe(0)
		expect(ProductionMath.StoredAmount(200, 100, 2, -10)).toBe(0)
	end)
end)
