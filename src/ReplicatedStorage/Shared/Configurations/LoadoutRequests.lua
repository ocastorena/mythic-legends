--!strict
-- ReplicatedStorage/Shared/Configurations/LoadoutRequests
-- Shared admission for legacy and retryable loadout routes; preserves existing request tuning.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 12,
	requestRefillPerSecond = 4,
	mutationIntervalSeconds = 0.5,
})
