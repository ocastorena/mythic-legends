--!strict
-- ServerStorage/Tests/__tests__/EquipmentCatalog.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Equipment = require(ReplicatedStorage.Shared.Configurations.Equipment)
local Recipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local Effects = require(ReplicatedStorage.Shared.Configurations.ElementalSwordEffects)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local Stations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local EquipmentCatalogUtil = require(ServerScriptService.Shared.EquipmentCatalogUtil)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local VARIANTS = {
	{ id = "fire", element = "Fire", name = "Vulcan", effect = "fire_burn" },
	{ id = "water", element = "Water", name = "Triton", effect = "water_slow" },
	{ id = "earth", element = "Earth", name = "Atlas", effect = "earth_root" },
	{ id = "air", element = "Air", name = "Aura", effect = "air_knockback" },
	{ id = "light", element = "Light", name = "Sol", effect = "light_weaken" },
	{ id = "dark", element = "Dark", name = "Nyx", effect = "dark_refund" },
}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function count<T>(value: { [string]: T }): number
	local total = 0
	for _ in value do
		total += 1
	end
	return total
end

-- Detached, deliberately dynamic fixtures permit invalid metadata without changing live config.
type Catalogs = {
	equipment: any,
	recipes: any,
	effects: any,
	materials: any,
	stations: any,
}

local function catalogs(): Catalogs
	return {
		equipment = copy(Equipment),
		recipes = copy(Recipes),
		effects = copy(Effects),
		materials = copy(Materials),
		stations = copy(Stations),
	}
end

local function expectValid(c: Catalogs)
	local ok, problem = EquipmentCatalogUtil.ValidateLaunch(
		c.equipment,
		c.recipes,
		c.effects,
		c.materials,
		c.stations
	)
	expect(ok).toBe(true)
	expect(problem).toBeNil()
end

local function expectInvalid(c: Catalogs)
	FreezeUtil.DeepFreeze(c)
	local ok, problem = EquipmentCatalogUtil.ValidateLaunch(
		c.equipment,
		c.recipes,
		c.effects,
		c.materials,
		c.stations
	)
	expect(ok).toBe(false)
	expect(type(problem)).toBe("string")
	expect(problem == "").toBe(false)
end

