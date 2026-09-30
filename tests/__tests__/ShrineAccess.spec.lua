--!strict
-- ServerStorage/Tests/__tests__/ShrineAccess.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Configuration = require(ReplicatedStorage.Shared.Configurations.ShrineInteractions)
local ShrineAccess = require(ServerScriptService.Services.BaseService.ShrineAccess)
local BaseRuntime = require(ServerScriptService.Services.BaseService.BaseRuntime)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local roots: { Instance } = {}

local function fixture()
	local container = Instance.new("Folder")
	container.Name = "ShrineAccessFixture"
	container.Parent = workspace
	table.insert(roots, container)
	local bases = Instance.new("Folder")
	bases.Parent = container
	local base = Instance.new("Model")
	base.Parent = bases
	local shrineSlots = Instance.new("Folder")
	shrineSlots.Name = "ShrineSlots"
	shrineSlots.Parent = base
	local markers: { BasePart } = {}
	local anchors: { Attachment } = {}
	local shrines: { [string]: Types.ShrineRecord } = {}
	for index = 1, 6 do
		local marker = Instance.new("Part")
		marker.Name = `Slot{index}`
		marker.Anchored = true
		marker.CanCollide = false
		marker.Position = Vector3.new((index - 1) * 20, 200, 0)
		marker.Parent = shrineSlots
		local anchor = Instance.new("Attachment")
		anchor.Name = "ShrinePromptAttachment"
		anchor.Position = Vector3.new(1, 0, 0)
		anchor.Parent = marker
		table.insert(markers, marker)
		table.insert(anchors, anchor)
		local id = `owned_shrine_{index}`
		shrines[id] = {
			id = id,
			shrineId = "fire_shrine",
			buildSlotId = index,
			level = 1,
			stored = 0,
			progress = 0,
			newWork = 0,
			workerIdsBySlot = {},
		}
	end
	local character = Instance.new("Model")
	character.Parent = container
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = false
	root.Position = anchors[1].WorldPosition
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.Parent = character
	local saved: Types.BaseRecord = {
		stands = {},
		shrines = shrines,
		buildSlotUpgrades = 4,
		craftingStation = { id = "owned_station", craftingStationId = "basic_crafting_station" },
	}
	local slots: BaseRuntime.Slots = { [1] = { userId = 1001, base = base } }
	return {
		container = container,
		bases = bases,
		base = base,
		shrineSlots = shrineSlots,
		markers = markers,
		anchors = anchors,
		character = character,
		root = root,
		humanoid = humanoid,
		saved = saved,
		shrines = shrines,
		slots = slots,
		check = function(id: string?): string?
			return ShrineAccess.Check(1001, character, saved, slots, bases, id or "owned_shrine_1")
		end,
	}
end

afterEach(function()
	for _, root in roots do
		root:Destroy()
	end
	table.clear(roots)
end)

