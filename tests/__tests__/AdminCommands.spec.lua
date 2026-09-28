--!strict
-- ServerStorage/Tests/__tests__/AdminCommands.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local service = game:GetService("ServerScriptService").Services.AdminCommandService
local CommandParser = require(service.CommandParser)
local Teleportation = require(service.Teleportation)
local config = require(game:GetService("ReplicatedStorage").Shared.Configurations.AdminCommands)

local afterEach = JestGlobals.afterEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local fixtures: { Instance } = {}

local function keep<T>(instance: T): T
	table.insert(fixtures, instance :: any)
	return instance
end

afterEach(function()
	for _, instance in fixtures do
		instance:Destroy()
	end
	table.clear(fixtures)
end)

describe("Admin command syntax", function()
	it("normalizes casing and whitespace for teleport and event arguments", function()
		local command = CommandParser.Parse("  /ADMIN   TELEPORT\tFire  ")
		expect(command).toEqual({ name = "teleport", argument = "fire" })
		expect((CommandParser.Parse("/admin teleport base"))).toEqual({
			name = "teleport",
			argument = "base",
		})
		expect((CommandParser.Parse("/admin event Blockstorm"))).toEqual({
			name = "event",
			argument = "blockstorm",
		})
	end)

	it(
		"rejects old spellings, help, missing arguments, unknown events, and extra targets",
		function()
			for _, text in
				{
					"",
					"/admin",
					"/admin teleport",
					"/admin event",
					"/admin help",
					"/admin tp fire",
					"/admin blockstorm",
					"/admin event flood",
					"/admin teleport fire OtherPlayer",
					"/admin event blockstorm extra",
					"/other teleport fire",
				}
			do
				local command, message = CommandParser.Parse(text)
				expect(command).toBeNil()
				expect(type(message)).toBe("string")
			end
		end
	)
end)

describe("Teleport destinations", function()
	it("resolves only the named island's Markers folder and reports unfinished islands", function()
		local world = keep(Instance.new("Folder"))
		local islands = Instance.new("Folder")
		islands.Name = "ElementalIslands"
		islands.Parent = world
		local fire = Instance.new("Model")
		fire.Name = config.destinations.fire.islandName
		fire.Parent = islands

		local missing, message = Teleportation.ResolveMarker("fire", world, nil, config)
		expect(missing).toBeNil()
		expect(message).toBe("Fire Island is not ready for teleporting yet.")
		local marker = Instance.new("Part")
		marker.Name = "TeleportPoint"
		marker.Parent = fire
		expect((Teleportation.ResolveMarker("fire", world, nil, config))).toBeNil()
		local markers = Instance.new("Folder")
		markers.Name = "Markers"
		markers.Parent = fire
		marker.Parent = markers
		expect((Teleportation.ResolveMarker("fire", world, nil, config))).toBe(marker)
		expect((Teleportation.ResolveMarker("water", world, nil, config))).toBeNil()
		expect((Teleportation.ResolveMarker("unknown", world, nil, config))).toBeNil()
		marker.Parent = islands
		expect((Teleportation.ResolveMarker("fire", world, nil, config))).toBeNil()
	end)

	it("uses only the supplied own-Base spawn, independent of island readiness", function()
		local spawn = keep(Instance.new("Part"))
		expect((Teleportation.ResolveMarker("base", nil, spawn, config))).toBe(spawn)
		local marker, message = Teleportation.ResolveMarker("base", nil, nil, config)
		expect(marker).toBeNil()
		expect(message).toBe("Your Base is not ready yet. Try again shortly.")
	end)
end)

local function createCharacter(): (Model, Humanoid, Part)
	local character = keep(Instance.new("Model"))
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(50, 20, 30) * CFrame.Angles(0, 0.4, 0)
	root.Parent = character
	character.PrimaryPart = root
	-- Exercise a custom pivot so moving it cannot silently displace the root.
	root.PivotOffset = CFrame.new(1, 0.5, 0)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = character
	return character, humanoid, root