describe("Equipment catalogue", function()
	it("keeps only the unchanged wooden pair in active combat profiles", function()
		expect(count(Equipment.profiles)).toBe(2)
		expect(count(Equipment.definitions)).toBe(4)
		for _, id in { "wooden_sword", "wooden_shield" } do
			local resolved =
				assert(EquipmentCatalog.Resolve(id), "[EquipmentCatalog.spec] Missing starter")
			expect(Equipment.definitions[id]).toBe(Equipment.profiles[id])
			expect(resolved.profile).toBe(Equipment.profiles[id])
			expect(resolved.rarity).toBe("Common")
			expect(resolved.finishId).toBeNil()
			expect(resolved.element).toBeNil()
			expect(resolved.effectId).toBeNil()
		end
		expect(Equipment.profiles.wooden_sword.modelName).toBe("WoodenSword")
		expect(Equipment.profiles.wooden_sword.staminaCost).toBe(20)
		expect(Equipment.profiles.wooden_sword.cooldownSeconds).toBe(1)
		expect(Equipment.profiles.wooden_sword.planarKnockback).toBe(56)
		expect(Equipment.profiles.wooden_sword.verticalKnockback).toBe(58)
		expect(Equipment.profiles.wooden_shield.modelName).toBe("WoodenShield")
		expect(Equipment.profiles.wooden_shield.impactStaminaCost).toBe(30)
		expect(Equipment.profiles.wooden_shield.minimumGuardStamina).toBe(30)
		expect(Equipment.profiles.elemental_sword).toBeNil()
		expect(Equipment.profiles.elemental_shield).toBeNil()
	end)

	it(
		"resolves all twelve fixed Rare variants by IDs to one shared profile per equipment type",
		function()
			for _, variant in VARIANTS do
				for _, kind in { "sword", "shield" } do
					local definitionId = `elemental_{kind}`
					local definition = Equipment.definitions[definitionId]
					local resolved = assert(
						EquipmentCatalog.Resolve(definitionId, variant.id),
						"[EquipmentCatalog.spec] Missing variant"
					)
					expect(resolved.definitionId).toBe(definitionId)
					expect(resolved.finishId).toBe(variant.id)
					expect(resolved.displayName).toBe(
						`{variant.name} {if kind == "sword" then "Sword" else "Shield"}`
					)
					expect(resolved.rarity).toBe("Rare")
					expect(resolved.element).toBe(variant.element)
					expect(resolved.profile).toBe(definition)
					expect(resolved.sellGold).toBe(25)
					expect(resolved.effectId).toBe(if kind == "sword" then variant.effect else nil)
					expect(#resolved.description > 0).toBe(true)
					expect(definition.stage).toBe(1)
					expect(definition.modelName).toBe("")
				end
			end
			local sword = Equipment.definitions.elemental_sword
			local shield = Equipment.definitions.elemental_shield
			expect(sword.handsRequired).toBe(1)
			for _, field in
				{
					"staminaCost",
					"cooldownSeconds",
					"swingDurationSeconds",
					"hitStartFallbackSeconds",
					"contactWindowSeconds",
					"hitStopSeconds",
					"reachStuds",
					"serverToleranceStuds",
					"requireLineOfSight",
					"planarKnockback",
					"verticalKnockback",
					"tumbleAngularSpeed",
					"launchControlSeconds",
					"maximumReactionSeconds",
					"landingRecoverySeconds",
				}
			do
				expect((sword :: any)[field]).toBe((Equipment.profiles.wooden_sword :: any)[field])
			end
			expect(shield.impactStaminaCost).toBe(25)
			expect(shield.minimumGuardStamina).toBe(25)
		end
	)

	it("gives every named variant one matching fixed sixty-second Equipment recipe", function()
		expect(count(Recipes)).toBe(12)
		for _, variant in VARIANTS do
			for _, kind in { "sword", "shield" } do
				local definitionId = `elemental_{kind}`
				expect(Recipes[`{definitionId}_{variant.id}`]).toEqual({
					craftingStationId = "basic_crafting_station",
					goldCost = 50,
					materials = { [`{variant.id}_material`] = 5 },
					resultDefinitionId = definitionId,
					resultFinishId = variant.id,
					quantity = 1,
					durationSeconds = 60,
				})
			end
		end
	end)

	it("stores the six approved effect roles and initial magnitudes as metadata", function()
		local expected: { [string]: { [string]: string | number } } = {
			fire_burn = {
				element = "Fire",
				kind = "Burn",
				staminaPerSecond = 15,
				durationSeconds = 2,
			},
			water_slow = {
				element = "Water",
				kind = "Slow",
				walkSpeedMultiplier = 0.75,
				durationSeconds = 2,
			},
			earth_root = {
				element = "Earth",
				kind = "Root",
				rootSeconds = 0.75,
				landingTimeoutSeconds = 3,
				recoverySeconds = 3,
			},
			air_knockback = { element = "Air", kind = "Push", horizontalMultiplier = 1.15 },
			light_weaken = {
				element = "Light",
				kind = "Weaken",
				horizontalMultiplier = 0.8,
				durationSeconds = 2,
			},
			dark_refund = { element = "Dark", kind = "Refund", stamina = 3 },
		}
		expect(count(Effects)).toBe(6)
		for id, tuning in expected do
			local effect = Effects[id]
			expect(#effect.description > 0).toBe(true)
			for field, value in tuning do
				expect((effect :: any)[field]).toBe(value)
			end
		end
	end)

	it(
		"deep-freezes configuration and resolved metadata without copied gameplay overrides",
		function()
			local function expectFrozen(value: unknown)
				if type(value) ~= "table" then
					return
				end
				expect(table.isfrozen(value)).toBe(true)
				for _, child in value do
					expectFrozen(child)
				end
			end
			expectFrozen(Equipment)
			expectFrozen(Recipes)
			expectFrozen(Effects)
			local result = assert(
				EquipmentCatalog.Resolve("elemental_sword", "earth"),
				"[EquipmentCatalog.spec] Missing Atlas Sword"
			)
			expectFrozen(result)
			expect((result :: any).staminaCost).toBeNil()
			expect((result :: any).planarKnockback).toBeNil()
			expect(result.profile).toBe(Equipment.definitions.elemental_sword)
		end
	)

	it(
		"rejects unknown definitions, malformed IDs, missing crafted variants, and any wooden finish",
		function()
			for _, id in { "unknown", "Atlas Sword", "", string.rep("x", 129), false, 1, {} } do
				expect(EquipmentCatalog.Resolve(id)).toBeNil()
			end
			expect(EquipmentCatalog.Resolve(nil)).toBeNil()
			for _, id in { "elemental_sword", "elemental_shield" } do
				expect(EquipmentCatalog.Resolve(id)).toBeNil()
				for _, finish in
					{
						"",
						"unknown",
						"Earth",
						"Atlas Sword",
						"regular",
						false,
						1,
						{},
						string.rep("x", 129),
					}
				do
					expect(EquipmentCatalog.Resolve(id, finish)).toBeNil()
				end
			end
			for _, id in { "wooden_sword", "wooden_shield" } do
				for _, finish in { "", "regular", "fire", false, 1, {} } do
					expect(EquipmentCatalog.Resolve(id, finish)).toBeNil()
				end
			end
		end
	)
end)

describe("EquipmentCatalogUtil.ValidateLaunch", function()
	it("accepts the real catalogue and does not rewrite or freeze detached valid inputs", function()
		expectValid({
			equipment = Equipment,
			recipes = Recipes,
			effects = Effects,
			materials = Materials,
			stations = Stations,
		})
		local c = catalogs()
		local before = copy(c)
		expectValid(c)
		expect(c).toEqual(before)
		expect(table.isfrozen(c.equipment.definitions.elemental_sword)).toBe(false)
		expect(table.isfrozen(c.recipes.elemental_sword_fire.materials)).toBe(false)
	end)

	it(
		"accepts coherent changed tuning instead of enforcing literal trial prices and timings",
		function()
			local c = catalogs()
			for _, sword in
				{
					c.equipment.profiles.wooden_sword,
					c.equipment.definitions.wooden_sword,
					c.equipment.definitions.elemental_sword,
				}
			do
				sword.staminaCost = 24
				sword.cooldownSeconds = 1.1
			end
			c.effects.fire_burn.staminaPerSecond = 12
			c.effects.fire_burn.durationSeconds = 1.5
			c.effects.water_slow.walkSpeedMultiplier = 0.8
			c.effects.earth_root.rootSeconds = 0.6
			c.effects.air_knockback.horizontalMultiplier = 1.2
			c.effects.light_weaken.horizontalMultiplier = 0.85
			c.effects.dark_refund.stamina = 4
			c.equipment.definitions.elemental_sword.sale.gold = 30
			c.equipment.definitions.elemental_shield.sale.gold = 30
			for _, recipe in c.recipes do
				recipe.goldCost = 60
				recipe.durationSeconds = 75
				for materialId in recipe.materials do
					recipe.materials[materialId] = 6
				end
			end
			expectValid(c)
		end
	)

	it("fails closed for malformed root catalogues", function()
		for _, field in { "equipment", "recipes", "effects", "materials", "stations" } do
			for _, value in { false, "catalogue", 1, {} } do
				local c = catalogs()
				local raw = c :: any
				raw[field] = value
				expectInvalid(c)
			end
			local missing = catalogs()
			local raw = missing :: any
			raw[field] = nil
			expectInvalid(missing)
		end
	end)

	it(
		"rejects malformed nested metadata and metatables without throwing or rewriting inputs",
		function()
			for _, location in
				{
					"equipment",
					"definition",
					"finishes",
					"finish",
					"effect",
					"recipe",
					"ingredients",
					"station",
				}
			do
				local c = catalogs()
				local targets = {
					equipment = c.equipment,
					definition = c.equipment.definitions.elemental_sword,
					finishes = c.equipment.definitions.elemental_sword.finishes,
					finish = c.equipment.definitions.elemental_sword.finishes.fire,
					effect = c.effects.fire_burn,
					recipe = c.recipes.elemental_sword_fire,
					ingredients = c.recipes.elemental_sword_fire.materials,
					station = c.stations.basic_crafting_station,
				}
				setmetatable(targets[location], {})
				expectInvalid(c)
			end
		end
	)

	local invalidCases: { { label: string, change: (Catalogs) -> () } } = {
		{
			label = "crafted sword has the wrong role",
			change = function(c)
				c.equipment.definitions.elemental_sword.kind = "Shield"
			end,
		},
		{
			label = "new acquisitions include Stage 2",
			change = function(c)
				c.equipment.definitions.elemental_sword.stage = 2
			end,
		},
		{
			label = "crafted sword requires two hands",
			change = function(c)
				c.equipment.definitions.elemental_sword.handsRequired = 2
			end,
		},
		{
			label = "crafted sword changes shared reach",
			change = function(c)
				c.equipment.definitions.elemental_sword.reachStuds += 1
			end,
		},
		{
			label = "crafted sword changes shared Stamina",
			change = function(c)
				c.equipment.definitions.elemental_sword.staminaCost += 1
			end,
		},
		{
			label = "wooden definition disagrees with its combat profile",
			change = function(c)
				c.equipment.definitions.wooden_sword.planarKnockback += 1
			end,
		},
		{
			label = "Shield minimum cannot pay a block",
			change = function(c)
				c.equipment.definitions.elemental_shield.minimumGuardStamina = 24
			end,
		},
		{
			label = "a launch element finish is missing",
			change = function(c)
				c.equipment.definitions.elemental_shield.finishes.earth = nil
			end,
		},
		{
			label = "variant elements are duplicated",
			change = function(c)
				c.equipment.definitions.elemental_sword.finishes.earth.element = "Fire"
			end,
		},
		{
			label = "variant rarity activates future Equipment",
			change = function(c)
				c.equipment.definitions.elemental_sword.finishes.fire.rarity = "Epic"
			end,
		},
		{
			label = "finish overrides base gameplay",
			change = function(c)
				c.equipment.definitions.elemental_sword.finishes.fire.staminaCost = 1
			end,
		},
		{
			label = "finish overrides sale value",
			change = function(c)
				c.equipment.definitions.elemental_shield.finishes.fire.sale = { gold = 999 }
			end,
		},
		{
			label = "a Shield gains a sword effect",
			change = function(c)
				c.equipment.definitions.elemental_shield.finishes.fire.effectId = "fire_burn"
			end,
		},
		{
			label = "a sword references another element's effect",
			change = function(c)
				c.equipment.definitions.elemental_sword.finishes.fire.effectId = "water_slow"
			end,
		},
		{
			label = "a sword effect reference is missing",
			change = function(c)
				c.equipment.definitions.elemental_sword.finishes.fire.effectId = nil
			end,
		},
		{
			label = "an effect uses the wrong role",
			change = function(c)
				c.effects.fire_burn.kind = "Slow"
			end,
		},
		{
			label = "Water does not slow movement",
			change = function(c)
				c.effects.water_slow.walkSpeedMultiplier = 1
			end,
		},
		{
			label = "Air does not increase horizontal force",
			change = function(c)
				c.effects.air_knockback.horizontalMultiplier = 1
			end,
		},
		{
			label = "Light increases outgoing force",
			change = function(c)
				c.effects.light_weaken.horizontalMultiplier = 1.1
			end,
		},
		{
			label = "Earth has no landing deadline",
			change = function(c)
				c.effects.earth_root.landingTimeoutSeconds = 0
			end,
		},
		{
			label = "a timed effect has nonfinite duration",
			change = function(c)
				c.effects.fire_burn.durationSeconds = math.huge
			end,
		},
		{
			label = "Dark sustains full-rate attacks after recovery",
			change = function(c)
				c.effects.dark_refund.stamina = 10
			end,
		},
		{
			label = "a required recipe is absent",
			change = function(c)
				c.recipes.elemental_shield_earth = nil
			end,
		},
		{
			label = "two recipes grant the same result",
			change = function(c)
				c.recipes.duplicate = copy(c.recipes.elemental_sword_fire)
			end,
		},
		{
			label = "recipe output omits its variant",
			change = function(c)
				c.recipes.elemental_sword_fire.resultFinishId = nil
			end,
		},
		{
			label = "recipe output references an unknown variant",
			change = function(c)
				c.recipes.elemental_sword_fire.resultFinishId = "unknown"
			end,
		},
		{
			label = "recipe output references starter gear",
			change = function(c)
				c.recipes.elemental_sword_fire.resultDefinitionId = "wooden_sword"
			end,
		},
		{
			label = "recipe substitutes another element",
			change = function(c)
				c.recipes.elemental_sword_fire.materials = { water_material = 5 }
			end,
		},
		{
			label = "recipe mixes Material elements",
			change = function(c)
				c.recipes.elemental_sword_fire.materials.water_material = 1
			end,
		},
		{
			label = "recipe activates legacy Materials",
			change = function(c)
				c.recipes.elemental_sword_fire.materials = { essence = 5 }
			end,
		},
		{
			label = "recipe has fractional ingredient quantity",
			change = function(c)
				c.recipes.elemental_sword_fire.materials.fire_material = 0.5
			end,
		},
		{
			label = "recipe has no Gold cost",
			change = function(c)
				c.recipes.elemental_sword_fire.goldCost = 0
			end,
		},
		{
			label = "recipe has invalid output quantity",
			change = function(c)
				c.recipes.elemental_sword_fire.quantity = 0
			end,
		},
		{
			label = "recipe has no completion duration",
			change = function(c)
				c.recipes.elemental_sword_fire.durationSeconds = 0
			end,
		},
		{
			label = "recipe references an unknown Station",
			change = function(c)
				c.recipes.elemental_sword_fire.craftingStationId = "missing_station"
			end,
		},
		{
			label = "Equipment resale breaks even with bought-input crafting",
			change = function(c)
				c.equipment.definitions.elemental_sword.sale.gold = 100
			end,
		},
		{
			label = "Equipment resale is profitable",
			change = function(c)
				c.equipment.definitions.elemental_shield.sale.gold = 101
			end,
		},
		{
			label = "Material resale breaks even with purchase",
			change = function(c)
				c.materials.fire_material.sellGold = 10
			end,
		},
		{
			label = "Station has an invalid display name",
			change = function(c)
				c.stations.basic_crafting_station.displayName = ""
			end,
		},
		{
			label = "Station has an invalid model binding",
			change = function(c)
				c.stations.basic_crafting_station.modelName = false
			end,
		},
		{
			label = "referenced Material has no valid stack limit",
			change = function(c)
				c.materials.fire_material.stackLimit = 0
			end,
		},
		{
			label = "wooden combat profile overrides its name",
			change = function(c)
				c.equipment.profiles.wooden_sword.displayName = "Replaced"
			end,
		},
		{
			label = "wooden combat profile overrides its animation",
			change = function(c)
				c.equipment.profiles.wooden_sword.animationId = "rbxassetid://1"
			end,
		},
		{
			label = "wooden combat profile gains a sword effect",
			change = function(c)
				c.equipment.profiles.wooden_sword.effectId = "fire_burn"
			end,
		},
		{
			label = "wooden combat profile gains sale metadata",
			change = function(c)
				c.equipment.profiles.wooden_shield.sale = { gold = 25 }
			end,
		},
		{
			label = "sword definition gains Shield gameplay",
			change = function(c)
				c.equipment.definitions.elemental_sword.impactStaminaCost = 25
			end,
		},
		{
			label = "Shield definition gains sword gameplay",
			change = function(c)
				c.equipment.definitions.elemental_shield.staminaCost = 20
			end,
		},
	}
	for _, case in invalidCases do
		it(`rejects when {case.label}`, function()
			local c = catalogs()
			case.change(c)
			expectInvalid(c)
		end)
	end
end)
