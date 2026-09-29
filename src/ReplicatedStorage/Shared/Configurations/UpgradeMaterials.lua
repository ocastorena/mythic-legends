--!strict
-- ReplicatedStorage/Shared/Configurations/UpgradeMaterials
-- The fixed normal-Material mix shared by paid Base and Inventory-capacity upgrades.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	"fire_material",
	"water_material",
	"earth_material",
	"air_material",
	"light_material",
	"dark_material",
})
