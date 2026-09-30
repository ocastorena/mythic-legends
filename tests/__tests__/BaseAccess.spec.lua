--!strict
-- ServerStorage/Tests/__tests__/BaseAccess.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local BaseAccess = require(ServerScriptService.Services.BaseService.BaseAccess)
local BaseRuntime = require(ServerScriptService.Services.BaseService.BaseRuntime)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local roots: { Instance } = {}

local function fixture()
	local container = Instance.new("Folder")
	container.Name = "BaseAccessFixture"
	container.Parent = workspace
	table.insert(roots, container)
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	bases.Parent = container
	local base = Instance.new("Model")
	base.Parent = bases
	local sign = Instance.new("Part")
	sign.Name = "NameSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Position = Vector3.new(0, 200, 0)
	sign.Parent = base
	local anchor = Instance.new("Attachment")
	anchor.Name = "BasePromptAttachment"
	anchor.Position = Vector3.new(1, 0, 0)
	anchor.Parent = sign
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
		sign = sign,
		anchor = anchor,
		character = character,
		root = root,
		humanoid = humanoid,
		saved = saved,
		slots = slots,
		check = function(): string?
			return BaseAccess.Check(1001, character, saved, slots, bases)
		end,
	}
end

afterEach(function()
	for _, root in roots do
		root:Destroy()
	end
	table.clear(roots)
end)

