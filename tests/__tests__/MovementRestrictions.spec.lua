--!strict
-- ServerStorage/Tests/__tests__/MovementRestrictions.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local MovementRestrictions =
	require(game:GetService("ServerScriptService").Services.CombatService.MovementRestrictions)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local characters: { Model } = {}
local NONE: MovementRestrictions.Rule =
	{ walkSpeedMultiplier = 1, blockJump = false, blockRotation = false }
local WATER: MovementRestrictions.Rule =
	{ walkSpeedMultiplier = 0.75, blockJump = false, blockRotation = false }
local EARTH: MovementRestrictions.Rule =
	{ walkSpeedMultiplier = 0, blockJump = true, blockRotation = false }
local GUARD: MovementRestrictions.Rule =
	{ walkSpeedMultiplier = 0, blockJump = true, blockRotation = true }

local function fixture()
	local character = Instance.new("Model")
	table.insert(characters, character)
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 20
	humanoid.JumpPower = 60
	humanoid.JumpHeight = 8
	humanoid.AutoRotate = true
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(1, 5, 3)
	root.CanCollide = true
	root.AssemblyLinearVelocity = Vector3.new(11, 20, -9)
	root.Parent = character
	return {
		character = character,
		humanoid = humanoid,
		root = root,
		api = MovementRestrictions.new(character, humanoid),
	}
end

local function values(humanoid: Humanoid)
	return { humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate }
end

afterEach(function()
	for _, character in characters do
		character:Destroy()
	end
	table.clear(characters)
end)

describe("MovementRestrictions", function()
	it("slows only walking and never compounds repeated Water applications", function()
		local f = fixture()
		f.api.Apply(WATER)
		f.api.Apply(WATER)
		expect(values(f.humanoid)).toEqual({ 15, 60, 8, true })
		f.humanoid.JumpPower = 72
		f.humanoid.JumpHeight = 9
		f.humanoid.AutoRotate = false
		f.api.Clear()
		expect(values(f.humanoid)).toEqual({ 20, 72, 9, false })
	end)

	it("captures each baseline lazily and releases each property independently", function()
		local f = fixture()
		f.api.Apply(NONE)
		f.humanoid.WalkSpeed = 24
		f.api.Apply(WATER)
		f.humanoid.JumpPower = 70
		f.humanoid.JumpHeight = 10
		f.humanoid.AutoRotate = false
		f.api.Apply(GUARD)
		expect(values(f.humanoid)).toEqual({ 0, 0, 0, false })
		f.api.Apply(WATER)
		expect(values(f.humanoid)).toEqual({ 18, 70, 10, false })
		f.api.Apply(NONE)
		expect(values(f.humanoid)).toEqual({ 24, 70, 10, false })
	end)

	it(
		"composes guard and Earth transitions without prematurely restoring movement or rotation",
		function()
			local f = fixture()
			f.api.Apply(EARTH)
			expect(values(f.humanoid)).toEqual({ 0, 0, 0, true })
			f.api.Apply(GUARD)
			expect(values(f.humanoid)).toEqual({ 0, 0, 0, false })
			f.api.Apply(EARTH)
			expect(values(f.humanoid)).toEqual({ 0, 0, 0, true })
			f.api.Apply(GUARD)
			f.api.Apply(GUARD)
			f.api.Apply(NONE)
			expect(values(f.humanoid)).toEqual({ 20, 60, 8, true })
		end
	)

	it("preserves zero and false baselines and both configured jump modes", function()
		for _, usePower in { false, true } do
			local f = fixture()
			f.humanoid.UseJumpPower = usePower
			f.humanoid.WalkSpeed = 0
			f.humanoid.JumpPower = 0
			f.humanoid.JumpHeight = 0
			f.humanoid.AutoRotate = false
			f.api.Apply(GUARD)
			f.api.Clear()
			expect(values(f.humanoid)).toEqual({ 0, 0, 0, false })
			expect(f.humanoid.UseJumpPower).toBe(usePower)
		end
	end)

	it(
		"does not alter forced motion, body collisions, anchoring, health, or Humanoid state",
		function()
			local f = fixture()
			local before = {
				f.root.CFrame,
				f.root.AssemblyLinearVelocity,
				f.root.AssemblyAngularVelocity,
				f.root.Anchored,
				f.root.CanCollide,
				f.root.CollisionGroup,
				f.humanoid.PlatformStand,
				f.humanoid.Health,
				f.humanoid:GetState(),
			}
			f.api.Apply(WATER)
			f.api.Apply(EARTH)
			f.api.Apply(GUARD)
			f.api.Clear()
			expect({
				f.root.CFrame,
				f.root.AssemblyLinearVelocity,
				f.root.AssemblyAngularVelocity,
				f.root.Anchored,
				f.root.CanCollide,
				f.root.CollisionGroup,
				f.humanoid.PlatformStand,
				f.humanoid.Health,
				f.humanoid:GetState(),
			}).toEqual(before)
		end
	)

	it("clears idempotently and captures new baselines for a later restriction", function()
		local f = fixture()
		f.api.Apply(WATER)
		f.api.Clear()
		f.humanoid.WalkSpeed = 32
		f.api.Clear()
		expect(f.humanoid.WalkSpeed).toBe(32)
		f.api.Apply(WATER)
		expect(f.humanoid.WalkSpeed).toBe(24)
		f.api.Apply(NONE)
		expect(f.humanoid.WalkSpeed).toBe(32)
	end)

	it(
		"safely releases dead characters and never writes to a reparented or destroyed Humanoid",
		function()
			local f = fixture()
			f.api.Apply(GUARD)
			f.humanoid.Health = 0
			f.api.Apply(GUARD)
			expect(values(f.humanoid)).toEqual({ 20, 60, 8, true })
			local other = fixture()
			other.api.Apply(GUARD)
			other.humanoid.Parent = f.character
			other.humanoid.WalkSpeed = 31
			other.api.Apply(WATER)
			other.api.Clear()
			expect(other.humanoid.WalkSpeed).toBe(31)
			other.humanoid:Destroy()
			expect(function()
				other.api.Clear()
			end).never.toThrow()
		end
	)

	it("rejects invalid rules before changing owned properties", function()
		local f = fixture()
		f.api.Apply(WATER)
		local before = values(f.humanoid)
		for _, multiplier in { -1, 1.1, math.huge, 0 / 0 } do
			expect(function()
				f.api.Apply({
					walkSpeedMultiplier = multiplier,
					blockJump = true,
					blockRotation = true,
				})
			end).toThrow()
			expect(values(f.humanoid)).toEqual(before)
		end
		f.api.Clear()
		expect(f.humanoid.WalkSpeed).toBe(20)
	end)
end)
