--!strict
-- ServerStorage/Tests/__tests__/ArenaBounds.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ArenaBounds = require(game:GetService("ReplicatedStorage").Shared.ArenaBounds)

local afterEach = JestGlobals.afterEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local arena: Part? = nil

afterEach(function()
	if arena then
		arena:Destroy()
		arena = nil
	end
end)

describe("ArenaBounds.Contains", function()
	it("uses the transformed circular footprint", function()
		arena = Instance.new("Part")
		arena.Size = Vector3.new(20, 4, 20)
		arena.CFrame = CFrame.new(50, 10, -25) * CFrame.Angles(0, math.rad(30), 0)

		expect(ArenaBounds.Contains(arena, arena.Position, 0)).toBe(true)
		expect(ArenaBounds.Contains(arena, arena.CFrame:PointToWorldSpace(Vector3.new(11, 0, 0)), 0)).toBe(false)
	end)

	it("honors vertical allowance and safely rejects a missing arena", function()
		arena = Instance.new("Part")
		arena.Size = Vector3.new(20, 4, 20)

		expect(ArenaBounds.Contains(arena, Vector3.new(0, 5, 0), 3)).toBe(true)
		expect(ArenaBounds.Contains(arena, Vector3.new(0, 5.1, 0), 3)).toBe(false)
		expect(ArenaBounds.Contains(nil, Vector3.zero, 0)).toBe(false)
	end)
end)
