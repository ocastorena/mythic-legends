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
	-- Canonical launch selection is validated before startup; activation still needs form assets.
	rarityWeights = {
		Common = 75,
		Rare = 20,
		Epic = 5,
	},
	-- Explicit compatibility pool until approved model bindings replace the three live prototypes.
	prototypeRarityWeights = {
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
	defaultExpireSeconds = 240, -- Retained compatibility metadata; enabled rarities require defaults.
}

return FreezeUtil.DeepFreeze(MythlingSpawns)
