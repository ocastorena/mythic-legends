--!strict
-- ReplicatedStorage/Shared/Configurations/Mythlings

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)
local Mythlings: { [string]: Types.MythlingDef } = {
	axolotl = {
		displayName = "Stream Axolotl",
		rarity = "Legendary",
		sizeClass = "S",
		zoneRadius = 20,
		fillRate = 10.0,
		drainRate = 10.0,
		description = "A gentle, luminous creature of flowing water that thrives in currents and calms storms within the stream.",
		production = {
			materialId = "essence",
			materialsPerMinute = 1.20,
			baseCapacity = 420,
		},
		variants = {
			regular = {
				model = "Axolotl",
				thumbnail = "rbxassetid://98725818079532",
			},
		},
	},
	dragon = {
		displayName = "Ember Fang",
		rarity = "Common",
		sizeClass = "M",
		zoneRadius = 20,
		fillRate = 5.0, -- 20 eligible seconds; one second absent removes one second earned.
		drainRate = 5.0,
		description = "A rare and regal dragon whose gemstone scales shimmer with light, drawing awe as much as power.",
		production = {
			materialId = "crystal",
			materialsPerMinute = 0.70,
			baseCapacity = 300,
		},
		variants = {
			regular = {
				model = "EmberFang",
				thumbnail = "rbxassetid://93367789665855",
			},
		},
	},
	satyr = {
		displayName = "Shadow Satyr",
		rarity = "Rare",
		sizeClass = "M",
		zoneRadius = 20,
		fillRate = 100 / 35,
		drainRate = 100 / 35,
		description = "A cunning dweller of twilight, dancing between shadows, unseen until its music echoes in silence.",
		production = {
			materialId = "shadow_dust",
			materialsPerMinute = 0.85,
			baseCapacity = 340,
		},
		variants = {
			regular = {
				model = "Satyr",
				thumbnail = "rbxassetid://121639359664798",
			},
		},
	},
}

return FreezeUtil.DeepFreeze(Mythlings)
