--!strict
-- ServerScriptService/Services/DataService/StarterEquipment
-- Recognize only untouched initialization state; ambiguous retained data receives no new grant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Types = require(ReplicatedStorage.Shared.Types)

local StarterEquipment = {}

export type Grant = {
	equipment: { [string]: Types.EquipmentEntry },
	primaryWeaponInstanceId: string,
	shieldInstanceId: string,
}

local function onlyFields(value: unknown, allowed: { [string]: boolean }): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	for key in value do
		if type(key) ~= "string" or not allowed[key] then
			return false
		end
	end
	return true
end

local function empty(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil and next(value) == nil
end

-- ProfileSchema validates the Base and clock separately before applying this detached candidate.
-- Existing content, missing state, or future fields are not evidence of an untouched new profile.
function StarterEquipment.Stage(data: Types.PlayerDoc): Grant?
	if
		not onlyFields(data, {
			version = true,
			profile = true,
			currency = true,
			materials = true,
			inventoryUpgrades = true,
			transactions = true,
			craftingJobs = true,
			equipment = true,
			combatLoadout = true,
			mythlings = true,
			base = true,
			productionClock = true,
		})
		or not onlyFields(data.profile, { userId = true, createdAt = true, lastLoginAt = true })
		or data.profile.userId ~= 0
		or data.profile.createdAt ~= 0
		or data.profile.lastLoginAt ~= 0
		or not onlyFields(data.currency, { gold = true })
		or data.currency.gold ~= Configuration.startingGold
		or not empty(data.equipment)
		or not empty(data.combatLoadout)
		or not empty(data.materials)
		or not empty(data.mythlings)
		or not empty(data.craftingJobs)
	then
		return nil
	end

	local upgrades = data.inventoryUpgrades
	local transactions = data.transactions
	if
		not onlyFields(upgrades, { materials = true, mythlings = true, equipment = true })
		or upgrades == nil
		or upgrades.materials ~= 0
		or upgrades.mythlings ~= 0
		or upgrades.equipment ~= 0
		or not onlyFields(transactions, { revision = true, receipts = true })
		or transactions == nil
		or transactions.revision ~= 0
		or not empty(transactions.receipts)
		or not onlyFields(data.base, {
			stands = true,
			buildSlotUpgrades = true,
			shrines = true,
			craftingStation = true,
		})
		or data.base.buildSlotUpgrades ~= 0
		or not empty(data.base.stands)
		or not empty(data.base.shrines)
	then
		return nil
	end

	local station = data.base.craftingStation
	local clock = data.productionClock
	if
		(station ~= nil and not onlyFields(station, { id = true, craftingStationId = true }))
		or (
			clock ~= nil
			and not onlyFields(clock, {
				lastAccruedAt = true,
				nextBatchAt = true,
				lastOnlineCheckpointAt = true,
				offlineSince = true,
			})
		)
	then
		return nil
	end

	return {
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
		primaryWeaponInstanceId = "starter_wooden_sword",
		shieldInstanceId = "starter_wooden_shield",
	}
end

return table.freeze(StarterEquipment)
