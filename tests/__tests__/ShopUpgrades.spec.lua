--!strict
-- ServerStorage/Tests/__tests__/ShopUpgrades.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local ShopUpgrades = require(ServerScriptService.Services.ShopService.ShopUpgrades)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function funded(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	data.currency.gold = 500_000
	for _, id in Inventory.upgradeMaterialIds do
		data.materials[id] = { total = 200 }
	end
	return data
end

describe("ShopUpgrades", function()
	it("quotes independent next upgrades and owned inputs without spending or reserving", function()
		local data = funded()
		data.inventoryUpgrades = { materials = 0, mythlings = 1, equipment = 2 }
		local before = copy(data)
		local views = ShopUpgrades.Snapshot(data)
		expect(#views).toBe(3)
		expect(views[1].category).toBe("materials")
		expect(views[1].capacity).toBe(12)
		expect(views[1].nextCapacity).toBe(24)
		expect(views[1].goldCost).toBe(20_000)
		expect(views[1].canPurchase).toBe(true)
		expect(views[2].capacity).toBe(36)
		expect(views[2].nextCapacity).toBe(48)
		expect(views[2].goldCost).toBe(300_000)
		expect(views[2].canPurchase).toBe(true)
		for _, material in views[2].materials do
			expect(material.quantity).toBe(200)
			expect(material.ownedQuantity).toBe(200)
		end
		expect(views[3].capacity).toBe(36)
		expect(views[3].maxCapacity).toBe(36)
		expect(views[3].nextCapacity).toBeNil()
		expect(views[3].goldCost).toBeNil()
		expect(views[3].materials).toEqual({})
		expect(views[3].purchaseCode).toBe("MaxCapacity")
		expect(views[3].canPurchase).toBe(false)
		views[1].materials[1].ownedQuantity = 0
		expect(data).toEqual(before)
	end)

	it("reports affordability using owned Materials, never uncollected output", function()
		local data = funded()
		data.currency.gold = 19_999
		expect(ShopUpgrades.Snapshot(data)[1].purchaseCode).toBe("InsufficientGold")
		data.currency.gold = 20_000
		data.materials.fire_material.total = 49
		expect(ShopUpgrades.Snapshot(data)[1].purchaseCode).toBe("InsufficientMaterials")
		data.materials.fire_material.total = 50
		expect(ShopUpgrades.Snapshot(data)[1].canPurchase).toBe(true)
	end)

	it(
		"requires ingredients to fit before a capacity grant and preserves refund reservations",
		function()
			local data = funded()
			data.craftingJobs = {
				legacy = {
					status = "Active",
					reservations = { equipment = 1, materials = { retained = 7_000 } },
				},
			}
			local before = copy(data)
			local view = ShopUpgrades.Snapshot(data)
			for _, item in view do
				expect(item.canPurchase).toBe(false)
				expect(item.purchaseCode).toBe("MaterialCapacityTooSmall")
			end
			expect(data).toEqual(before)
		end
	)

	it(
		"keeps upgrade ownership independent of Shop stock and accepts filled Equipment inventory",
		function()
			local data = funded()
			for index = 1, 12 do
				data.equipment[`owned_{index}`] = { definitionId = "wooden_sword" }
			end
			data.shop = { periodId = 0, purchased = { fire_material = 10, featured_sword = 1 } }
			local first = ShopUpgrades.Snapshot(data)
			data.shop = { periodId = 100, purchased = {} }
			expect(ShopUpgrades.Snapshot(data)).toEqual(first)
			expect(first[3].canPurchase).toBe(true)
		end
	)

	it(
		"fails closed for malformed counts, Materials, or category records without rewriting them",
		function()
			for _, malformed in { "level", "materials", "owned" } do
				local data = funded()
				-- Only this fixture boundary intentionally supplies invalid persisted data.
				local raw = data :: any
				if malformed == "level" then
					raw.inventoryUpgrades.equipment = -1
				elseif malformed == "materials" then
					raw.materials.fire_material.total = "invalid"
				else
					raw.equipment.invalid = false
				end
				local before = copy(data)
				expect(ShopUpgrades.Snapshot(data)[3].canPurchase).toBe(false)
				expect(data).toEqual(before)
			end
		end
	)
end)
