--!strict
-- ServerScriptService/Services/DataService/ProfileSchema
-- Additive upgrades within the MVP namespace only; never reads the old prototype store.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseState = require(ServerScriptService.Domain.Base.BaseState)

local ProfileSchema = {}

-- The generator is server-owned and synchronous. Stage additions first so failed validation
-- leaves the loaded save untouched, including an interrupted first initialization.
function ProfileSchema.Prepare(
	data: Types.PlayerDoc,
	createStationId: () -> string
): (boolean, string?)
	if data.version ~= 4 and data.version ~= Configuration.schemaVersion then
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
	if not BaseState.GetStatus(candidate) then
		return false, "InvalidBase"
	end

	-- Retain table identities and every existing field, including legacy ledgers and job links.
	data.base.buildSlotUpgrades = candidate.buildSlotUpgrades
	data.base.shrines = candidate.shrines
	data.base.craftingStation = candidate.craftingStation
	data.version = Configuration.schemaVersion
	return true, nil
end

return table.freeze(ProfileSchema)
