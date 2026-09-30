--!strict
-- ReplicatedStorage/Shared/Configurations/BaseRequests
-- Shared admission for canonical Base/Shrine views and actions; legacy stand routes stay separate.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 12,
	requestRefillPerSecond = 4,
})
