--!strict
-- ReplicatedStorage/Shared/Configurations/ShopRequests
-- One per-player request budget shared by Shop views and offer purchases.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 6,
	requestRefillPerSecond = 2,
})
