--!strict
-- ReplicatedStorage/Shared/Configurations/Bases

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	initialShrineSlots = 2,
	-- Sequential purchased expansions; the permanent Station never uses these slots.
	buildSlotGrants = { 1, 1, 1, 1 },
	buildSlotUpgradeCosts = {
		{ gold = 10_000, materialQuantity = 50 },
		{ gold = 50_000, materialQuantity = 100 },
		{ gold = 150_000, materialQuantity = 150 },
		{ gold = 500_000, materialQuantity = 200 },
	},
	-- Every expansion pays the same fixed mix, irrespective of the player's Shrine layout.
	expansionMaterialIds = {
		"fire_material",
		"water_material",
		"earth_material",
		"air_material",
		"light_material",
		"dark_material",
	},
	craftingStationId = "basic_crafting_station",
})