describe("Shrine access", function()
	it(
		"resolves all six configured logical slot anchors without requiring Shrine visuals",
		function()
			local f = fixture()
			expect(Configuration).toEqual({
				slotsFolderName = "ShrineSlots",
				slotNamePrefix = "Slot",
				promptAttachmentName = "ShrinePromptAttachment",
				interactionDistanceStuds = 4,
			})
			expect(table.isfrozen(Configuration)).toBe(true)
			for index = 1, 6 do
				f.root.Position = f.anchors[index].WorldPosition
				expect(f.check(`owned_shrine_{index}`)).toBeNil()
				local other = if index == 6 then 1 else index + 1
				expect(f.check(`owned_shrine_{other}`)).toBe("OutOfRange")
			end
		end
	)

	it(
		"uses current saved identity and slot after upgrades, moves, dismantle, and rebuild",
		function()
			local f = fixture()
			f.shrines.owned_shrine_1.level = 3
			expect(f.check()).toBeNil()
			f.shrines.owned_shrine_1.buildSlotId = 2
			f.shrines.owned_shrine_2.buildSlotId = 1
			expect(f.check()).toBe("OutOfRange")
			expect(f.check("owned_shrine_2")).toBeNil()
			f.root.Position = f.anchors[2].WorldPosition
			expect(f.check()).toBeNil()
			local replacement = table.clone(f.shrines.owned_shrine_1)
			replacement.id = "rebuilt_shrine"
			f.shrines.owned_shrine_1 = nil
			expect(f.check()).toBe("ShrineNotOwned")
			f.shrines.rebuilt_shrine = replacement
			expect(f.check("rebuilt_shrine")).toBeNil()
			expect(f.check()).toBe("ShrineNotOwned")
			expect(f.anchors[2].Parent).toBe(f.markers[2])
		end
	)

	it("uses server ownership rather than names, attributes, or a nearby different Base", function()
		local f = fixture()
		f.base.Name = "1002"
		f.base:SetAttribute("OwnerId", 1002)
		f.markers[1]:SetAttribute("ShrineInstanceId", "not_owned")
		f.anchors[1]:SetAttribute("OwnerId", 1002)
		expect(f.check()).toBeNil()
		f.slots[1].userId = 1002
		f.base.Name = "1001"
		f.base:SetAttribute("OwnerId", 1001)
		f.anchors[1]:SetAttribute("OwnerId", 1001)
		expect(f.check()).toBe("ShrineUnavailable")
		local owned = f.base:Clone()
		owned.Parent = f.bases
		owned:PivotTo(owned:GetPivot() + Vector3.new(200, 0, 0))
		f.slots[2] = { userId = 1001, base = owned }
		expect(f.check()).toBe("OutOfRange")
		f.slots[1].userId = 1001
		expect(f.check()).toBe("ShrineUnavailable")
	end)

	it("requires the complete live Base hierarchy and a direct slot Attachment", function()
		local f = fixture()
		f.base.Parent = f.container
		expect(f.check()).toBe("ShrineUnavailable")
		f.base.Parent = f.bases
		f.bases.Parent = nil
		expect(f.check()).toBe("ShrineUnavailable")
		f.bases.Parent = f.container
		f.shrineSlots.Parent = f.container
		expect(f.check()).toBe("ShrineUnavailable")
		f.shrineSlots.Parent = f.base
		f.markers[1].Parent = f.base
		expect(f.check()).toBe("ShrineUnavailable")
		f.markers[1].Parent = f.shrineSlots
		f.anchors[1].Parent = f.root
		expect(f.check()).toBe("ShrineUnavailable")
		f.anchors[1].Parent = f.markers[1]
		expect(f.check()).toBeNil()
	end)

	it("fails closed for duplicate, renamed, missing, or incorrectly typed path nodes", function()
		local f = fixture()
		local nodes: { Instance } = { f.shrineSlots, f.markers[1], f.anchors[1] }
		for _, node in nodes do
			local duplicate = node:Clone()
			duplicate.Parent = node.Parent
			expect(f.check()).toBe("ShrineUnavailable")
			duplicate:Destroy()
			local name = node.Name
			node.Name = "Renamed"
			expect(f.check()).toBe("ShrineUnavailable")
			node.Name = name
			local parent = node.Parent
			node.Parent = nil
			expect(f.check()).toBe("ShrineUnavailable")
			local wrong = Instance.new(if node:IsA("Folder") then "Model" else "Folder")
			wrong.Name = name
			wrong.Parent = parent
			expect(f.check()).toBe("ShrineUnavailable")
			wrong:Destroy()
			node.Parent = parent
		end
		expect(f.check()).toBeNil()
	end)

	it("rejects unanchored markers without using prototype stands or a Base pivot", function()
		local f = fixture()
		f.markers[1].Anchored = false
		expect(f.check()).toBe("ShrineUnavailable")
		f.markers[1].Anchored = true
		expect(f.check()).toBeNil()
		local stands = Instance.new("Folder")
		stands.Name = "Stands"
		stands.Parent = f.base
		f.markers[1].Parent = stands
		f.base.PrimaryPart = f.markers[1]
		expect(f.check()).toBe("ShrineUnavailable")
	end)

	it("checks inclusive finite three-dimensional distance using current positions", function()
		local f = fixture()
		local limit = Configuration.interactionDistanceStuds
		for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
			for _, distance in { 0, limit - 0.01, limit } do
				f.root.Position = f.anchors[1].WorldPosition + axis * distance
				expect(f.check()).toBeNil()
			end
			f.root.Position = f.anchors[1].WorldPosition + axis * (limit + 0.01)
			expect(f.check()).toBe("OutOfRange")
		end
		f.root.Position = f.anchors[1].WorldPosition + Vector3.new(limit, limit, 0)
		expect(f.check()).toBe("OutOfRange")
		f.root.Position = Vector3.new(math.huge, 200, 0)
		expect(f.check()).toBe("OutOfRange")
		f.root.Position = f.anchors[1].WorldPosition
		f.markers[1].Position += Vector3.new(100, 0, 0)
		expect(f.check()).toBe("OutOfRange")
		f.root.Position = f.anchors[1].WorldPosition
		expect(f.check()).toBeNil()
	end)

	it("requires the current living character and its unique root", function()
		local f = fixture()
		expect(ShrineAccess.Check(1001, nil, f.saved, f.slots, f.bases, "owned_shrine_1")).toBe(
			"CharacterUnavailable"
		)
		f.character.Parent = nil
		expect(f.check()).toBe("CharacterUnavailable")
		f.character.Parent = f.container
		local duplicate = f.root:Clone()
		duplicate.Parent = f.character
		expect(f.check()).toBe("CharacterUnavailable")
		duplicate:Destroy()
		f.root.Parent = f.container
		expect(f.check()).toBe("CharacterUnavailable")
		f.root.Parent = f.character
		f.humanoid.Parent = f.container
		expect(f.check()).toBe("CharacterUnavailable")
		f.humanoid.Parent = f.character
		local replacement = f.character:Clone()
		replacement.Parent = f.container
		local replacementRoot = replacement:FindFirstChild("HumanoidRootPart") :: BasePart
		replacementRoot.Position += Vector3.new(100, 0, 0)
		expect(ShrineAccess.Check(1001, replacement, f.saved, f.slots, f.bases, "owned_shrine_1")).toBe(
			"OutOfRange"
		)
		expect(f.check()).toBeNil()
		f.humanoid.Health = 0
		expect(f.check()).toBe("CharacterUnavailable")
	end)

	it(
		"rejects invalid request identity before invalid saved or unavailable world state",
		function()
			local f = fixture()
			f.saved.shrines = nil
			f.anchors[1]:Destroy()
			local invalidIds: { unknown } = { "", string.rep("a", 129), 1, false, {} }
			for _, id in invalidIds do
				expect(
					ShrineAccess.Check(1001, f.character, f.saved, f.slots, f.bases, id :: string)
				).toBe("InvalidRequest")
			end
		end
	)

	it("validates the whole saved Base before ownership or world lookup", function()
		local invalidators: { (Types.BaseRecord, { [string]: Types.ShrineRecord }) -> () } = {
			function(saved)
				saved.buildSlotUpgrades = 0
			end,
			function(saved)
				saved.craftingStation = nil
			end,
			function(saved)
				saved.shrines = nil
			end,
			function(_saved, shrines)
				shrines.owned_shrine_6.id = "wrong_id"
			end,
			function(_saved, shrines)
				shrines.owned_shrine_6.buildSlotId = 1
			end,
			function(_saved, shrines)
				shrines.owned_shrine_6.level = 4
			end,
			function(saved)
				setmetatable(saved, {})
			end,
		}
		for _, invalidate in invalidators do
			local f = fixture()
			invalidate(f.saved, f.shrines)
			f.anchors[1]:Destroy()
			expect(f.check("not_owned")).toBe("InvalidBaseState")
		end
		local f = fixture()
		f.anchors[1]:Destroy()
		expect(f.check("not_owned")).toBe("ShrineNotOwned")
		expect(
			ShrineAccess.Check(
				1001,
				f.character,
				(false :: unknown) :: Types.BaseRecord,
				f.slots,
				f.bases,
				"owned_shrine_1"
			)
		).toBe("InvalidBaseState")
	end)
end)
