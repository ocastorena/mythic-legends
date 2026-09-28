--!strict
-- ReplicatedStorage/Shared/Configurations/Bases

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	initialShrineSlots = 2,
	-- Sequential purchased expansions; the permanent Station never uses these slots.
	buildSlotGrants = { 1, 1, 1, 1 },
	craftingStationId = "basic_crafting_station",
})
