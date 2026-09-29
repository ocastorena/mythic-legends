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
	-- ProfileSchema grants the starter pair once; reconciliation must not refill empty slots.
	equipment = {},
	combatLoadout = {},
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
