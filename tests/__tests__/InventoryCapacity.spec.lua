--!strict
-- ServerStorage/Tests/__tests__/InventoryCapacity.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)

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
		expect(InventoryCapacity.GetLimit("materials", nil)).toBe(12)
		expect(InventoryCapacity.GetLimit("materials", 1)).toBe(24)
		expect(InventoryCapacity.GetLimit("materials", 2)).toBe(36)
		expect(InventoryCapacity.GetLimit("mythlings", 0)).toBe(24)
		expect(InventoryCapacity.GetLimit("mythlings", 1)).toBe(36)
		expect(InventoryCapacity.GetLimit("mythlings", 2)).toBe(48)
		expect(InventoryCapacity.GetLimit("equipment", 0)).toBe(12)
		expect(InventoryCapacity.GetLimit("equipment", 1)).toBe(24)
		expect(InventoryCapacity.GetLimit("equipment", 2)).toBe(36)
		expect(InventoryCapacity.GetLimit("equipment", 99)).toBe(36)
		expect(InventoryCapacity.GetLimit("equipment", -1)).toBe(12)
		expect(InventoryCapacity.GetLimit("equipment", 0 / 0)).toBe(12)
		expect(InventoryCapacity.GetMythlingLimit(1)).toBe(36)
	end)

	it("applies category upgrades independently", function()
		local data = fixture()
		data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 0 }

		expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 0, limit = 24 })
		expect(InventoryCapacity.GetUsage(data, "mythlings")).toEqual({ used = 0, limit = 48 })
		expect(InventoryCapacity.GetUsage(data, "equipment")).toEqual({ used = 0, limit = 12 })
	end)

	it("rounds six Material IDs at 3,600 each to 24 occupied slots", function()
		local data = fixture()
		data.inventoryUpgrades = { materials = 1 }
		for _, materialId in { "fire", "water", "earth", "air", "light", "dark" } do
			data.materials[materialId] = { total = 3_600 }
		end

		expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 24, limit = 24 })
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

		expect(InventoryCapacity.GetUsage(data, "mythlings")).toEqual({ used = 2, limit = 24 })
		expect(InventoryCapacity.GetUsage(data, "equipment")).toEqual({ used = 3, limit = 12 })
	end)

	it("fills a compatible partial stack before consuming empty Material slots", function()
		local data = fixture()
		data.materials.fire = { total = 1_250 }
		data.materials.water = { total = 1_000 }

		expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 3, limit = 12 })
		expect(InventoryCapacity.GetMaterialRoom(data, "fire")).toBe(9_750)
		-- Static metadata is not required yet; an unknown ID can use every empty slot.
		expect(InventoryCapacity.GetMaterialRoom(data, "future_material")).toBe(9_000)
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

		expect(InventoryCapacity.GetUsage(data, "equipment")).toEqual({ used = 3, limit = 12 })
		expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 3, limit = 12 })
		expect(InventoryCapacity.GetMaterialRoom(data, "fire")).toBe(9_850)
		expect(InventoryCapacity.ValidateMaterialState(data)).toBeNil()
	end)

	it("fails closed for non-finite, fractional, or negative saved quantities", function()
		for _, invalid in { -1, 0.5, math.huge, 0 / 0 } do
			local data = fixture()
			data.materials.fire = ({ total = invalid } :: unknown) :: Types.MaterialEntry
			expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 12, limit = 12 })
			expect(InventoryCapacity.GetMaterialRoom(data, "fire")).toBe(0)
			expect(InventoryCapacity.ValidateMaterialState(data)).toBe("InvalidInventoryState")
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

		expect(InventoryCapacity.GetUsage(data, "equipment")).toEqual({ used = 12, limit = 12 })
		expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 12, limit = 12 })
		expect(InventoryCapacity.GetMaterialRoom(data, "fire")).toBe(0)
		expect(InventoryCapacity.ValidateMaterialState(data)).toBe("InvalidReservations")
	end)

	it("validates compatible Material state without requiring catalogue metadata", function()
		local data = fixture()
		data.materials.future_material = { total = 37 }

		expect(InventoryCapacity.ValidateMaterialState(data)).toBeNil()
		for _, purchasedLevel in { 0, 1, 2 } do
			data.inventoryUpgrades = {
				materials = purchasedLevel,
				-- Other category values are outside this narrow validator's responsibility.
				mythlings = math.huge,
			}
			expect(InventoryCapacity.ValidateMaterialState(data)).toBeNil()
		end
	end)

	it("rejects malformed or unavailable Material upgrade levels", function()
		local nonTable = fixture()
		local rawNonTable = nonTable :: any
		rawNonTable.inventoryUpgrades = 1
		expect(InventoryCapacity.ValidateMaterialState(nonTable)).toBe("InvalidInventoryUpgrade")

		for _, invalid in { -1, 0.5, 3, 99, math.huge, 0 / 0 } do
			local data = fixture()
			data.inventoryUpgrades = { materials = invalid }
			expect(InventoryCapacity.ValidateMaterialState(data)).toBe("InvalidInventoryUpgrade")
		end
	end)

	it("rejects malformed owned Material state and combined-total overflow", function()
		local nonRecord = (false :: unknown) :: InventoryCapacity.MaterialState
		expect(InventoryCapacity.ValidateMaterialState(nonRecord)).toBe("InvalidInventoryState")

		local nonPlainRecord = fixture()
		setmetatable(nonPlainRecord, {})
		expect(InventoryCapacity.ValidateMaterialState(nonPlainRecord)).toBe(
			"InvalidInventoryState"
		)

		local nonTable = fixture()
		local rawNonTable = nonTable :: any
		rawNonTable.materials = false
		expect(InventoryCapacity.ValidateMaterialState(nonTable)).toBe("InvalidInventoryState")

		local emptyId = fixture()
		emptyId.materials[""] = { total = 1 }
		-- Existing callers retain their prior permissive accounting, while collection validates first.
		expect(InventoryCapacity.GetUsage(emptyId, "materials")).toEqual({ used = 1, limit = 12 })
		expect(InventoryCapacity.GetMaterialRoom(emptyId, "fire")).toBe(11_000)
		expect(InventoryCapacity.ValidateMaterialState(emptyId)).toBe("InvalidInventoryState")

		local overflow = fixture()
		overflow.materials.fire = { total = 2 ^ 53 - 1 }
		overflow.craftingJobs = {
			active = {
				status = "Active",
				reservations = { equipment = 0, materials = { fire = 1 } },
			},
		}
		expect(InventoryCapacity.ValidateMaterialState(overflow)).toBe("InvalidInventoryState")

		local nonPlain = fixture()
		setmetatable(nonPlain.materials, {})
		expect(InventoryCapacity.ValidateMaterialState(nonPlain)).toBe("InvalidInventoryState")
	end)

	it("reports malformed Active crafting reservations separately", function()
		local nonTable = fixture()
		local rawNonTable = nonTable :: any
		rawNonTable.craftingJobs = "invalid"
		expect(InventoryCapacity.ValidateMaterialState(nonTable)).toBe("InvalidReservations")

		local emptyMaterialId = fixture()
		emptyMaterialId.craftingJobs = {
			active = {
				status = "Active",
				reservations = { equipment = 0, materials = { [""] = 1 } },
			},
		}
		expect(InventoryCapacity.ValidateMaterialState(emptyMaterialId)).toBe("InvalidReservations")

		local invalidStatus = fixture()
		invalidStatus.craftingJobs = (
			{
				unknown = {
					status = "Pending",
					reservations = { equipment = 0, materials = {} },
				},
			} :: unknown
		) :: { [string]: Types.CraftingJob }
		expect(InventoryCapacity.ValidateMaterialState(invalidStatus)).toBe("InvalidReservations")
	end)
end)
