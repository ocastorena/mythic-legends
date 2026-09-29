--!strict
-- ServerScriptService/Services/DataService/ProfileSchema
-- Additive upgrades within the MVP namespace only; never reads the old prototype store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseState = require(ServerScriptService.Shared.BaseState)

local ProfileSchema = {}

local LEGACY_SCHEMA_VERSIONS = { [4] = true, [5] = true, [6] = true }
local LEGACY_BASE_VERSIONS = { [4] = true, [5] = true }

type LegacyShrineRecord = {
	id: string,
	shrineId: string,
	buildSlotId: number?,
	level: number?,
}

local function stageShrines(
	shrines: unknown,
	unlockedSlots: number,
	isLegacyVersion: boolean
): ({ [string]: Types.ShrineRecord }?, { [string]: LegacyShrineRecord }?)
	if type(shrines) ~= "table" then
		return nil, nil
	end

	local staged: { [string]: Types.ShrineRecord } = {}
	local originals: { [string]: LegacyShrineRecord } = {}
	local missingSlots: { string } = {}
	local occupiedSlots: { [number]: boolean } = {}

	for rawId, rawShrine in shrines do
		if type(rawId) ~= "string" or type(rawShrine) ~= "table" then
			return nil, nil
		end
		local id = rawId
		local original = rawShrine :: LegacyShrineRecord
		local candidate = table.clone(original) :: LegacyShrineRecord
		originals[id] = original

		if candidate.level == nil and isLegacyVersion then
			if type(candidate.shrineId) ~= "string" then
				return nil, nil
			end
			local definition = Shrines[candidate.shrineId]
			if not definition then
				return nil, nil
			end
			candidate.level = definition.initialLevel
		end

		local buildSlotId = candidate.buildSlotId
		if buildSlotId == nil and isLegacyVersion then
			table.insert(missingSlots, id)
		elseif
			type(buildSlotId) ~= "number"
			or buildSlotId ~= buildSlotId
			or buildSlotId % 1 ~= 0
			or buildSlotId < 1
			or buildSlotId > unlockedSlots
			or occupiedSlots[buildSlotId]
		then
			return nil, nil
		else
			occupiedSlots[buildSlotId] = true
		end

		staged[id] = candidate :: Types.ShrineRecord
	end

	table.sort(missingSlots)
	for _, id in missingSlots do
		local buildSlotId: number? = nil
		for slotId = 1, unlockedSlots do
			if not occupiedSlots[slotId] then
				buildSlotId = slotId
				break
			end
		end
		if buildSlotId == nil then
			return nil, nil
		end
		local candidate = staged[id] :: LegacyShrineRecord
		candidate.buildSlotId = buildSlotId
		occupiedSlots[buildSlotId] = true
	end

	return staged, originals
end

