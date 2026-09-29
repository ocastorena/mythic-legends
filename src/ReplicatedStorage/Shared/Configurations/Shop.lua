--!strict
-- ReplicatedStorage/Shared/Configurations/Shop
-- Publish catalogue/tuning changes at a shared scheduled boundary, never during a period.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

local Shop = {
	epochSeconds = 0,
	refreshSeconds = 3_600,
	materials = {
		{ materialId = "fire_material", stockLimit = 10 },
		{ materialId = "water_material", stockLimit = 10 },
		{ materialId = "earth_material", stockLimit = 10 },
		{ materialId = "air_material", stockLimit = 10 },
		{ materialId = "light_material", stockLimit = 10 },
		{ materialId = "dark_material", stockLimit = 10 },
	},
	rotation = {
		{
			element = "Fire",
			sword = {
				definitionId = "elemental_sword",
				finishId = "fire",
				recipeId = "elemental_sword_fire",
				unitGold = 150,
				stockLimit = 1,
			},
			shield = {
				definitionId = "elemental_shield",
				finishId = "fire",
				recipeId = "elemental_shield_fire",
				unitGold = 150,
				stockLimit = 1,
			},
		},
		{
			element = "Water",
			sword = {
				definitionId = "elemental_sword",
				finishId = "water",
				recipeId = "elemental_sword_water",
				unitGold = 150,
				stockLimit = 1,
			},
			shield = {
				definitionId = "elemental_shield",
				finishId = "water",
				recipeId = "elemental_shield_water",
				unitGold = 150,
				stockLimit = 1,
			},
		},
		{
			element = "Earth",
			sword = {
				definitionId = "elemental_sword",
				finishId = "earth",
				recipeId = "elemental_sword_earth",
				unitGold = 150,
				stockLimit = 1,
			},
			shield = {
				definitionId = "elemental_shield",
				finishId = "earth",
				recipeId = "elemental_shield_earth",
				unitGold = 150,
				stockLimit = 1,
			},
		},
		{
			element = "Air",
			sword = {
				definitionId = "elemental_sword",
				finishId = "air",
				recipeId = "elemental_sword_air",
				unitGold = 150,
				stockLimit = 1,
			},
			shield = {
				definitionId = "elemental_shield",
				finishId = "air",
				recipeId = "elemental_shield_air",
				unitGold = 150,
				stockLimit = 1,
			},
		},
		{
			element = "Light",
			sword = {
				definitionId = "elemental_sword",
				finishId = "light",
				recipeId = "elemental_sword_light",
				unitGold = 150,
				stockLimit = 1,
			},
			shield = {
				definitionId = "elemental_shield",
				finishId = "light",
				recipeId = "elemental_shield_light",
				unitGold = 150,
				stockLimit = 1,
			},
		},
		{
			element = "Dark",
			sword = {
				definitionId = "elemental_sword",
				finishId = "dark",
				recipeId = "elemental_sword_dark",
				unitGold = 150,
				stockLimit = 1,
			},
			shield = {
				definitionId = "elemental_shield",
				finishId = "dark",
				recipeId = "elemental_shield_dark",
				unitGold = 150,
				stockLimit = 1,
			},
		},
	},
}

return FreezeUtil.DeepFreeze(Shop)