describe("Base access", function()
	it("uses the configured Attachment and inclusive horizontal and vertical distance", function()
		local f = fixture()
		expect(Bases.interactionAnchorPath).toEqual({ "NameSign", "BasePromptAttachment" })
		expect(table.isfrozen(Bases.interactionAnchorPath)).toBe(true)
		local limit = Bases.interactionDistanceStuds
		for _, axis in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
			for _, distance in { 0, limit - 0.01, limit } do
				f.root.Position = f.anchor.WorldPosition + axis * distance
				expect(f.check()).toBeNil()
			end
			f.root.Position = f.anchor.WorldPosition + axis * (limit + 0.01)
			expect(f.check()).toBe("OutOfRange")
		end
		-- The rule is a sphere, not independent horizontal/vertical allowances.
		f.root.Position = f.anchor.WorldPosition + Vector3.new(limit, limit, 0)
		expect(f.check()).toBe("OutOfRange")
	end)

	it("ignores presentation names and owner attributes without borrowing another Base", function()
		local f = fixture()
		f.base.Name = "not_an_owner_id"
		f.base:SetAttribute("OwnerId", 999)
		f.sign:SetAttribute("OwnerId", 999)
		f.anchor:SetAttribute("OwnerId", 999)
		expect(f.check()).toBeNil()
		f.slots[1].userId = 1002
		f.base.Name = "1001"
		f.base:SetAttribute("OwnerId", 1001)
		f.anchor:SetAttribute("OwnerId", 1001)
		expect(f.check()).toBe("BaseUnavailable")
		local other = f.base:Clone()
		other.Parent = f.bases
		f.slots[2] = { userId = 1001, base = other }
		local otherSign = other:FindFirstChild("NameSign") :: BasePart
		otherSign.Position += Vector3.new(100, 0, 0)
		expect(f.check()).toBe("OutOfRange")
		f.slots[1].userId = 1001
		expect(f.check()).toBe("BaseUnavailable")
	end)

	it("requires the registered Base under the live Bases folder", function()
		local f = fixture()
		f.base.Parent = f.container
		expect(f.check()).toBe("BaseUnavailable")
		f.base.Parent = f.bases
		f.bases.Parent = nil
		expect(f.check()).toBe("BaseUnavailable")
		f.bases.Parent = f.container
		expect(f.check()).toBeNil()
	end)

	it("does not substitute a pivot, renamed anchor, or an Attachment moved elsewhere", function()
		local f = fixture()
		f.base:PivotTo(CFrame.new(f.root.Position))
		f.anchor.Name = "DifferentAnchor"
		expect(f.check()).toBe("BaseUnavailable")
		f.anchor.Name = "BasePromptAttachment"
		f.anchor.Parent = f.root
		expect(f.check()).toBe("BaseUnavailable")
		f.anchor.Parent = f.sign
		f.sign.Name = "RenamedSign"
		expect(f.check()).toBe("BaseUnavailable")
	end)

	it("rejects duplicate path segments, wrong classes, and non-Part anchor parents", function()
		local f = fixture()
		local duplicateSign = f.sign:Clone()
		duplicateSign.Parent = f.base
		expect(f.check()).toBe("BaseUnavailable")
		duplicateSign:Destroy()
		local duplicateAnchor = f.anchor:Clone()
		duplicateAnchor.Parent = f.sign
		expect(f.check()).toBe("BaseUnavailable")
		duplicateAnchor:Destroy()
		f.anchor:Destroy()
		local wrong = Instance.new("Folder")
		wrong.Name = "BasePromptAttachment"
		wrong.Parent = f.sign
		expect(f.check()).toBe("BaseUnavailable")
		f.sign:Destroy()
		local folder = Instance.new("Folder")
		folder.Name = "NameSign"
		folder.Parent = f.base
		local detached = Instance.new("Attachment")
		detached.Name = "BasePromptAttachment"
		detached.Parent = folder
		expect(f.check()).toBe("BaseUnavailable")
	end)

	it("requires a living character with its own unique HumanoidRootPart", function()
		local f = fixture()
		expect(BaseAccess.Check(1001, nil, f.saved, f.slots, f.bases)).toBe("CharacterUnavailable")
		f.character.Parent = nil
		expect(f.check()).toBe("CharacterUnavailable")
		f.character.Parent = f.container
		f.root.Parent = f.container
		expect(f.check()).toBe("CharacterUnavailable")
		f.root.Parent = f.character
		local duplicate = f.root:Clone()
		duplicate.Parent = f.character
		expect(f.check()).toBe("CharacterUnavailable")
		duplicate:Destroy()
		f.humanoid.Parent = f.container
		expect(f.check()).toBe("CharacterUnavailable")
		f.humanoid.Parent = f.character
		expect(f.check()).toBeNil()
		f.humanoid.Health = 0
		expect(f.check()).toBe("CharacterUnavailable")
	end)

	it("uses the supplied current character and current anchor positions on every check", function()
		local f = fixture()
		local replacement = f.character:Clone()
		replacement.Parent = f.container
		local replacementRoot = replacement:FindFirstChild("HumanoidRootPart") :: BasePart
		replacementRoot.Position = f.anchor.WorldPosition + Vector3.new(100, 0, 0)
		expect(BaseAccess.Check(1001, replacement, f.saved, f.slots, f.bases)).toBe("OutOfRange")
		expect(f.check()).toBeNil()
		f.sign.Position += Vector3.new(100, 0, 0)
		expect(BaseAccess.Check(1001, replacement, f.saved, f.slots, f.bases)).toBeNil()
		expect(f.check()).toBe("OutOfRange")
	end)

	it("rejects invalid saved Base state before checking unavailable world bindings", function()
		local cases: { (Types.BaseRecord) -> () } = {
			function(saved)
				saved.buildSlotUpgrades = -1
			end,
			function(saved)
				saved.craftingStation = nil
			end,
			function(saved)
				saved.shrines = nil
			end,
		}
		for _, invalidate in cases do
			local f = fixture()
			invalidate(f.saved)
			f.anchor:Destroy()
			expect(f.check()).toBe("InvalidBaseState")
		end
		local f = fixture()
		expect(
			BaseAccess.Check(
				1001,
				f.character,
				(false :: unknown) :: Types.BaseRecord,
				f.slots,
				f.bases
			)
		).toBe("InvalidBaseState")
	end)
end)