local function nonnegative(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 53
end

-- Default only an entirely absent legacy ledger. Partial state cannot be safely interpreted.
-- This validates ownership/slot structure, not unresolved launch-form elements or Yield.
local function stageProduction(
	shrines: { [string]: Types.ShrineRecord },
	mythlings: { [string]: Types.MythlingEntry },
	allowDefaults: boolean
): (boolean, boolean)
	if type(mythlings) ~= "table" then
		return false, false
	end
	local hadAccounting = false
	local assigned: { [string]: boolean } = {}
	for _, shrine in shrines do
		local allMissing = shrine.stored == nil
			and shrine.progress == nil
			and shrine.newWork == nil
			and shrine.workerIdsBySlot == nil
		if allMissing then
			if not allowDefaults then
				return false, false
			end
			shrine.stored = 0
			shrine.progress = 0
			shrine.newWork = 0
			shrine.workerIdsBySlot = {}
		else
			hadAccounting = true
		end
		local stored, progress, newWork = shrine.stored, shrine.progress, shrine.newWork
		if
			not nonnegative(stored)
			or (stored :: number) % 1 ~= 0
			or not nonnegative(progress)
			or (progress :: number) >= 1
			or not nonnegative(newWork)
			or type(shrine.workerIdsBySlot) ~= "table"
		then
			return false, false
		end
		-- Retain above-capacity stored work after tuning changes; migration never discards earnings.
		local levels = Shrines[shrine.shrineId].levels
		if type(levels) ~= "table" then
			return false, false
		end
		local levelDefinition = levels[shrine.level]
		if
			type(levelDefinition) ~= "table"
			or not nonnegative(levelDefinition.workerSlots)
			or levelDefinition.workerSlots < 1
			or levelDefinition.workerSlots % 1 ~= 0
		then
			return false, false
		end
		for slotKey, workerId in shrine.workerIdsBySlot do
			if type(slotKey) ~= "string" or type(workerId) ~= "string" then
				return false, false
			end
			local slot = tonumber(slotKey)
			if
				not slot
				or not nonnegative(slot)
				or slot % 1 ~= 0
				or slot < 1
				or slot > levelDefinition.workerSlots
				or tostring(slot) ~= slotKey
				or #workerId == 0
				or #workerId > 128
			then
				return false, false
			end
			local worker = mythlings[workerId]
			if type(worker) ~= "table" or assigned[workerId] or worker.standId ~= nil then
				return false, false
			end
			assigned[workerId] = true
		end
	end
	return true, hadAccounting
end

local function stageClock(
	clock: Types.ProductionClock?,
	allowInitialization: boolean,
	hadAccounting: boolean,
	now: number
): (Types.ProductionClock?, string?)
	local interval = Production.batchIntervalSeconds
	if not nonnegative(interval) or interval <= 0 then
		return nil, "InvalidProductionConfiguration"
	end
	if clock == nil then
		if not allowInitialization or hadAccounting then
			return nil, "MissingProductionClock"
		end
		local nextBatchAt = now + interval
		if not nonnegative(nextBatchAt) or nextBatchAt <= now then
			return nil, "InvalidProductionTime"
		end
		return { lastAccruedAt = now, nextBatchAt = nextBatchAt }, nil
	end
	if
		type(clock) ~= "table"
		or not nonnegative(clock.lastAccruedAt)
		or not nonnegative(clock.nextBatchAt)
		or clock.nextBatchAt <= clock.lastAccruedAt
		or clock.nextBatchAt > clock.lastAccruedAt + interval
	then
		return nil, "InvalidProductionClock"
	end
	return clock, nil
end

-- The generator is server-owned and synchronous. Stage additions first so failed validation
-- leaves the loaded save untouched, including an interrupted first initialization.
function ProfileSchema.Prepare(
	data: Types.PlayerDoc,
	createStationId: () -> string,
	now: number?
): (boolean, string?)
	local isLegacyVersion = LEGACY_SCHEMA_VERSIONS[data.version] == true
	if not isLegacyVersion and data.version ~= Configuration.schemaVersion then
		return false, "UnsupportedVersion"
	end
	if type(data.profile) ~= "table" then
		return false, "InvalidProfile"
	end
	if type(data.base) ~= "table" or type(data.base.stands) ~= "table" then
		return false, "InvalidBase"
	end
	local timestamp = if now == nil then os.time() else now
	if not nonnegative(timestamp) then
		return false, "InvalidProductionTime"
	end
	local candidate = table.clone(data.base)
	local isFresh = data.profile.userId == 0
		and data.profile.createdAt == 0
		and candidate.craftingStation == nil
		and type(candidate.shrines) == "table"
		and next(candidate.shrines) == nil
	if data.version == 4 then
		if candidate.buildSlotUpgrades == nil then
			candidate.buildSlotUpgrades = 0
		end
		if candidate.shrines == nil then
			candidate.shrines = {}
		end
	end
	if candidate.craftingStation == nil then
		-- These template sentinels are replaced only after preparation succeeds. Unlike the
		-- session counter, they survive a crash between creating the save and initializing it.
		local isUninitialized = data.profile.userId == 0 and data.profile.createdAt == 0
		if data.version ~= 4 and not isUninitialized then
			return false, "MissingStation"
		end
		local ok, id = pcall(createStationId)
		if not ok then
			return false, "StationIdentityFailed"
		end
		candidate.craftingStation = { id = id, craftingStationId = Bases.craftingStationId }
	end

	local unlockedSlots = BaseState.GetSlotLimits(candidate.buildSlotUpgrades)
	if unlockedSlots == nil then
		return false, "InvalidBase"
	end
	local retainedShrines = candidate.shrines
	local stagedShrines, originalShrines =
		stageShrines(candidate.shrines, unlockedSlots, LEGACY_BASE_VERSIONS[data.version] == true)
	if not stagedShrines or not originalShrines then
		return false, "InvalidBase"
	end
	candidate.shrines = stagedShrines
	if not BaseState.GetStatus(candidate) then
		return false, "InvalidBase"
	end
	local productionValid, hadAccounting =
		stageProduction(stagedShrines, data.mythlings, isLegacyVersion)
	if not productionValid then
		return false, "InvalidShrineProduction"
	end
	local clock, clockError =
		stageClock(data.productionClock, isLegacyVersion or isFresh, hadAccounting, timestamp)
	if not clock then
		return false, clockError
	end

	-- Retain table identities and every existing field, including legacy ledgers and job links.
	for id, stagedShrine in stagedShrines do
		local original = originalShrines[id]
		original.buildSlotId = stagedShrine.buildSlotId
		original.level = stagedShrine.level
		local record = original :: Types.ShrineRecord
		record.stored = stagedShrine.stored
		record.progress = stagedShrine.progress
		record.newWork = stagedShrine.newWork
		record.workerIdsBySlot = stagedShrine.workerIdsBySlot
	end
	data.base.buildSlotUpgrades = candidate.buildSlotUpgrades
	data.base.shrines = retainedShrines
	data.base.craftingStation = candidate.craftingStation
	data.productionClock = clock
	data.version = Configuration.schemaVersion
	return true, nil
end

return table.freeze(ProfileSchema)
