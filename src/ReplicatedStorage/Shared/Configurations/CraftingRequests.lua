--!strict
-- ReplicatedStorage/Shared/Configurations/CraftingRequests
-- One per-player budget shared by Station reads, starts, and cancellations.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	requestBurst = 12,
	requestRefillPerSecond = 4,
})
