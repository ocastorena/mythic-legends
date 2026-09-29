--!strict
-- ServerStorage/Tests/__tests__/UpgradePaymentUtil.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local UpgradePaymentUtil = require(ServerScriptService.Shared.UpgradePaymentUtil)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local COST: UpgradePaymentUtil.Cost = { gold = 20_000, materialQuantity = 50 }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function draft(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	data.currency.gold = 20_000
	for _, materialId in Inventory.upgradeMaterialIds do
		data.materials[materialId] = { total = 50 }
	end
	return data
end

describe("UpgradePaymentUtil", function()
	it(
		"accepts every configured positive whole cost and rejects malformed cost metadata",
		function()
			for _, cost in Bases.buildSlotUpgradeCosts do
				expect(UpgradePaymentUtil.ValidateCost(cost)).toBe(true)
			end
			for _, cost in Inventory.capacityUpgradeCosts do
				expect(UpgradePaymentUtil.ValidateCost(cost)).toBe(true)
			end
			expect(UpgradePaymentUtil.ValidateCost(nil)).toBe(false)
			for _, value in
				{
					false,
					"cost",
					{},
					{ gold = 1 },
					{ materialQuantity = 1 },
					setmetatable(copy(COST), {}),
				}
			do
				expect(UpgradePaymentUtil.ValidateCost(value)).toBe(false)
			end
			for _, field in { "gold", "materialQuantity" } do
				for _, value in { -1, 0, 0.5, math.huge, 0 / 0, 2 ^ 53, "50", false } do
					local cost: any = copy(COST)
					cost[field] = value
					expect(UpgradePaymentUtil.ValidateCost(cost)).toBe(false)
				end
			end
		end
	)

	it("accepts the real six normal Materials in any order, without changing the mix", function()
		expect(UpgradePaymentUtil.ValidateMaterialMix(Bases.expansionMaterialIds)).toBe(true)
		expect(UpgradePaymentUtil.ValidateMaterialMix(Inventory.upgradeMaterialIds)).toBe(true)
		local reversed = {}
		for index = #Inventory.upgradeMaterialIds, 1, -1 do
			table.insert(reversed, Inventory.upgradeMaterialIds[index])
		end
		local before = table.clone(reversed)
		expect(UpgradePaymentUtil.ValidateMaterialMix(reversed)).toBe(true)
		expect(reversed).toEqual(before)
	end)

	it("rejects missing, sparse, duplicate, extra, and non-array elemental mixes", function()
		expect(UpgradePaymentUtil.ValidateMaterialMix(nil)).toBe(false)
		for _, value in { false, "mix", {}, setmetatable(copy(Inventory.upgradeMaterialIds), {}) } do
			expect(UpgradePaymentUtil.ValidateMaterialMix(value)).toBe(false)
		end
		local sparse: any = copy(Inventory.upgradeMaterialIds)
		sparse[3] = nil
		expect(UpgradePaymentUtil.ValidateMaterialMix(sparse)).toBe(false)
		local duplicate = copy(Inventory.upgradeMaterialIds)
		duplicate[6] = duplicate[1]
		expect(UpgradePaymentUtil.ValidateMaterialMix(duplicate)).toBe(false)
		for _, key in { 0, -1, 0.5, 7, "extra" } do
			local mix: any = copy(Inventory.upgradeMaterialIds)
			mix[key] = "fire_material"
			expect(UpgradePaymentUtil.ValidateMaterialMix(mix)).toBe(false)
		end
	end)

	it("rejects unknown, retained prototype, and malformed Material IDs", function()
		for _, materialId in
			{ "unknown", "essence", "crystal", "shadow_dust", "", string.rep("x", 129), 1, false }
		do
			local mix: any = copy(Inventory.upgradeMaterialIds)
			mix[1] = materialId
			expect(UpgradePaymentUtil.ValidateMaterialMix(mix)).toBe(false)
		end
	end)

	it("charges the exact fixed mix and removes entries that reach zero", function()
		local data = draft()
		local before = copy(data)
		expect(UpgradePaymentUtil.PayToDraft(data, COST, Inventory.upgradeMaterialIds)).toBeNil()
		expect(data.currency.gold).toBe(0)
		expect(data.materials).toEqual({})
		before.currency.gold = 0
		before.materials = {}
		expect(data).toEqual(before)
	end)

	it("preserves remaining entry metadata and every unrelated field or reservation", function()
		local data = draft()
		data.currency.gold = 30_000
		local currency = data.currency :: any
		currency.legacyTokens = 7
		for _, materialId in Inventory.upgradeMaterialIds do
			data.materials[materialId].total = 75
		end
		local fire = data.materials.fire_material :: any
		fire.note = { retained = true }
		data.materials.essence = { total = 4_001 }
		data.craftingJobs = {
			active = {
				status = "Active",
				reservations = { equipment = 1, materials = { fire_material = 1_000 } },
			},
		}
		local materials, jobs, equipment = data.materials, data.craftingJobs, data.equipment
		local before = copy(data)
		expect(UpgradePaymentUtil.PayToDraft(data, COST, Inventory.upgradeMaterialIds)).toBeNil()
		before.currency.gold -= COST.gold
		for _, materialId in Inventory.upgradeMaterialIds do
			before.materials[materialId].total -= COST.materialQuantity
		end
		expect(data).toEqual(before)
		expect(data.currency).toBe(currency)
		expect(data.materials).toBe(materials)
		expect(data.materials.fire_material).toBe(fire)
		expect(data.craftingJobs).toBe(jobs)
		expect(data.equipment).toBe(equipment)
	end)

	it("returns failures without partially debiting Gold or any earlier Material", function()
		for _, failure in
			{
				"cost",
				"mix",
				"gold",
				"poor",
				"material",
				"missing-last",
				"reservation",
				"upgrade",
				"capacity",
			}
		do
			local data = draft()
			local cost = copy(COST)
			local mix = copy(Inventory.upgradeMaterialIds)
			local code: string
			if failure == "cost" then
				cost.gold = 0
				code = "InvalidUpgradeConfiguration"
			elseif failure == "mix" then
				mix[6] = "essence"
				code = "InvalidUpgradeConfiguration"
			elseif failure == "gold" then
				data.currency.gold = -1
				code = "InvalidCurrency"
			elseif failure == "poor" then
				data.currency.gold = COST.gold - 1
				code = "InsufficientGold"
			elseif failure == "material" then
				data.materials.dark_material.total = -1
				code = "InvalidInventoryState"
			elseif failure == "missing-last" then
				data.materials[mix[6]].total -= 1
				code = "InsufficientMaterials"
			elseif failure == "reservation" then
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { fire_material = -1 } },
					},
				}
				code = "InvalidReservations"
			elseif failure == "upgrade" then
				data.inventoryUpgrades = { materials = -1 }
				code = "InvalidInventoryUpgrade"
			else
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { water_material = 7_000 } },
					},
				}
				code = "MaterialCapacityTooSmall"
			end
			local before = copy(data)
			local currency, materials, firstEntry =
				data.currency, data.materials, data.materials.fire_material
			expect(UpgradePaymentUtil.PayToDraft(data, cost, mix)).toBe(code)
			expect(data).toEqual(before)
			expect(data.currency).toBe(currency)
			expect(data.materials).toBe(materials)
			expect(data.materials.fire_material).toBe(firstEntry)
		end
	end)
end)
