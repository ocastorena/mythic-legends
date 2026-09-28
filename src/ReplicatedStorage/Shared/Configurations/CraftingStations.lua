--!strict
-- ReplicatedStorage/Shared/Configurations/CraftingStations

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

local definitions: { [string]: { displayName: string, modelName: string } } = {
	basic_crafting_station = {
		displayName = "Crafting Station",
		modelName = "PB_CraftingStation_Root",
	},
}

return FreezeUtil.DeepFreeze(definitions)
