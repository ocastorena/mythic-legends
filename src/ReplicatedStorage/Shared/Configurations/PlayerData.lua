--!strict
-- ReplicatedStorage/Shared/Configurations/PlayerData

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	-- Development namespace. At launch readiness, switch once to MythicLegends_v1 and keep that
	-- namespace stable afterward; never copy, reset, or delete the earlier stores as part of release.
	storeName = "MythicLegends_MVP_v1",
	profileKeyPrefix = "Player_",
	schemaVersion = 7,
	startingGold = 100,
	starterSwordId = "wooden_sword",
	starterShieldId = "wooden_shield",
	maxRequestReceipts = 64,
	maxRequestIdLength = 128,
	maxOperationLength = 64,
	maxSignatureLength = 512,
	maxResultFields = 32,
})
