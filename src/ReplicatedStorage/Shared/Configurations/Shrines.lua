--!strict
-- ReplicatedStorage/Shared/Configurations/Shrines
-- Shrine definitions deliberately have no dependency on prototype models or Mythling names.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)

-- upgradeCost is the cost to REACH that level; level 1 uses the separate buildGoldCost.
local sharedLevels: { [number]: Types.ShrineLevelDef } = {
	[1] = { capacity = 300, workerSlots = 1 },
	[2] = {
		capacity = 1_200,
		workerSlots = 2,
		upgradeCost = { gold = 1_000, materialQuantity = 400 },
	},
	[3] = {
		capacity = 3_600,
		workerSlots = 3,
		upgradeCost = { gold = 15_000, materialQuantity = 4_000 },
	},
}

local Shrines: { [string]: Types.ShrineDef } = {
	fire_shrine = {
		displayName = "Fire Shrine",
		element = "Fire",
		materialId = "fire_material",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
		levels = sharedLevels,
	},
	water_shrine = {
		displayName = "Water Shrine",
		element = "Water",
		materialId = "water_material",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
		levels = sharedLevels,
	},
	earth_shrine = {
		displayName = "Earth Shrine",
		element = "Earth",
		materialId = "earth_material",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
		levels = sharedLevels,
	},
	air_shrine = {
		displayName = "Air Shrine",
		element = "Air",
		materialId = "air_material",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
		levels = sharedLevels,
	},
	light_shrine = {
		displayName = "Light Shrine",
		element = "Light",
		materialId = "light_material",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
		levels = sharedLevels,
	},
	dark_shrine = {
		displayName = "Dark Shrine",
		element = "Dark",
		materialId = "dark_material",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
		levels = sharedLevels,
	},
}

return FreezeUtil.DeepFreeze(Shrines)
