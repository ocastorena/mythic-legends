--!strict
-- ServerScriptService/Shared/BaseState
-- Read-only validation and derived Shrine-only capacity shared by persistence and presentation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = require(ReplicatedStorage.Shared.Configurations.Bases)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseState = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

function BaseState.GetSlotLimits(upgrades: unknown): (number?, number?)
	if
		type(upgrades) ~= "number"
		or upgrades ~= upgrades
		or upgrades < 0
		or upgrades > #Configuration.buildSlotGrants
		or upgrades % 1 ~= 0
	then
		return nil, nil
	end

	local unlocked = Configuration.initialShrineSlots
	local maximum = unlocked
	for index, grant in Configuration.buildSlotGrants do
		maximum += grant
		if index <= upgrades then
			unlocked += grant
		end
	end
	return unlocked, maximum
end

function BaseState.GetStatus(base: Types.BaseRecord): Types.BaseStatus?
	if type(base) ~= "table" then
		return nil
	end
	local unlocked, maximum = BaseState.GetSlotLimits(base.buildSlotUpgrades)
	if not unlocked or not maximum then
		return nil
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
	local occupied: { [number]: boolean } = {}
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
		local definition = Shrines[shrine.shrineId]
		if not definition then
			return nil
		end
		local slot = shrine.buildSlotId
		local level = shrine.level
		if
			type(slot) ~= "number"
			or slot ~= slot
			or slot < 1
			or slot > unlocked
			or slot % 1 ~= 0
			or occupied[slot]
			or type(level) ~= "number"
			or level ~= level
			or level < definition.initialLevel
			or level > definition.maxLevel
			or level % 1 ~= 0
		then
			return nil
		end
		occupied[slot] = true
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

function BaseState.GetLowestFreeShrineSlot(base: Types.BaseRecord): (number?, string?)
	local status = BaseState.GetStatus(base)
	local shrines = if type(base) == "table" then base.shrines else nil
	if not status or not shrines then
		return nil, "InvalidBaseState"
	end
	local occupied: { [number]: boolean } = {}
	for _, shrine in shrines do
		occupied[shrine.buildSlotId] = true
	end
	for slot = 1, status.unlockedShrineSlots do
		if not occupied[slot] then
			return slot, nil
		end
	end
	return nil, "BaseFull"
end

return table.freeze(BaseState)
