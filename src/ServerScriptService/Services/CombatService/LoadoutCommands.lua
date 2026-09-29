--!strict
-- ServerScriptService/Services/CombatService/LoadoutCommands
-- Change only saved equipped references; runtime combat reconciliation follows a confirmed commit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type Resolver = (unknown, unknown?) -> Types.ResolvedEquipment?
export type LoadoutCommands = {
	Equip: (Player, Types.EquipEquipmentRequest) -> Types.TransactionResult,
	Unequip: (Player, Types.UnequipEquipmentRequest) -> Types.TransactionResult,
}
type Slot = "PrimaryWeapon" | "Shield"

local LoadoutCommands = {}
local EQUIP_FIELDS = {
	requestId = true,
	expectedRevision = true,
	instanceId = true,
	expectedDefinitionId = true,
	expectedFinishId = true,
}
local UNEQUIP_FIELDS = {
	requestId = true,
	expectedRevision = true,
	slot = true,
	expectedInstanceId = true,
}

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isPlain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function closed(value: unknown, fields: { [string]: boolean }): boolean
	if not isPlain(value) then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if type(key) ~= "string" or not fields[key] then
			return false
		end
	end
	return true
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if type(state) == "table" then
		local revision = (state :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function parseEquip(value: unknown): Types.EquipEquipmentRequest?
	if not closed(value, EQUIP_FIELDS) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.instanceId)
		or not isId(fields.expectedDefinitionId)
		or (fields.expectedFinishId ~= nil and not isId(fields.expectedFinishId))
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		instanceId = fields.instanceId :: string,
		expectedDefinitionId = fields.expectedDefinitionId :: string,
		expectedFinishId = fields.expectedFinishId :: string?,
	}
end

local function parseUnequip(value: unknown): Types.UnequipEquipmentRequest?
	if not closed(value, UNEQUIP_FIELDS) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or (fields.slot ~= "PrimaryWeapon" and fields.slot ~= "Shield")
		or not isId(fields.expectedInstanceId)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		slot = fields.slot :: Slot,
		expectedInstanceId = fields.expectedInstanceId :: string,
	}
end

local function validateState(draft: Types.PlayerDoc): string?
	if draft.version ~= PlayerData.schemaVersion then
		return "UnsupportedVersion"
	end
	if not isPlain(draft.equipment) then
		return "InvalidInventoryState"
	end
	local loadout = draft.combatLoadout
	if
		not isPlain(loadout)
		or (loadout.primaryWeaponInstanceId ~= nil and not isId(loadout.primaryWeaponInstanceId))
		or (loadout.shieldInstanceId ~= nil and not isId(loadout.shieldInstanceId))
	then
		return "InvalidLoadoutState"
	end
	return nil
end

local function validEntry(value: unknown): boolean
	if not isPlain(value) then
		return false
	end
	local entry = value :: { [string]: unknown }
	return isId(entry.definitionId)
		and (entry.finishId == nil or isId(entry.finishId))
		and (entry.isStarterGrant == nil or type(entry.isStarterGrant) == "boolean")
end

local function validMetadata(resolved: Types.ResolvedEquipment?): boolean
	if not resolved or not isPlain(resolved) or not isPlain(resolved.profile) then
		return false
	end
	local profile = resolved.profile
	if profile.kind == "PrimaryWeapon" then
		return profile.handsRequired == 1 or profile.handsRequired == 2
	end
	return profile.kind == "Shield" and profile.handsRequired == nil
end

local function idPart(value: string): string
	return `{#value}:{value}`
end

