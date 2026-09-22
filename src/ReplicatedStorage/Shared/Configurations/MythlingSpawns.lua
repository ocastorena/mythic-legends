--!strict
-- ReplicatedStorage/Shared/Configurations/MythlingSpawns

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)

local MythlingSpawns: Types.MythlingSpawnConfiguration = {
	targetActive = 10, -- how many Mythlings should be alive at once
	spawnIntervalMin = 10, -- min seconds between spawns
	spawnIntervalMax = 15, -- max seconds between spawns
	zonePadding = 2, -- extra space to prevent overlap
	maxPlacementTries = 16, -- tries to find valid spawn point
	rarityWeights = { -- spawn chances
		Common = 100,
		Rare = 50,
		Epic = 30,
		Legendary = 15,
		Secret = 5,
	},
	expireSeconds = { -- lifetime per rarity
		Common = 120,
		Rare = 120,
		Epic = 120,
		Legendary = 120,
		Secret = 120,
	},
	defaultExpireSeconds = 60, -- fallback if rarity missing
}

return FreezeUtil.DeepFreeze(MythlingSpawns)
