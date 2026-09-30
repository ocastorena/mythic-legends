--!strict
-- ReplicatedStorage/Shared/Configurations/InventoryRequests
-- One per-player budget shared by canonical Inventory actions and the retired delete endpoint.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 6,
	requestRefillPerSecond = 2,
})
