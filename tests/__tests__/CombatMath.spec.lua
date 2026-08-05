--!strict
-- ServerStorage/Tests/__tests__/CombatMath.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local CombatMath = require(game:GetService("ReplicatedStorage").Shared.CombatMath)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("CombatMath.IsValidSequence", function()
	it("accepts bounded positive integers", function()
		expect(CombatMath.IsValidSequence(1, 100)).toBe(true)
		expect(CombatMath.IsValidSequence(100, 100)).toBe(true)
	end)

	it("rejects malformed and out-of-range values", function()
		expect(CombatMath.IsValidSequence(0, 100)).toBe(false)
		expect(CombatMath.IsValidSequence(1.5, 100)).toBe(false)
		expect(CombatMath.IsValidSequence(101, 100)).toBe(false)
		expect(CombatMath.IsValidSequence("1", 100)).toBe(false)
	end)
end)

describe("CombatMath.IsWithinGuardArc", function()
	local target = Vector3.zero
	local facing = Vector3.zAxis

	it("accepts an attacker in front and rejects one behind a forward guard", function()
		expect(CombatMath.IsWithinGuardArc(Vector3.new(0, 0, 5), target, facing, 110)).toBe(true)
		expect(CombatMath.IsWithinGuardArc(Vector3.new(0, 0, -5), target, facing, 110)).toBe(false)
	end)

	it("accepts every non-overlapping direction for a full guard", function()
		expect(CombatMath.IsWithinGuardArc(Vector3.new(0, 0, -5), target, facing, 360)).toBe(true)
	end)

	it("rejects overlapping positions that have no stable direction", function()
		expect(CombatMath.IsWithinGuardArc(target, target, facing, 360)).toBe(false)
	end)
end)
