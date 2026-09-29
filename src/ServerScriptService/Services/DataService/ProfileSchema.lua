--!strict
-- ServerScriptService/Services/DataService/ProfileSchema
-- Additive upgrades within the MVP namespace only; never reads the old prototype store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseState = require(ServerScriptService.Shared.BaseState)

local ProfileSchema = {}

local LEGACY_SCHEMA_VERSIONS = { [4] = true, [5] = true }

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

-- The generator is server-owned and synchronous. Stage additions first so failed validation
-- leaves the loaded save untouched, including an interrupted first initialization.
function ProfileSchema.Prepare(
	data: Types.PlayerDoc,
	createStationId: () -> string
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
	local candidate = table.clone(data.base)
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
		stageShrines(candidate.shrines, unlockedSlots, isLegacyVersion)
	if not stagedShrines or not originalShrines then
		return false, "InvalidBase"
	end
	candidate.shrines = stagedShrines
	if not BaseState.GetStatus(candidate) then
		return false, "InvalidBase"
	end

	-- Retain table identities and every existing field, including legacy ledgers and job links.
	for id, stagedShrine in stagedShrines do
		local original = originalShrines[id]
		original.buildSlotId = stagedShrine.buildSlotId
		original.level = stagedShrine.level
	end
	data.base.buildSlotUpgrades = candidate.buildSlotUpgrades
	data.base.shrines = retainedShrines
	data.base.craftingStation = candidate.craftingStation
	data.version = Configuration.schemaVersion
	return true, nil
end

return table.freeze(ProfileSchema)
