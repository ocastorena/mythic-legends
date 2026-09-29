--!strict
-- ReplicatedStorage/Shared/Configurations/EquipmentRecipes
-- Fixed launch recipes; active jobs will retain their agreed costs, result IDs, and deadline.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)

local EquipmentRecipes: { [string]: Types.EquipmentRecipe } = {
	elemental_sword_fire = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { fire_material = 5 },
		resultDefinitionId = "elemental_sword",
		resultFinishId = "fire",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_sword_water = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { water_material = 5 },
		resultDefinitionId = "elemental_sword",
		resultFinishId = "water",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_sword_earth = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { earth_material = 5 },
		resultDefinitionId = "elemental_sword",
		resultFinishId = "earth",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_sword_air = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { air_material = 5 },
		resultDefinitionId = "elemental_sword",
		resultFinishId = "air",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_sword_light = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { light_material = 5 },
		resultDefinitionId = "elemental_sword",
		resultFinishId = "light",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_sword_dark = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { dark_material = 5 },
		resultDefinitionId = "elemental_sword",
		resultFinishId = "dark",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_shield_fire = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { fire_material = 5 },
		resultDefinitionId = "elemental_shield",
		resultFinishId = "fire",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_shield_water = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { water_material = 5 },
		resultDefinitionId = "elemental_shield",
		resultFinishId = "water",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_shield_earth = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { earth_material = 5 },
		resultDefinitionId = "elemental_shield",
		resultFinishId = "earth",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_shield_air = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { air_material = 5 },
		resultDefinitionId = "elemental_shield",
		resultFinishId = "air",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_shield_light = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { light_material = 5 },
		resultDefinitionId = "elemental_shield",
		resultFinishId = "light",
		quantity = 1,
		durationSeconds = 60,
	},
	elemental_shield_dark = {
		craftingStationId = "basic_crafting_station",
		goldCost = 50,
		materials = { dark_material = 5 },
		resultDefinitionId = "elemental_shield",
		resultFinishId = "dark",
		quantity = 1,
		durationSeconds = 60,
	},
}

return FreezeUtil.DeepFreeze(EquipmentRecipes)
