--!strict
-- ServerStorage/Databases/PlayerDataTemplate

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local PlayerDataTemplate: Types.PlayerDoc = {
	version = 3,
	profile = {
		userId = 0,
		createdAt = 0,
		lastLoginAt = 0,
	},
	currency = {
		gold = 0,
	},
	materials = {},
	consumables = {},
	equipment = {
		starter_wooden_sword = { definitionId = "wooden_sword" },
		starter_wooden_shield = { definitionId = "wooden_shield" },
	},
	combatLoadout = {
		primaryWeaponInstanceId = "starter_wooden_sword",
		shieldInstanceId = "starter_wooden_shield",
	},
	mythlings = {},
	base = {
		stands = {},
	},
}

return PlayerDataTemplate
