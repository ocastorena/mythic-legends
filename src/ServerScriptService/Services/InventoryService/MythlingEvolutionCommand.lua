--!strict
-- ServerScriptService/Services/InventoryService/MythlingEvolutionCommand
-- Retry-safe manual evolution: settle old-form work and change form in one profile transaction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local MythlingEvolution = require(script.Parent.MythlingEvolution)

local MythlingEvolutionCommand = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type MythlingEvolutionCommand = {
	Evolve: (Player, Types.EvolveMythlingRequest) -> Types.TransactionResult,
}

local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	workerId = true,
	expectedFormId = true,
	expectedTargetFormId = true,
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

local function parseRequest(value: unknown): Types.EvolveMythlingRequest?
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
		or not isId(fields.workerId)
		or not isId(fields.expectedFormId)
		or not isId(fields.expectedTargetFormId)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		workerId = fields.workerId :: string,
		expectedFormId = fields.expectedFormId :: string,
		expectedTargetFormId = fields.expectedTargetFormId :: string,
	}
end

local function evolutionMetadata(metadata: ShrineAccrual.Metadata): MythlingEvolution.Metadata?
	local definitions: MythlingEvolution.Metadata = { forms = {}, shrines = metadata.shrines }
	for id, definition in metadata.forms do
		local canonical = MythlingForms[id]
		if not canonical then
			return nil
		end
		-- Preserve accounting's definitions; only Inventory's evolution policy needs links.
		definitions.forms[id] = {
			element = definition.element,
			baseYieldPerHour = definition.baseYieldPerHour,
			evolution = canonical.evolution,
		}
	end
	return definitions
end

function MythlingEvolutionCommand.new(
	DataService: DataSource,
	clock: (() -> number)?
): MythlingEvolutionCommand
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[InventoryService.MythlingEvolutionCommand] DataService.GetLoadedData and Transact required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.Evolve(
		player: Player,
		rawRequest: Types.EvolveMythlingRequest
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
			`worker={#request.workerId}:{request.workerId};form={#request.expectedFormId}:{request.expectedFormId};target={#request.expectedTargetFormId}:{request.expectedTargetFormId}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Inventory.EvolveMythling",
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local timestamp = now()
			local evolved: ShrineAccrual.Worker? = nil
			local ok, problem = ShrineAccounting.ChangeWorkerFormToDraft(
				draft,
				timestamp,
				request.workerId,
				request.expectedTargetFormId,
				function(state, time, metadata, production, progression)
					local definitions = evolutionMetadata(metadata)
					if not definitions then
						return nil, "InvalidEvolutionDefinition"
					end
					local result, evolutionError = MythlingEvolution.Evolve(state, time, {
						workerId = request.workerId,
						expectedFormId = request.expectedFormId,
						expectedTargetFormId = request.expectedTargetFormId,
					}, definitions, production, progression)
					if result then
						evolved = result.workers[request.workerId]
					end
					return result, evolutionError
				end
			)
			local worker = evolved
			if not ok or not worker then
				return { ok = false, code = problem or "EvolutionFailed" }
			end
			-- The adapter merges the form and earned fields together, preserving the owned
			-- record's identity and unrelated metadata. No separate settlement or grant follows.
			return {
				ok = true,
				values = {
					workerId = request.workerId,
					previousFormId = request.expectedFormId,
					formId = worker.formId,
					level = worker.level,
					xp = worker.xp,
					settledAt = timestamp,
				},
			}
		end)
	end

	return api
end

return table.freeze(MythlingEvolutionCommand)
