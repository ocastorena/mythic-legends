--!strict
-- ServerScriptService/Domain/Base/BaseState
-- Read-only validation and derived Shrine-only capacity shared by persistence and presentation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = require(ReplicatedStorage.Shared.Configurations.Bases)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseState = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

function BaseState.GetStatus(base: Types.BaseRecord): Types.BaseStatus?
	if type(base) ~= "table" then
		return nil
	end
	local upgrades = base.buildSlotUpgrades
	if
		type(upgrades) ~= "number"
		or upgrades ~= upgrades
		or upgrades < 0
		or upgrades > #Configuration.buildSlotGrants
		or upgrades % 1 ~= 0
	then
		return nil
	end

	local unlocked = Configuration.initialShrineSlots
	local maximum = unlocked
	for index, grant in Configuration.buildSlotGrants do
		maximum += grant
		if index <= upgrades then
			unlocked += grant
		end
	end

	local station = base.craftingStation
	if
		type(station) ~= "table"
		or not isId(station.id)
		or not isId(station.craftingStationId)
		or not CraftingStations[station.craftingStationId]
	then
		return nil
	end

	local shrines = base.shrines
	if type(shrines) ~= "table" then
		return nil
	end
	local used = 0
	for id, shrine in shrines do
		if
			not isId(id)
			or id == station.id
			or type(shrine) ~= "table"
			or shrine.id ~= id
			or not isId(shrine.shrineId)
		then
			return nil
		end
		used += 1
	end
	if used > unlocked then
		return nil
	end

	return {
		usedShrineSlots = used,
		unlockedShrineSlots = unlocked,
		maxShrineSlots = maximum,
		craftingStation = { id = station.id, craftingStationId = station.craftingStationId },
	}
end

return table.freeze(BaseState)
