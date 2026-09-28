--!strict
-- ServerStorage/Tests/__tests__/BaseState.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local BaseState = require(ServerScriptService.Domain.Base.BaseState)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function freshBase(): Types.BaseRecord
	return {
		stands = {},
		buildSlotUpgrades = 0,
		shrines = {},
		craftingStation = { id = "station-one", craftingStationId = Bases.craftingStationId },
	}
end

local function status(base: Types.BaseRecord): Types.BaseStatus
	return assert(BaseState.GetStatus(base), "[BaseState.spec] Expected valid Base status")
end

describe("BaseState", function()
	it("derives two starting Shrine slots and four sequential expansions up to six", function()
		local base = freshBase()
		for upgrade = 0, 4 do
			base.buildSlotUpgrades = upgrade
			local result = status(base)
			expect(result.unlockedShrineSlots).toBe(2 + upgrade)
			expect(result.maxShrineSlots).toBe(6)
			expect(result.usedShrineSlots).toBe(0)
		end
	end)

	it(
		"counts only constructed Shrines, never the permanent Station or prototype stands",
		function()
			local base = freshBase()
			for index = 1, 8 do
				base.stands[tostring(index)] = {}
			end
			expect(status(base).usedShrineSlots).toBe(0)
			base.shrines = {
				first = { id = "first", shrineId = "fire_shrine", buildSlotId = 1, level = 1 },
				second = { id = "second", shrineId = "water_shrine", buildSlotId = 2, level = 1 },
			}
			expect(status(base).usedShrineSlots).toBe(2)
			expect(status(base).unlockedShrineSlots).toBe(2)
		end
	)

	it("returns detached derived state without changing ownership", function()
		local base = freshBase()
		local result = status(base)
		result.craftingStation.id = "changed"
		result.unlockedShrineSlots = 100
		expect(status(base).craftingStation.id).toBe("station-one")
		expect(status(base).unlockedShrineSlots).toBe(2)
		expect(base.buildSlotUpgrades).toBe(0)
	end)

	it("fails closed for malformed upgrades rather than granting or clamping capacity", function()
		for _, value in { -1, 0.5, 5, math.huge, -math.huge, 0 / 0 } do
			local base = freshBase()
			base.buildSlotUpgrades = value
			expect(BaseState.GetStatus(base)).toBeNil()
		end
		local base = freshBase()
		base.buildSlotUpgrades = nil
		expect(BaseState.GetStatus(base)).toBeNil()
	end)

	it("rejects missing or invalid identities and over-capacity Shrine maps", function()
		local base = freshBase()
		base.craftingStation = nil
		expect(BaseState.GetStatus(base)).toBeNil()
		base.craftingStation = { id = "station-one", craftingStationId = "unknown" }
		expect(BaseState.GetStatus(base)).toBeNil()
		base.craftingStation = { id = "", craftingStationId = Bases.craftingStationId }
		expect(BaseState.GetStatus(base)).toBeNil()
		base = freshBase()
		base.shrines = nil
		expect(BaseState.GetStatus(base)).toBeNil()
		base.shrines =
			{ first = { id = "other-id", shrineId = "fire_shrine", buildSlotId = 1, level = 1 } }
		expect(BaseState.GetStatus(base)).toBeNil()
		base.shrines = {
			["station-one"] = {
				id = "station-one",
				shrineId = "fire_shrine",
				buildSlotId = 1,
				level = 1,
			},
		}
		expect(BaseState.GetStatus(base)).toBeNil()
		local shrines: { [string]: Types.ShrineRecord } = {}
		base.shrines = shrines
		for index = 1, 3 do
			local id = tostring(index)
			shrines[id] = { id = id, shrineId = "fire_shrine", buildSlotId = index, level = 1 }
		end
		expect(BaseState.GetStatus(base)).toBeNil()
		base.buildSlotUpgrades = 1
		expect(status(base).usedShrineSlots).toBe(3)
	end)

	it("freezes nested static Base and Station definitions", function()
		expect(table.isfrozen(Bases)).toBe(true)
		expect(table.isfrozen(Bases.buildSlotGrants)).toBe(true)
		expect(table.isfrozen(CraftingStations)).toBe(true)
		expect(table.isfrozen(CraftingStations[Bases.craftingStationId])).toBe(true)
		expect(table.isfrozen(Shrines)).toBe(true)
		for _, definition in Shrines do
			expect(table.isfrozen(definition)).toBe(true)
		end
	end)

	it("selects the lowest gap in unlocked slots, independently of map insertion order", function()
		local base = freshBase()
		base.buildSlotUpgrades = 2
		base.shrines = {
			last = { id = "last", shrineId = "fire_shrine", buildSlotId = 4, level = 1 },
			first = { id = "first", shrineId = "fire_shrine", buildSlotId = 1, level = 1 },
		}
		expect((BaseState.GetLowestFreeShrineSlot(base))).toBe(2)
	end)

	it("distinguishes a full Base from malformed slot ownership", function()
		local base = freshBase()
		base.shrines = {
			first = { id = "first", shrineId = "fire_shrine", buildSlotId = 1, level = 1 },
			second = { id = "second", shrineId = "fire_shrine", buildSlotId = 2, level = 1 },
		}
		local slot, code = BaseState.GetLowestFreeShrineSlot(base)
		expect(slot).toBeNil()
		expect(code).toBe("BaseFull")
		for _, invalidSlot in { 0, 1, 1.5, 3, math.huge, 0 / 0 } do
			local shrines = assert(base.shrines, "[BaseState.spec] Expected Shrines")
			shrines.second.buildSlotId = invalidSlot
			slot, code = BaseState.GetLowestFreeShrineSlot(base)
			expect(slot).toBeNil()
			expect(code).toBe("InvalidBaseState")
		end
	end)

	it("rejects unknown Shrine definitions and invalid levels", function()
		local base = freshBase()
		local shrine = { id = "first", shrineId = "unknown", buildSlotId = 1, level = 1 }
		base.shrines = { first = shrine }
		expect(BaseState.GetStatus(base)).toBeNil()
		shrine.shrineId = "fire_shrine"
		for _, invalidLevel in { 0, 1.5, 4, math.huge, 0 / 0 } do
			shrine.level = invalidLevel
			expect(BaseState.GetStatus(base)).toBeNil()
		end
		for level = 1, 3 do
			shrine.level = level
			expect(status(base).usedShrineSlots).toBe(1)
		end
	end)
end)
