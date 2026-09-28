--!strict
-- ReplicatedStorage/Shared/Configurations/Shrines
-- Construction definitions deliberately have no dependency on prototype models or Mythling names.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)

local Shrines: { [string]: Types.ShrineDef } = {
	fire_shrine = {
		displayName = "Fire Shrine",
		element = "Fire",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
	},
	water_shrine = {
		displayName = "Water Shrine",
		element = "Water",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
	},
	earth_shrine = {
		displayName = "Earth Shrine",
		element = "Earth",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
	},
	air_shrine = {
		displayName = "Air Shrine",
		element = "Air",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
	},
	light_shrine = {
		displayName = "Light Shrine",
		element = "Light",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
	},
	dark_shrine = {
		displayName = "Dark Shrine",
		element = "Dark",
		buildGoldCost = 100,
		initialLevel = 1,
		maxLevel = 3,
	},
}

return FreezeUtil.DeepFreeze(Shrines)
