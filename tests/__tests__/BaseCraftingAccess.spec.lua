--!strict
-- ServerStorage/Tests/__tests__/BaseCraftingAccess.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Configuration = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local CraftingAccess = require(ServerScriptService.Services.BaseService.CraftingAccess)
local BaseRuntime = require(ServerScriptService.Services.BaseService.BaseRuntime)
local BaseService = require(ServerScriptService.Services.BaseService)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local roots: { Instance } = {}

local function fixture()
	local container = Instance.new("Folder")
	container.Name = "CraftingAccessFixture"
	container.Parent = workspace
	table.insert(roots, container)
	local bases = Instance.new("Folder")
	bases.Parent = container
	local base = Instance.new("Model")
	base.Parent = bases
	local station = Instance.new("Model")
	station.Name = "PB_CraftingStation_Root"
	station.Parent = base
	local visual = Instance.new("Model")
	visual.Name = "PB_CraftingStation"
	visual.Parent = station
	local mesh = Instance.new("Part")
	mesh.Name = "PB_CraftingStation_Mesh"
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.Position = Vector3.new(0, 200, 0)
	mesh.Parent = visual
	local anchor = Instance.new("Attachment")
	anchor.Name = "CraftingPromptAttachment"
	anchor.Parent = mesh
	local character = Instance.new("Model")
	character.Parent = container
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = false
	root.Position = anchor.WorldPosition
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.Parent = character
	local saved: Types.BaseRecord = {
		stands = {},
		shrines = {},
		buildSlotUpgrades = 0,
		craftingStation = { id = "owned_station", craftingStationId = "basic_crafting_station" },
	}
	local slots: BaseRuntime.Slots = { [1] = { userId = 1001, base = base } }
	return {
		container = container,
		bases = bases,
		base = base,
		station = station,
		mesh = mesh,
		anchor = anchor,
		character = character,
		root = root,
		humanoid = humanoid,
		saved = saved,
		slots = slots,
		check = function(selected: string?): string?
			return CraftingAccess.Check(1001, character, saved, slots, bases, selected)
		end,
	}
end

afterEach(function()
	for _, root in roots do
		root:Destroy()
	end
	table.clear(roots)
end)

describe("Base Crafting access", function()
	it(
		"uses the exact configured distance and Station, independent of presentation attributes",
		function()
			local f = fixture()
			local definition = Configuration.basic_crafting_station
			expect(table.isfrozen(definition.interactionAnchorPath)).toBe(true)
			local limit = definition.interactionDistanceStuds
			f.station:SetAttribute("OwnerId", 999)
			f.station:SetAttribute("StationInstanceId", "forged")
			f.base.Name = "not_an_owner_id"
			for _, distance in { 0, limit - 0.01, limit } do
				f.root.Position = f.anchor.WorldPosition + Vector3.new(distance, 0, 0)
				expect(f.check("owned_station")).toBeNil()
				expect(f.check(nil)).toBeNil()
			end
			f.root.Position = f.anchor.WorldPosition + Vector3.new(limit + 0.01, 0, 0)
			expect(f.check(nil)).toBe("OutOfRange")
			f.root.Position = f.anchor.WorldPosition + Vector3.new(0, limit + 0.01, 0)
			expect(f.check(nil)).toBe("OutOfRange")
			expect(f.check("another_station")).toBe("StationChanged")
		end
	)

	it(
		"does not borrow another owner's Base even when its names and attributes are forged",
		function()
			local f = fixture()
			f.slots[1].userId = 1002
			f.base.Name = "1001"
			f.station:SetAttribute("OwnerId", 1001)
			expect(f.check(nil)).toBe("StationUnavailable")
			f.slots[1].userId = 1001
			f.slots[2] = { userId = 1001, base = f.base }
			expect(f.check(nil)).toBe("StationUnavailable")
		end
	)

	it(
		"requires a live server-owned Base hierarchy without falling back to a model pivot",
		function()
			local f = fixture()
			f.base.Parent = f.container
			expect(f.check(nil)).toBe("StationUnavailable")
			f.base.Parent = f.bases
			f.bases.Parent = nil
			expect(f.check(nil)).toBe("StationUnavailable")
			f.bases.Parent = f.container
			f.station.Parent = f.container
			expect(f.check(nil)).toBe("StationUnavailable")
			f.station.Parent = f.base
			f.anchor.Parent = f.root
			expect(f.check(nil)).toBe("StationUnavailable")
			f.anchor.Parent = f.mesh
			expect(f.check(nil)).toBeNil()
		end
	)

	it("rejects ambiguous anchors and wrong anchor classes", function()
		local f = fixture()
		local duplicate = f.anchor:Clone()
		duplicate.Parent = f.mesh
		expect(f.check(nil)).toBe("StationUnavailable")
		duplicate:Destroy()
		f.anchor:Destroy()
		local wrong = Instance.new("Folder")
		wrong.Name = "CraftingPromptAttachment"
		wrong.Parent = f.mesh
		expect(f.check(nil)).toBe("StationUnavailable")
	end)

	it(
		"rejects missing, dead and removed characters and evaluates the supplied current character",
		function()
			local f = fixture()
			expect(CraftingAccess.Check(1001, nil, f.saved, f.slots, f.bases, nil)).toBe(
				"CharacterUnavailable"
			)
			f.character.Parent = nil
			expect(f.check(nil)).toBe("CharacterUnavailable")
			f.character.Parent = f.container
			f.root.Parent = f.container
			expect(f.check(nil)).toBe("CharacterUnavailable")
			f.root.Parent = f.character
			local replacement = f.character:Clone()
			replacement.Parent = f.container
			local replacementRoot = replacement:FindFirstChild("HumanoidRootPart") :: BasePart
			replacementRoot.Position = f.anchor.WorldPosition + Vector3.new(100, 0, 0)
			expect(CraftingAccess.Check(1001, replacement, f.saved, f.slots, f.bases, nil)).toBe(
				"OutOfRange"
			)
			expect(f.check(nil)).toBeNil()
			f.humanoid.Health = 0
			expect(f.check(nil)).toBe("CharacterUnavailable")
		end
	)

	it("fails closed for malformed saved Base state and public non-Player callers", function()
		local f = fixture()
		f.saved.craftingStation = nil
		expect(f.check(nil)).toBe("InvalidBaseState")
		for _, raw in { false, f.base, { UserId = 1001, Character = f.character } } do
			expect(BaseService.CheckCraftingAccess((raw :: unknown) :: Player, f.saved, nil)).toBe(
				"DataUnavailable"
			)
		end
	end)
end)