function LoadoutCommands.new(DataService: DataSource, resolver: Resolver?): LoadoutCommands
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[CombatService.LoadoutCommands] DataService.GetLoadedData and Transact required"
	)
	assert(
		resolver == nil or type(resolver) == "function",
		"[CombatService.LoadoutCommands] Resolver must be a function"
	)
	local resolve = resolver or EquipmentCatalog.Resolve
	local api = {}

	local function resolveEntry(entry: Types.EquipmentEntry): Types.ResolvedEquipment?
		local result = resolve(entry.definitionId, entry.finishId)
		if
			not validMetadata(result)
			or not result
			or result.definitionId ~= entry.definitionId
			or result.finishId ~= entry.finishId
		then
			return nil
		end
		return result
	end

	function api.Equip(
		player: Player,
		rawRequest: Types.EquipEquipmentRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseEquip(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local finish = if request.expectedFinishId then idPart(request.expectedFinishId) else "none"
		local signature = `instance={idPart(request.instanceId)};definition={idPart(
			request.expectedDefinitionId
		)};finish={finish}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Combat.EquipEquipment",
			signature = signature,
		}, function(draft: Types.PlayerDoc, _now: number): Types.TransactionOutcome
			local problem = validateState(draft)
			if problem then
				return { ok = false, code = problem }
			end
			local entry = draft.equipment[request.instanceId]
			if entry == nil then
				return { ok = false, code = "NotOwned" }
			end
			if not validEntry(entry) then
				return { ok = false, code = "InvalidInventoryState" }
			end
			if
				entry.definitionId ~= request.expectedDefinitionId
				or entry.finishId ~= request.expectedFinishId
			then
				return { ok = false, code = "EquipmentChanged" }
			end
			local resolved = resolveEntry(entry)
			if not resolved then
				return { ok = false, code = "NotEquippable" }
			end
			local slot = resolved.profile.kind
			local loadout = draft.combatLoadout
			if slot == "Shield" and loadout.primaryWeaponInstanceId ~= nil then
				local primary = draft.equipment[loadout.primaryWeaponInstanceId]
				if not primary or not validEntry(primary) then
					return { ok = false, code = "InvalidLoadoutState" }
				end
				local equipped = resolveEntry(primary)
				if not equipped or equipped.profile.kind ~= "PrimaryWeapon" then
					return { ok = false, code = "InvalidLoadoutState" }
				end
				if equipped.profile.handsRequired == 2 then
					return { ok = false, code = "ShieldIncompatible" }
				end
			end
			-- Re-equipping the same primary still enforces compatibility. A cleared Shield remains
			-- owned and consumes capacity; no restoration reference or runtime state is recorded.
			local shieldUnequipped = slot == "PrimaryWeapon"
				and resolved.profile.handsRequired == 2
				and loadout.shieldInstanceId ~= nil
			local previous = if slot == "PrimaryWeapon"
				then loadout.primaryWeaponInstanceId
				else loadout.shieldInstanceId
			local changed = previous ~= request.instanceId or shieldUnequipped
			if slot == "PrimaryWeapon" then
				loadout.primaryWeaponInstanceId = request.instanceId
			else
				loadout.shieldInstanceId = request.instanceId
			end
			if shieldUnequipped then
				loadout.shieldInstanceId = nil
			end
			local values: Types.TransactionValues = {
				instanceId = request.instanceId,
				definitionId = entry.definitionId,
				slot = slot,
				changed = changed,
				shieldUnequipped = shieldUnequipped,
			}
			if entry.finishId ~= nil then
				values.finishId = entry.finishId
			end
			return { ok = true, values = values }
		end)
	end

	function api.Unequip(
		player: Player,
		rawRequest: Types.UnequipEquipmentRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseUnequip(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Combat.UnequipEquipment",
			signature = `slot={idPart(request.slot)};instance={idPart(request.expectedInstanceId)}`,
		}, function(draft: Types.PlayerDoc, _now: number): Types.TransactionOutcome
			local problem = validateState(draft)
			if problem then
				return { ok = false, code = problem }
			end
			local loadout = draft.combatLoadout
			local previous = if request.slot == "PrimaryWeapon"
				then loadout.primaryWeaponInstanceId
				else loadout.shieldInstanceId
			if previous ~= request.expectedInstanceId then
				return { ok = false, code = "SlotChanged" }
			end
			-- Do not resolve the former occupant: explicit removal must recover dangling or
			-- unsupported saved references without deleting or reinterpreting retained ownership.
			if request.slot == "PrimaryWeapon" then
				loadout.primaryWeaponInstanceId = nil
			else
				loadout.shieldInstanceId = nil
			end
			return {
				ok = true,
				values = {
					instanceId = request.expectedInstanceId,
					slot = request.slot,
					changed = true,
				},
			}
		end)
	end

	return api
end

return table.freeze(LoadoutCommands)
