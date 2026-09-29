--!strict
-- ServerScriptService/Services/ProductionService/ShrineCollector
-- Retry-safe collection: settle, debit Shrine storage, and grant Inventory Materials atomically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineCollection = require(script.Parent.ShrineCollection)

local ShrineCollector = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type ShrineCollector = {
	Collect: (Player, Types.CollectShrineRequest) -> Types.TransactionResult,
}

local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	shrineInstanceId = true,
	expectedMaterialId = true,
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

local function parseRequest(value: unknown): Types.CollectShrineRequest?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local fields = value :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.shrineInstanceId)
		or not isId(fields.expectedMaterialId)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		shrineInstanceId = fields.shrineInstanceId :: string,
		expectedMaterialId = fields.expectedMaterialId :: string,
	}
end

function ShrineCollector.new(DataService: DataSource, clock: (() -> number)?): ShrineCollector
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[ProductionService.ShrineCollector] DataService.GetLoadedData and Transact required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.Collect(
		player: Player,
		rawRequest: Types.CollectShrineRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local signature =
			`shrine={#request.shrineInstanceId}:{request.shrineInstanceId};material={#request.expectedMaterialId}:{request.expectedMaterialId}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Production.CollectShrine",
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			-- Both views come from this transaction, not a prior read or caller-submitted ledger.
			local timestamp = now()
			local collected: ShrineCollection.Result? = nil
			local ok, problem = ShrineAccounting.ChangeStorageToDraft(
				draft,
				timestamp,
				function(state, time, metadata, production, progression)
					local result, collectionError = ShrineCollection.Collect(
						state,
						{
							materials = draft.materials,
							inventoryUpgrades = draft.inventoryUpgrades,
							craftingJobs = draft.craftingJobs,
						},
						time,
						{
							shrineInstanceId = request.shrineInstanceId,
							expectedMaterialId = request.expectedMaterialId,
						},
						metadata,
						production,
						progression
					)
					collected = result
					return if result then result.production else nil, collectionError
				end
			)
			local result = collected
			if not ok or not result then
				return { ok = false, code = problem or "CollectionFailed" }
			end
			-- The shared bridge has accepted the matching debit/accounting. No separate grant or
			-- save call may escape this draft; DataService commits all fields and the receipt.
			draft.materials = result.materials
			return {
				ok = true,
				values = {
					shrineInstanceId = result.shrineInstanceId,
					materialId = result.materialId,
					collected = result.collected,
					remaining = result.remaining,
					settledAt = timestamp,
				},
			}
		end)
	end

	return api
end

return table.freeze(ShrineCollector)
