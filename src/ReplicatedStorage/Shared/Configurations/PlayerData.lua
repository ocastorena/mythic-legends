--!strict
-- ReplicatedStorage/Shared/Configurations/PlayerData

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

return FreezeUtil.DeepFreeze({
	-- Deliberate pre-release fresh start; the prototype namespace is left untouched.
	storeName = "MythicLegends_MVP_v1",
	profileKeyPrefix = "Player_",
	schemaVersion = 6,
	startingGold = 100,
	starterSwordId = "wooden_sword",
	starterShieldId = "wooden_shield",
	maxRequestReceipts = 64,
	maxRequestIdLength = 128,
	maxOperationLength = 64,
	maxSignatureLength = 512,
	maxResultFields = 32,
})
