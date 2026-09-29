--!strict
-- ReplicatedStorage/Shared/Configurations/Crafting

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	receiptVersion = 1,
	maxResolvedJobs = 32,
	resolutionIntervalSeconds = 1,
})
