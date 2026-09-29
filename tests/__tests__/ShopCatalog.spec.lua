--!strict
-- ServerStorage/Tests/__tests__/ShopCatalog.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Shop = require(ReplicatedStorage.Shared.Configurations.Shop)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local EquipmentRecipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local ShopCatalog = require(ServerScriptService.Services.ShopService.ShopCatalog)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local MAX_SAFE_INTEGER = 9007199254740991
local ELEMENTS = { "Fire", "Water", "Earth", "Air", "Light", "Dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function fixture()
	return { config = copy(Shop), materials = copy(Materials), recipes = copy(EquipmentRecipes) }
end

local function resolve(api: ShopCatalog.ShopCatalog, now: number): Types.ShopPeriod
	local period, problem = api.Resolve(now)
	expect(problem).toBeNil()
	return (assert(period, "[ShopCatalog.spec] Expected current catalogue"))
end

describe("ShopCatalog", function()
	it(
		"pins the approved hourly six-element cycle and eight ordered offers without per-player state",
		function()
			expect((ShopCatalog.ValidateLaunch())).toBe(true)
			expect(Shop.epochSeconds).toBe(0)
			expect(Shop.refreshSeconds).toBe(3600)
			local api = ShopCatalog.new()
			for periodId = 0, 12 do
				local period = resolve(api, periodId * 3600)
				local element = ELEMENTS[periodId % 6 + 1]
				expect(period.periodId).toBe(periodId)
				expect(period.featuredElement).toBe(element)
				expect(period.startsAt).toBe(periodId * 3600)
				expect(period.refreshAt).toBe((periodId + 1) * 3600)
				expect(#period.offers).toBe(8)
				for index = 1, 6 do
					local offer = period.offers[index]
					expect(offer.kind).toBe("Material")
					expect(offer.materialId).toBe(Shop.materials[index].materialId)
					expect(Materials[offer.materialId :: string].element).toBe(ELEMENTS[index])
					expect(offer.unitGold).toBe(10)
					expect(offer.stockLimit).toBe(10)
					expect(offer.offerId).toBe(offer.materialId)
					expect(offer.stockKey).toBe(offer.materialId)
				end
				for index = 7, 8 do
					local offer = period.offers[index]
					local item = assert(
						EquipmentCatalog.Resolve(offer.definitionId, offer.finishId),
						"[ShopCatalog.spec] Expected named item"
					)
					expect(offer.kind).toBe("Equipment")
					expect(offer.unitGold).toBe(150)
					expect(offer.stockLimit).toBe(1)
					expect(offer.offerId).toBe(
						if index == 7 then "featured_sword" else "featured_shield"
					)
					expect(offer.stockKey).toBe(offer.offerId)
					expect(item.element).toBe(element)
					expect(item.rarity).toBe("Rare")
					expect(item.sellGold).toBe(25)
				end
			end
		end
	)

	it(
		"uses exact boundaries and absolute periods after skipped hours and independent construction",
		function()
			local first, second = ShopCatalog.new(), ShopCatalog.new()
			for _, now in { 0, 0.125, 3599.999, 3600, 21599.5, 21600, 1234567890.25 } do
				local period = resolve(first, now)
				expect(period).toEqual(resolve(second, now))
				expect(period.periodId).toBe(math.floor(now / 3600))
				expect(period.startsAt <= now and now < period.refreshAt).toBe(true)
			end
			local changed = fixture()
			changed.config.epochSeconds = 100
			changed.config.refreshSeconds = 60
			local api = ShopCatalog.new(changed)
			expect(resolve(api, 159.999).periodId).toBe(0)
			expect(resolve(api, 160).periodId).toBe(1)
			expect(resolve(api, 820).periodId).toBe(12)
			local before, code = api.Resolve(99)
			expect(before).toBeNil()
			expect(code).toBe("InvalidTimestamp")
		end
	)

	it("rejects nonfinite, negative, overflowing, or rounded-out-of-window timestamps", function()
		local api = ShopCatalog.new()
		for _, now in { -1, math.huge, -math.huge, 0 / 0, MAX_SAFE_INTEGER, 9007199254740992 } do
			local period, problem = api.Resolve(now)
			expect(period).toBeNil()
			expect(problem).toBe("InvalidTimestamp")
		end
		local f = fixture()
		f.config.refreshSeconds = 3
		local precise = ShopCatalog.new(f)
		local period = resolve(precise, MAX_SAFE_INTEGER - 4)
		expect(period.periodId).toBe(3002399751580329)
		expect(period.refreshAt).toBe(MAX_SAFE_INTEGER - 1)
	end)

	it(
		"detaches and freezes schedules and offers instead of exposing mutable owner metadata",
		function()
			local f = fixture()
			local api = ShopCatalog.new(f)
			local before = resolve(api, 0)
			f.config.refreshSeconds = 1
			f.config.rotation[1].sword.unitGold = 900
			f.materials.fire_material.buyGold = 900
			f.recipes.elemental_sword_fire.materials.fire_material = 999
			expect(resolve(api, 0)).toEqual(before)
			expect(table.isfrozen(Shop)).toBe(true)
			expect(table.isfrozen(Shop.rotation[1].sword)).toBe(true)
			expect(table.isfrozen(before)).toBe(true)
			expect(table.isfrozen(before.offers)).toBe(true)
			for _, offer in before.offers do
				expect(table.isfrozen(offer)).toBe(true)
			end
			local writes = pcall(function()
				before.offers[1].unitGold = 999
			end)
			expect(writes).toBe(false)
			expect(resolve(api, 3600).offers[1].unitGold).toBe(10)
		end
	)

	it("revises exact price, stock, and item selections while keeping stable stock keys", function()
		local base = resolve(ShopCatalog.new(), 0)
		local f = fixture()
		f.materials.fire_material.buyGold = 11
		f.config.materials[1].stockLimit = 12
		f.config.rotation[1].sword.unitGold = 170
		local tuned = resolve(ShopCatalog.new(f), 0)
		for _, index in { 1, 7 } do
			expect(tuned.offers[index].stockKey).toBe(base.offers[index].stockKey)
			expect(tuned.offers[index].offerRevision == base.offers[index].offerRevision).toBe(
				false
			)
		end
		expect(tuned.offers[2].offerRevision).toBe(base.offers[2].offerRevision)
		expect(tuned.offers[1].unitGold).toBe(11)
		local water = resolve(ShopCatalog.new(), 3600)
		expect(water.offers[7].stockKey).toBe(base.offers[7].stockKey)
		expect(water.offers[7].offerRevision == base.offers[7].offerRevision).toBe(false)
		for _, price in { MAX_SAFE_INTEGER - 1, MAX_SAFE_INTEGER } do
			local large = fixture()
			large.config.rotation[1].sword.unitGold = price
			local quote = resolve(ShopCatalog.new(large), 0).offers[7].offerRevision
			expect(string.find(quote, string.format("%.0f", price), 1, true) ~= nil).toBe(true)
			expect(#quote <= 128).toBe(true)
		end
	end)

	it("accepts coherent changed recipe costs, allowances, schedule, and prices", function()
		local f = fixture()
		f.config.refreshSeconds = 1800
		for _, reference in f.config.materials do
			reference.stockLimit = 20
		end
		for _, recipe in f.recipes do
			recipe.goldCost = 60
			for id in recipe.materials do
				recipe.materials[id] = 8
			end
		end
		local api = ShopCatalog.new(f)
		expect((api.ValidateLaunch())).toBe(true)
		expect(resolve(api, 1800).featuredElement).toBe("Water")
	end)

	it(
		"fails closed for malformed schedules, incomplete rotations, legacy references, and forged variants",
		function()
			local changes: { (any) -> () } = {
				function(f)
					f.config.epochSeconds = -1
				end,
				function(f)
					f.config.refreshSeconds = 0
				end,
				function(f)
					f.config.refreshSeconds = 0.5
				end,
				function(f)
					f.config.epochSeconds = MAX_SAFE_INTEGER
				end,
				function(f)
					f.config.materials[2] = nil
				end,
				function(f)
					f.config.materials[7] = f.config.materials[1]
				end,
				function(f)
					f.config.materials[2].materialId = "fire_material"
				end,
				function(f)
					f.config.materials[1].materialId = "essence"
				end,
				function(f)
					f.config.materials[1].stockLimit = -1
				end,
				function(f)
					f.config.rotation[1].element = "Dark"
				end,
				function(f)
					f.config.rotation[1].sword.definitionId = "wooden_sword"
				end,
				function(f)
					f.config.rotation[1].sword.finishId = "water"
				end,
				function(f)
					f.config.rotation[1].shield = f.config.rotation[1].sword
				end,
				function(f)
					f.config.rotation[1].sword.stockLimit = 2
				end,
				function(f)
					f.config.rotation[1].sword.unitGold = 0 / 0
				end,
				function(f)
					f.config.rotation[1].sword.recipeId = "missing_recipe"
				end,
				function(f)
					f.config.rotation[1].sword.ownedRarity = "Mythical"
				end,
				function(f)
					f.config = setmetatable(f.config, {})
				end,
				function(f)
					f.materials.fire_material.launchEnabled = false
				end,
				function(f)
					f.materials.fire_material.stackLimit = 1
				end,
				function(f)
					f.recipes.elemental_sword_fire.resultFinishId = "dark"
				end,
				function(f)
					f.recipes.elemental_sword_fire.materials = { water_material = 5 }
				end,
				function(f)
					f.recipes.elemental_sword_fire.durationSeconds = 0 / 0
				end,
				function(f)
					f.recipes.elemental_sword_fire.quantity = 2
				end,
				function(f)
					f.recipes.unreferenced = f.recipes.elemental_sword_fire
				end,
			}
			for _, change in changes do
				local f = fixture()
				change(f)
				local api = ShopCatalog.new(f)
				local ok, code = api.ValidateLaunch()
				expect(ok).toBe(false)
				expect(type(code)).toBe("string")
				local period, resolveCode = api.Resolve(0)
				expect(period).toBeNil()
				expect(resolveCode).toBe(code)
			end
		end
	)

	it(
		"rejects resale loops, insufficient recipe allowances, and unsafe economic products",
		function()
			local changes: { (any) -> () } = {
				function(f)
					f.materials.fire_material.buyGold = 2
				end,
				function(f)
					f.config.rotation[1].sword.unitGold = 100
				end,
				function(f)
					f.config.materials[1].stockLimit = 9
				end,
				function(f)
					f.recipes.elemental_sword_fire.quantity = 4
				end,
				function(f)
					f.recipes.elemental_sword_fire.goldCost = MAX_SAFE_INTEGER
				end,
				function(f)
					f.materials.fire_material.buyGold = MAX_SAFE_INTEGER
				end,
			}
			for _, change in changes do
				local f = fixture()
				change(f)
				expect((ShopCatalog.new(f).ValidateLaunch())).toBe(false)
			end
			local function expensiveResale(id: unknown, finish: unknown?): Types.ResolvedEquipment?
				local item = EquipmentCatalog.Resolve(id, finish)
				if item then
					item = table.clone(item)
					item.sellGold = 150
				end
				return item
			end
			expect((ShopCatalog.new({ resolver = expensiveResale }).ValidateLaunch())).toBe(false)
		end
	)

	it("never truncates long offer identities into ambiguous revisions", function()
		local f = fixture()
		local longId = string.rep("a", 64)
		f.materials[longId] = f.materials.fire_material
		f.materials.fire_material = nil
		f.config.materials[1].materialId = longId
		local api = ShopCatalog.new(f)
		local ok, code = api.ValidateLaunch()
		expect(ok).toBe(false)
		expect(code).toBe("OfferRevisionTooLong")
	end)
end)
