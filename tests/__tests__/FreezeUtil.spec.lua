--!strict
-- ServerStorage/Tests/__tests__/FreezeUtil.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(game:GetService("ReplicatedStorage").Shared.FreezeUtil)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("FreezeUtil.DeepFreeze", function()
	it("freezes nested configuration and preserves shared references", function()
		local nested = { rate = 12 }
		local config = { first = nested, second = nested }
		expect(FreezeUtil.DeepFreeze(config)).toBe(config)
		expect(config.first).toBe(config.second)
		expect(table.isfrozen(config)).toBe(true)
		expect(table.isfrozen(nested)).toBe(true)
		expect(function()
			nested.rate = 99
		end).toThrow()
	end)

	it("traverses children even when their parent was already frozen", function()
		local nested = { rate = 12 }
		local config = table.freeze({ nested = nested })
		FreezeUtil.DeepFreeze(config)
		expect(table.isfrozen(nested)).toBe(true)
		expect(FreezeUtil.DeepFreeze(config)).toBe(config)
	end)

	it("terminates on cycles and freezes table keys", function()
		type Graph = { next: Graph? }
		local graph: Graph = {}
		graph.next = graph
		local key = { id = 1 }
		local config = { [key] = graph }
		FreezeUtil.DeepFreeze(config)
		expect(graph.next).toBe(graph)
		expect(table.isfrozen(graph)).toBe(true)
		expect(table.isfrozen(key)).toBe(true)
	end)
end)
