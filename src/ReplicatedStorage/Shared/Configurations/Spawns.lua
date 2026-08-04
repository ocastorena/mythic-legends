-- ReplicatedStorage/Shared/Configurations/Spawns
return {
	TargetActive = 10,            -- how many Mythlings should be alive at once
	SpawnIntervalMin = 10,        -- min seconds between spawns
	SpawnIntervalMax = 15,        -- max seconds between spawns
	ZonePadding = 2,             -- extra space to prevent overlap
	MaxPlacementTries = 16,      -- tries to find valid spawn point
	RarityWeights = {            -- spawn chances
		Common    = 100,
		Rare      = 50,
		Epic      = 30,
		Legendary = 15,
		Secret    = 5,
	},
	ExpireSeconds = {            -- lifetime per rarity
		Common    = 120,
		Rare      = 120,
		Epic      = 120,
		Legendary = 120,
		Secret    = 120,
		
	},
	DefaultExpireSeconds = 60,   -- fallback if rarity missing
}