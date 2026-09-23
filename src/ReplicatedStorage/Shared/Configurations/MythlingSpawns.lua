--!strict
-- ReplicatedStorage/Shared/Configurations/MythlingSpawns

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)

local MythlingSpawns: Types.MythlingSpawnConfiguration = {
	targetActive = 12,
	refillDeadlineSeconds = 3,
	refillRetrySeconds = 0.1,
	captureTickSeconds = 0.1,
	ringVerticalAllowanceStuds = 12,
	zonePadding = 2,
	boundaryClearance = 12,
	maxPlacementTries = 32,
	fallbackStepStuds = 4,
	-- Preserve the three existing prototype forms and their effective distribution.
	-- The approved 75/20/5 launch pool requires the missing six-element, 18-form catalogue.
	rarityWeights = {
		Common = 100,
		Rare = 50,
		Legendary = 15,
	},
	expireSeconds = {
		Common = 240,
		Rare = 240,
		Epic = 240,
		Legendary = 240,
	},
	formExpireSeconds = {},
	defaultExpireSeconds = 240,
}

return FreezeUtil.DeepFreeze(MythlingSpawns)
