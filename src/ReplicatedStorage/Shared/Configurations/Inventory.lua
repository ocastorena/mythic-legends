--!strict
-- ReplicatedStorage/Shared/Configurations/Inventory

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	mythlingCapacities = { 24, 36, 48 },
})