end

local function createMarker(): Part
	local marker = keep(Instance.new("Part"))
	marker.Anchored = true
	marker.Size = Vector3.new(4, 0.2, 4)
	marker.CFrame = CFrame.new(10, 0.1, 20) * CFrame.Angles(0, math.pi / 2, 0)
	return marker
end

describe("Teleport arrival", function()
	it(
		"preserves the pivot offset and character state while using marker facing and avatar height",
		function()
			local character, humanoid, root = createCharacter()
			local marker = createMarker()
			local floor = keep(Instance.new("Part"))
			local queries = 0
			local world: any = {
				Raycast = function()
					queries += 1
					return if queries == 1
						then {
							Position = Vector3.new(10, 0, 20),
							Normal = Vector3.yAxis,
							Instance = floor,
						}
						else nil
				end,
			}
			character:SetAttribute("CombatStamina", 37)
			character:SetAttribute("TestEffectDeadline", 42)
			local arrival = Teleportation.GetArrival(character, marker, world, config)
			expect(arrival ~= nil).toBe(true)
			Teleportation.MoveCharacter(character, arrival :: CFrame)
			expect((root.Position - Vector3.new(10, 3.7, 20)).Magnitude < 0.001).toBe(true)
			expect(root.CFrame.LookVector:Dot(marker.CFrame.LookVector) > 0.999).toBe(true)
			expect(character:GetAttribute("CombatStamina")).toBe(37)
			expect(character:GetAttribute("TestEffectDeadline")).toBe(42)
			expect(humanoid.HipHeight).toBe(2)
		end
	)

	it("rejects missing ground and does not move the character", function()
		local character, _, root = createCharacter()
		local original = root.CFrame
		local world: any = {
			Raycast = function()
				return nil
			end,
		}
		local arrival, message = Teleportation.GetArrival(character, createMarker(), world, config)
		expect(arrival).toBeNil()
		expect(message).toBe("There is no safe ground at that landing point.")
		expect(root.CFrame).toBe(original)
	end)

	it("rejects dead or seated characters before querying the destination", function()
		local character, humanoid = createCharacter()
		local world: any = {
			Raycast = function()
				error("Should not query invalid characters")
			end,
		}
		humanoid.Sit = true
		expect((Teleportation.GetArrival(character, createMarker(), world, config))).toBeNil()
		humanoid.Sit = false
		humanoid.Health = 0
		expect((Teleportation.GetArrival(character, createMarker(), world, config))).toBeNil()
	end)

	it(
		"rejects a ceiling above the actual arrival height even when the marker sits above the floor",
		function()
			local character = createCharacter()
			local marker = createMarker()
			marker.Position += Vector3.yAxis * 3
			local floor = keep(Instance.new("Part"))
			local queries = 0
			local world: any = {
				Raycast = function(_self: unknown, origin: Vector3)
					queries += 1
					if queries == 1 then
						return {
							Position = Vector3.new(10, 0, 20),
							Normal = Vector3.yAxis,
							Instance = floor,
						}
					end
					expect(math.abs(origin.Y - 3.7) < 0.001).toBe(true)
					return { Instance = floor }
				end,
			}
			local arrival, message = Teleportation.GetArrival(character, marker, world, config)
			expect(arrival).toBeNil()
			expect(message).toBe("There is not enough room above that landing point.")
		end
	)

	it("rejects an unanchored or tilted landing marker before moving", function()
		local character = createCharacter()
		local marker = createMarker()
		local world: any = {
			Raycast = function()
				error("Should not query invalid markers")
			end,
		}
		marker.Anchored = false
		expect((Teleportation.GetArrival(character, marker, world, config))).toBeNil()
		marker.Anchored = true
		marker.CFrame *= CFrame.Angles(math.pi / 2, 0, 0)
		expect((Teleportation.GetArrival(character, marker, world, config))).toBeNil()
	end)
end)
