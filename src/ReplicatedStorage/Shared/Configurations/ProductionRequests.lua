--!strict
-- ReplicatedStorage/Shared/Configurations/ProductionRequests
-- Canonical Shrine collection has a separate budget from retained prototype stand requests.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 12,
	requestRefillPerSecond = 4,
})
