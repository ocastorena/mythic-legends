--!strict
-- ReplicatedStorage/Shared/Configurations/CraftingStations

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

local definitions: {
	[string]: {
		displayName: string,
		modelName: string,
		interactionAnchorPath: { string },
		interactionDistanceStuds: number,
	},
} =
	{
		basic_crafting_station = {
			displayName = "Crafting Station",
			modelName = "PB_CraftingStation_Root",
			interactionAnchorPath = {
				"PB_CraftingStation",
				"PB_CraftingStation_Mesh",
				"CraftingPromptAttachment",
			},
			interactionDistanceStuds = 4,
		},
	}

return FreezeUtil.DeepFreeze(definitions)
