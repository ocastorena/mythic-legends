--!strict
-- ServerScriptService/Services/BaseService/ShrineConstruction
-- Headless Shrine construction. World presentation and client transport are separate concerns.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseState = require(ServerScriptService.Domain.Base.BaseState)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)

local ShrineConstruction = {}

local OPERATION = "Base.BuildShrine"
local ALLOWED_REQUEST_FIELDS: { [string]: boolean } = {
	requestId = true,
	expectedRevision = true,
	shrineId = true,
	expectedGoldCost = true,
}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type ShrineConstruction = {
	Build: (Player, Types.BuildShrineRequest) -> Types.TransactionResult,
}

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function validId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
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

local function parseRequest(value: unknown): Types.BuildShrineRequest?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local fields = value :: { [any]: unknown }
	for key in fields do
		if type(key) ~= "string" or not ALLOWED_REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not validId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not validId(fields.shrineId)
		or not whole(fields.expectedGoldCost)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		shrineId = fields.shrineId :: string,
		expectedGoldCost = fields.expectedGoldCost :: number,
	}
end

local function reject(code: string, revision: number): Types.TransactionResult
	return { ok = false, code = code, revision = revision }
end

function ShrineConstruction.new(
	DataService: DataSource,
	makeId: (() -> string)?
): ShrineConstruction
	assert(type(DataService) == "table", "[BaseService.ShrineConstruction] DataService required")
	assert(
		type(DataService.GetLoadedData) == "function" and type(DataService.Transact) == "function",
		"[BaseService.ShrineConstruction] invalid DataService"
	)
	local generateId = makeId
		or function(): string
			return `shrine_{HttpService:GenerateGUID(false)}`
		end
	local api = {}

	function api.Build(
		player: Player,
		rawRequest: Types.BuildShrineRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return reject("DataUnavailable", 0)
		end
		local request = parseRequest(rawRequest)
		if not request then
			return reject("InvalidRequest", currentRevision(loaded))
		end

		local signature =
			`shrineId={#request.shrineId}:{request.shrineId};expectedGoldCost={request.expectedGoldCost}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = OPERATION,
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local definition = Shrines[request.shrineId]
			if not definition then
				return { ok = false, code = "InvalidShrine" }
			end
			local cost = definition.buildGoldCost
			local initialLevel = definition.initialLevel
			if
				not whole(cost)
				or cost <= 0
				or not whole(initialLevel)
				or initialLevel < 1
				or not whole(definition.maxLevel)
				or initialLevel > definition.maxLevel
			then
				return { ok = false, code = "InvalidShrine" }
			end
			if request.expectedGoldCost ~= cost then
				return { ok = false, code = "PriceChanged" }
			end

			local buildSlotId, slotCode = BaseState.GetLowestFreeShrineSlot(draft.base)
			if not buildSlotId then
				return { ok = false, code = slotCode or "InvalidBaseState" }
			end

			local currency: unknown = draft.currency
			if type(currency) ~= "table" then
				return { ok = false, code = "InvalidCurrency" }
			end
			local gold = (currency :: { [string]: unknown }).gold
			if not whole(gold) then
				return { ok = false, code = "InvalidCurrency" }
			end
			if (gold :: number) < cost then
				return { ok = false, code = "InsufficientGold" }
			end

			local shrines = draft.base.shrines
			local station = draft.base.craftingStation
			if type(shrines) ~= "table" or type(station) ~= "table" then
				return { ok = false, code = "InvalidBaseState" }
			end
			local instanceId = generateId()
			if
				not validId(instanceId)
				or shrines[instanceId] ~= nil
				or station.id == instanceId
			then
				return { ok = false, code = "InstanceIdConflict" }
			end

			shrines[instanceId] = {
				id = instanceId,
				shrineId = request.shrineId,
				buildSlotId = buildSlotId,
				level = initialLevel,
			}
			if not BaseState.GetStatus(draft.base) then
				return { ok = false, code = "InvalidBaseState" }
			end
			(currency :: { [string]: number }).gold = (gold :: number) - cost
			return {
				ok = true,
				values = {
					shrineInstanceId = instanceId,
					shrineId = request.shrineId,
					buildSlotId = buildSlotId,
					level = initialLevel,
					goldSpent = cost,
				},
			}
		end)
	end

	return api
end

return table.freeze(ShrineConstruction)
