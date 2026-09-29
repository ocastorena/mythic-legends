--!strict
-- ReplicatedStorage/Shared/Configurations/MythlingProgression

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	levelCap = 100,
	xpPerLevel = 120,
	yieldGainPerLevel = 0.01,
})
