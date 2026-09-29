--!strict
-- ReplicatedStorage/Shared/Configurations/Production

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	batchIntervalSeconds = 1,
	baseXpPerSecond = 1,
	onlineCheckpointIntervalSeconds = 30,
})
