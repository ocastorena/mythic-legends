--!strict
-- ReplicatedStorage/Shared/Configurations/BaseRequests
-- Shared admission for the canonical Base view and purchases; legacy stand routes stay separate.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 12,
	requestRefillPerSecond = 4,
})
