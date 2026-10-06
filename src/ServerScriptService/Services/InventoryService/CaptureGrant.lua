--!strict
-- ServerScriptService/Services/InventoryService/CaptureGrant
-- Grants an authenticated server capture without changing the caught form or earned older records.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerTypes = require(ServerScriptService.Shared.Types)

local Types = require(ReplicatedStorage.Shared.Types)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local PrototypeMythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)

export type Params = { typeId: string, variantId: string, legacyPrototype: boolean? }
export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Update: (Player, string, ServerTypes.ProfileMutation) -> Types.TransactionResult,
}
export type CaptureGrant = {
	Grant: (Player, Params) -> Types.TransactionResult,
}

local CaptureGrant = {}
local REQUEST_FIELDS = { typeId = true, variantId = true, legacyPrototype = true }

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 53
end

local function isWhole(value: unknown): boolean
	return isNumber(value) and (value :: number) % 1 == 0
end

local function isPlain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if type(state) == "table" then
		local revision = (state :: { [string]: unknown }).revision
		if isWhole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function parseParams(value: unknown): Params?
	if not isPlain(value) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if not isId(fields.typeId) or not isId(fields.variantId) then
		return nil
	end
	if fields.legacyPrototype ~= nil and type(fields.legacyPrototype) ~= "boolean" then
		return nil
	end
	return {
		typeId = fields.typeId :: string,
		variantId = fields.variantId :: string,
		legacyPrototype = fields.legacyPrototype :: boolean?,
	}
end

local function validateInventory(data: Types.PlayerDoc): string?
	if data.version ~= PlayerData.schemaVersion then
		return "UnsupportedVersion"
	end
	if not isPlain(data.mythlings) then
		return "InvalidInventoryState"
	end
	for id, entry in data.mythlings do
		if not isId(id) or not isPlain(entry) or not isId(entry.typeId) then
			return "InvalidInventoryState"
		end
	end
	local upgrades = data.inventoryUpgrades
	if upgrades ~= nil then
		if not isPlain(upgrades) then
			return "InvalidInventoryUpgrade"
		end
		local level = upgrades.mythlings
		if
			level ~= nil
			and (not isWhole(level) or level > #Inventory.capacityByCategory.mythlings - 1)
		then
			return "InvalidInventoryUpgrade"
		end
	end
	return nil
end

local function validateDefinition(params: Params): string?
	-- Only the authenticated active-pool wrapper marks retained stand production.
	-- A direct canonical grant keeps its Shrine/progression semantics even for the same ID.
	local prototype = PrototypeMythlings[params.typeId]
	if params.legacyPrototype == true then
		if not prototype then
			return "InvalidMythling"
		end
		return if prototype.variants[params.variantId] then nil else "InvalidVariant"
	end
	if MythlingForms[params.typeId] then
		return if params.variantId == "regular" then nil else "InvalidVariant"
	end
	if not prototype then
		return "InvalidMythling"
	end
	return if prototype.variants[params.variantId] then nil else "InvalidVariant"
end

function CaptureGrant.new(
	DataService: DataSource,
	clock: (() -> number)?,
	createId: (() -> string)?
): CaptureGrant
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Update) == "function",
		"[InventoryService.CaptureGrant] DataService.GetLoadedData and Update required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local generateId = createId
		or function(): string
			return `myth_{HttpService:GenerateGUID(false)}`
		end
	local api = {}

	function api.Grant(player: Player, rawParams: Params): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local params = parseParams(rawParams)
		if not params then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		-- ClaimService owns non-yielding winner eligibility and duplicate-event suppression.
		-- This is a server-authored transition, not a retryable client acquisition endpoint.
		return DataService.Update(player, "CaptureMythling", function(draft)
			local inventoryError = validateInventory(draft)
			if inventoryError then
				return { ok = false, code = inventoryError }
			end
			local definitionError = validateDefinition(params)
			if definitionError then
				return { ok = false, code = definitionError }
			end
			local capacity = InventoryCapacity.GetUsage(draft, "mythlings")
			if capacity.used >= capacity.limit then
				return { ok = false, code = "InventoryFull" }
			end
			local timestamp = now()
			if not isNumber(timestamp) then
				return { ok = false, code = "InvalidTimestamp" }
			end
			local instanceId = generateId()
			if not isId(instanceId) or draft.mythlings[instanceId] ~= nil then
				return { ok = false, code = "InstanceIdConflict" }
			end
			-- A new unassigned worker changes no earlier production input. Ready settlement
			-- preceded profile exposure, and every pre-existing worker keeps its earned state.
			draft.mythlings[instanceId] = {
				typeId = params.typeId,
				variantId = params.variantId,
				claimedAt = timestamp,
				legacyPrototype = params.legacyPrototype,
				level = 1,
				xp = 0,
				pendingXp = 0,
			}
			return { ok = true, values = { instanceId = instanceId } }
		end)
	end

	return api
end

return table.freeze(CaptureGrant)
