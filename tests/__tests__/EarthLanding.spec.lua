--!strict
-- ServerStorage/Tests/__tests__/EarthLanding.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local EarthLanding =
	require(game:GetService("ServerScriptService").Services.CombatService.EarthLanding)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local characters: { Model } = {}
local TUNING: EarthLanding.Tuning =
	{ supportAllowanceStuds = 0.3, minimumGroundNormalY = 0.5, takeoffVelocityStudsPerSecond = 1 }

local function fixture()
	local character = Instance.new("Model")
	table.insert(characters, character)
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 2
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(4, 10, 6)
	root.Parent = character
	root.AssemblyLinearVelocity = Vector3.zero
	return { character = character, humanoid = humanoid, root = root }
end

local function grounded(): EarthLanding.GroundHit
	return { distance = 3, normal = Vector3.yAxis }
end

afterEach(function()
	for _, character in characters do
		character:Destroy()
	end
	table.clear(characters)
end)

describe("EarthLanding", function()
	it(
		"uses self-excluded collidable support, the root collision group, and configured standing reach",
		function()
			local f = fixture()
			local calls = 0
			local observed = EarthLanding.Sample(
				f.character,
				f.humanoid,
				f.root,
				TUNING,
				function(origin, direction, params)
					calls += 1
					expect(origin).toEqual(f.root.Position)
					expect(direction.X == 0).toBe(true)
					expect(direction.Y).toBeCloseTo(-3.3, 5)
					expect(direction.Z == 0).toBe(true)
					expect(params.FilterType).toBe(Enum.RaycastFilterType.Exclude)
					expect(params.FilterDescendantsInstances).toEqual({ f.character })
					expect(params.RespectCanCollide).toBe(true)
					expect(params.CollisionGroup).toBe(f.root.CollisionGroup)
					expect(params.IgnoreWater).toBe(true)
					return grounded()
				end
			)
			expect(observed).toEqual({ airborne = false, supported = true })
			expect(calls).toBe(1)
		end
	)

	it(
		"reports support without inventing takeoff history on the grounded pre-launch frame",
		function()
			local f = fixture()
			for _ = 1, 2 do
				expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, grounded)).toEqual({
					airborne = false,
					supported = true,
				})
			end
			-- CombatState, not this stateless sampler, requires airborne-before-supported history.
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, function()
				return nil
			end)).toEqual({ airborne = true, supported = false })
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, grounded)).toEqual({
				airborne = false,
				supported = true,
			})
		end
	)

	it(
		"observes upward takeoff near the floor and never calls ascending motion a landing",
		function()
			local f = fixture()
			for _, velocity in { 2, 20 } do
				f.root.AssemblyLinearVelocity = Vector3.new(0, velocity, 0)
				expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, grounded)).toEqual({
					airborne = true,
					supported = false,
				})
			end
			for _, velocity in { 0.5, 1 } do
				f.root.AssemblyLinearVelocity = Vector3.new(0, velocity, 0)
				expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, grounded)).toEqual({
					airborne = false,
					supported = false,
				})
			end
			f.root.AssemblyLinearVelocity = Vector3.new(80, -30, -20)
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, grounded)).toEqual({
				airborne = false,
				supported = true,
			})
		end
	)

	it("requires a qualifying ground normal and a hit within the exact bounded reach", function()
		local f = fixture()
		for _, normalY in { -1, 0, 0.49 } do
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, function()
				return { distance = 3, normal = Vector3.new(0, normalY, 0) }
			end)).toEqual({ airborne = true, supported = false })
		end
		expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, function()
			return { distance = 3.3, normal = Vector3.new(0, 0.5, 0) }
		end)).toEqual({ airborne = false, supported = true })
		for _, distance in { -1, 3.31, math.huge, 0 / 0 } do
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, function()
				return { distance = distance, normal = Vector3.yAxis }
			end)).toEqual({ airborne = true, supported = false })
		end
	end)

	it("shrinks upright HipHeight reach when the root tips sideways or inverts", function()
		for _, angle in { math.pi / 2, math.pi } do
			local f = fixture()
			f.root.CFrame = CFrame.new(4, 10, 6) * CFrame.Angles(0, 0, angle)
			local length = 0
			local observed = EarthLanding.Sample(
				f.character,
				f.humanoid,
				f.root,
				TUNING,
				function(_origin, direction)
					length = direction.Magnitude
					-- This floor is inside the former upright probe but not beneath the tipped body.
					return { distance = 2, normal = Vector3.yAxis }
				end
			)
			expect(length).toBeCloseTo(1.3, 4)
			expect(observed).toEqual({ airborne = true, supported = false })
		end
	end)

	it("uses a short rotated LowerTorso fallback without adding standing HipHeight", function()
		local f = fixture()
		f.root.CFrame = CFrame.new(4, 10, 6) * CFrame.Angles(math.pi / 2, 0, 0)
		local torso = Instance.new("Part")
		torso.Name = "LowerTorso"
		torso.Size = Vector3.new(2, 1, 3)
		torso.CFrame = CFrame.new(4, 9, 6) * CFrame.Angles(math.pi / 2, 0, 0)
		torso.Parent = f.character
		local calls = 0
		local observed = EarthLanding.Sample(
			f.character,
			f.humanoid,
			f.root,
			TUNING,
			function(origin, direction, params)
				calls += 1
				if calls == 1 then
					return nil
				end
				expect(origin).toEqual(torso.Position)
				expect(direction.Magnitude).toBeCloseTo(1.8, 4)
				expect(params.RespectCanCollide).toBe(true)
				return { distance = 1.6, normal = Vector3.yAxis }
			end
		)
		expect(observed).toEqual({ airborne = false, supported = true })
		expect(calls).toBe(2)
	end)

	it("responds to configured tolerances without modifying character physics", function()
		local f = fixture()
		f.root.AssemblyLinearVelocity = Vector3.new(7, -3, 9)
		local before = {
			f.root.CFrame,
			f.root.AssemblyLinearVelocity,
			f.root.AssemblyAngularVelocity,
			f.root.Anchored,
			f.root.CanCollide,
			f.humanoid.WalkSpeed,
			f.humanoid.JumpPower,
			f.humanoid.AutoRotate,
			f.humanoid.Health,
		}
		local tuning: EarthLanding.Tuning = {
			supportAllowanceStuds = 0.6,
			minimumGroundNormalY = 0.25,
			takeoffVelocityStudsPerSecond = 2,
		}
		expect(
			EarthLanding.Sample(
				f.character,
				f.humanoid,
				f.root,
				tuning,
				function(_origin, direction)
					expect(direction.Magnitude).toBeCloseTo(3.6, 4)
					return { distance = 3.5, normal = Vector3.new(0, 0.3, 0) }
				end
			)
		).toEqual({ airborne = false, supported = true })
		expect({
			f.root.CFrame,
			f.root.AssemblyLinearVelocity,
			f.root.AssemblyAngularVelocity,
			f.root.Anchored,
			f.root.CanCollide,
			f.humanoid.WalkSpeed,
			f.humanoid.JumpPower,
			f.humanoid.AutoRotate,
			f.humanoid.Health,
		}).toEqual(before)
	end)

	it(
		"returns no evidence for dead, detached, or foreign character parts without raycasting",
		function()
			local f = fixture()
			local other = fixture()
			local casts = 0
			local function ray(): EarthLanding.GroundHit?
				casts += 1
				return grounded()
			end
			expect(EarthLanding.Sample(f.character, other.humanoid, f.root, TUNING, ray)).toEqual({
				airborne = false,
				supported = false,
			})
			expect(EarthLanding.Sample(f.character, f.humanoid, other.root, TUNING, ray)).toEqual({
				airborne = false,
				supported = false,
			})
			f.humanoid.Health = 0
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, TUNING, ray)).toEqual({
				airborne = false,
				supported = false,
			})
			other.root:Destroy()
			expect(EarthLanding.Sample(other.character, other.humanoid, other.root, TUNING, ray)).toEqual({
				airborne = false,
				supported = false,
			})
			expect(casts).toBe(0)
		end
	)

	it("rejects unsafe tuning before asking the world for support", function()
		local f = fixture()
		local invalid: { EarthLanding.Tuning } = {
			{
				supportAllowanceStuds = -1,
				minimumGroundNormalY = 0.5,
				takeoffVelocityStudsPerSecond = 1,
			},
			{
				supportAllowanceStuds = math.huge,
				minimumGroundNormalY = 0.5,
				takeoffVelocityStudsPerSecond = 1,
			},
			{
				supportAllowanceStuds = 0.3,
				minimumGroundNormalY = 0,
				takeoffVelocityStudsPerSecond = 1,
			},
			{
				supportAllowanceStuds = 0.3,
				minimumGroundNormalY = 1.1,
				takeoffVelocityStudsPerSecond = 1,
			},
			{
				supportAllowanceStuds = 0.3,
				minimumGroundNormalY = 0.5,
				takeoffVelocityStudsPerSecond = -1,
			},
			{
				supportAllowanceStuds = 0.3,
				minimumGroundNormalY = 0.5,
				takeoffVelocityStudsPerSecond = 0 / 0,
			},
		}
		local casts = 0
		for _, tuning in invalid do
			expect(EarthLanding.Sample(f.character, f.humanoid, f.root, tuning, function()
				casts += 1
				return grounded()
			end)).toEqual({ airborne = false, supported = false })
		end
		expect(casts).toBe(0)
	end)
end)
