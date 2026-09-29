--!strict
-- ServerStorage/Databases/PlayerDataTemplate

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Configuration = require(game:GetService("ReplicatedStorage").Shared.Configurations.PlayerData)

local PlayerDataTemplate: Types.PlayerDoc = {
	version = Configuration.schemaVersion,
	profile = {
		userId = 0,
		createdAt = 0,
		lastLoginAt = 0,
	},
	currency = {
		gold = Configuration.startingGold,
	},
	materials = {},
	inventoryUpgrades = { materials = 0, mythlings = 0, equipment = 0 },
	transactions = { revision = 0, receipts = {} },
	craftingJobs = {},
	equipment = {
		starter_wooden_sword = {
			definitionId = Configuration.starterSwordId,
			isStarterGrant = true,
		},
		starter_wooden_shield = {
			definitionId = Configuration.starterShieldId,
			isStarterGrant = true,
		},
	},
	combatLoadout = {
		primaryWeaponInstanceId = "starter_wooden_sword",
		shieldInstanceId = "starter_wooden_shield",
	},
	mythlings = {},
	-- ProfileSchema creates productionClock once using server time; no static accrual sentinel.
	base = {
		stands = {},
		buildSlotUpgrades = 0,
		shrines = {},
		-- The load boundary creates a unique permanent Station before exposing this profile.
	},
}

return PlayerDataTemplate
