--!strict
-- ServerStorage/Tests/__tests__/InventoryCapacity.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Capacity = require(ServerScriptService.Services.InventoryService.Capacity)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function fixture(): Types.PlayerDoc
	return {
		version = 4,
		profile = { userId = 91, createdAt = 0, lastLoginAt = 0 },
		mythlings = {},
		materials = {},
		currency = { gold = 100 },
		equipment = {},
		combatLoadout = {},
		base = { stands = {} },
	}
end

local function ownedMythling(standId: number?): Types.MythlingEntry
	return {
		typeId = "test_form",
		variantId = "regular",
		claimedAt = 0,
		level = 1,
		xp = 0,
		standId = standId,
	}
end

describe("Inventory capacity", function()
	it("resolves every category tier and preserves the Mythling compatibility API", function()
		expect(Capacity.GetLimit("materials", nil)).toBe(12)
		expect(Capacity.GetLimit("materials", 1)).toBe(24)
		expect(Capacity.GetLimit("materials", 2)).toBe(36)
		expect(Capacity.GetLimit("mythlings", 0)).toBe(24)
		expect(Capacity.GetLimit("mythlings", 1)).toBe(36)
		expect(Capacity.GetLimit("mythlings", 2)).toBe(48)
		expect(Capacity.GetLimit("equipment", 0)).toBe(12)
		expect(Capacity.GetLimit("equipment", 1)).toBe(24)
		expect(Capacity.GetLimit("equipment", 2)).toBe(36)
		expect(Capacity.GetLimit("equipment", 99)).toBe(36)
		expect(Capacity.GetLimit("equipment", -1)).toBe(12)
		expect(Capacity.GetLimit("equipment", 0 / 0)).toBe(12)
		expect(Capacity.GetMythlingLimit(1)).toBe(36)
	end)

	it("applies category upgrades independently", function()
		local data = fixture()
		data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 0 }

		expect(Capacity.GetUsage(data, "materials")).toEqual({ used = 0, limit = 24 })
		expect(Capacity.GetUsage(data, "mythlings")).toEqual({ used = 0, limit = 48 })
		expect(Capacity.GetUsage(data, "equipment")).toEqual({ used = 0, limit = 12 })
	end)

	it("rounds six Material IDs at 3,600 each to 24 occupied slots", function()
		local data = fixture()
		data.inventoryUpgrades = { materials = 1 }
		for _, materialId in { "fire", "water", "earth", "air", "light", "dark" } do
			data.materials[materialId] = { total = 3_600 }
		end

		expect(Capacity.GetUsage(data, "materials")).toEqual({ used = 24, limit = 24 })
	end)

	it("counts assigned Mythlings, equipped copies, and protected starter copies", function()
		local data = fixture()
		data.mythlings.assigned = ownedMythling(1)
		data.mythlings.unassigned = ownedMythling(nil)
		data.equipment.starter_sword = {
			definitionId = "wooden_sword",
			isStarterGrant = true,
		}
		data.equipment.starter_shield = {
			definitionId = "wooden_shield",
			isStarterGrant = true,
		}
		data.equipment.crafted_sword = { definitionId = "vulcan_sword" }
		data.combatLoadout.primaryWeaponInstanceId = "crafted_sword"
		data.combatLoadout.shieldInstanceId = "starter_shield"

		expect(Capacity.GetUsage(data, "mythlings")).toEqual({ used = 2, limit = 24 })
		expect(Capacity.GetUsage(data, "equipment")).toEqual({ used = 3, limit = 12 })
	end)

	it("fills a compatible partial stack before consuming empty Material slots", function()
		local data = fixture()
		data.materials.fire = { total = 1_250 }
		data.materials.water = { total = 1_000 }

		expect(Capacity.GetUsage(data, "materials")).toEqual({ used = 3, limit = 12 })
		expect(Capacity.GetMaterialRoom(data, "fire")).toBe(9_750)
		-- Static metadata is not required yet; an unknown ID can use every empty slot.
		expect(Capacity.GetMaterialRoom(data, "future_material")).toBe(9_000)
	end)

	it("reserves outstanding Equipment output and Material refunds for Active jobs", function()
		local data = fixture()
		data.materials.fire = { total = 400 }
		data.equipment.starter_sword = {
			definitionId = "wooden_sword",
			isStarterGrant = true,
		}
		data.equipment.starter_shield = {
			definitionId = "wooden_shield",
			isStarterGrant = true,
		}
		data.craftingJobs = {
			active_output = {
				status = "Active",
				reservations = { equipment = 1, materials = { fire = 750, water = 1_000 } },
			},
			completed = {
				status = "Completed",
				reservations = { equipment = -1, materials = { fire = math.huge } },
			},
			cancelled = {
				status = "Cancelled",
				reservations = { equipment = -1, materials = { fire = math.huge } },
			},
		}

		expect(Capacity.GetUsage(data, "equipment")).toEqual({ used = 3, limit = 12 })
		expect(Capacity.GetUsage(data, "materials")).toEqual({ used = 3, limit = 12 })
		expect(Capacity.GetMaterialRoom(data, "fire")).toBe(9_850)
	end)

	it("fails closed for non-finite, fractional, or negative saved quantities", function()
		for _, invalid in { -1, 0.5, math.huge, 0 / 0 } do
			local data = fixture()
			data.materials.fire = ({ total = invalid } :: unknown) :: Types.MaterialEntry
			expect(Capacity.GetUsage(data, "materials")).toEqual({ used = 12, limit = 12 })
			expect(Capacity.GetMaterialRoom(data, "fire")).toBe(0)
		end
	end)

	it("fails closed when an Active reservation is malformed", function()
		local data = fixture()
		data.craftingJobs = (
			{
				bad_job = {
					status = "Active",
					reservations = { equipment = 0.5, materials = { fire = -1 } },
				},
			} :: unknown
		) :: { [string]: Types.CraftingJob }

		expect(Capacity.GetUsage(data, "equipment")).toEqual({ used = 12, limit = 12 })
		expect(Capacity.GetUsage(data, "materials")).toEqual({ used = 12, limit = 12 })
		expect(Capacity.GetMaterialRoom(data, "fire")).toBe(0)
	end)
end)
