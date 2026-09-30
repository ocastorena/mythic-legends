--!strict
-- ServerScriptService/Services/BaseService/ShrineRemoval
-- Retry-safe empty-Shrine dismantling; slot release and retained work commit together.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerTypes = require(ServerScriptService.Shared.Types)

local Types = require(ReplicatedStorage.Shared.Types)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineDismantling = require(script.Parent.ShrineDismantling)

local ShrineRemoval = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type ShrineRemoval = {
	Dismantle: (Player, Types.DismantleShrineRequest) -> Types.TransactionResult,
}

local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	shrineInstanceId = true,
	expectedLevel = true,
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

local function parseRequest(value: unknown): Types.DismantleShrineRequest?
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
		or not whole(fields.expectedLevel)
		or (fields.expectedLevel :: number) < 1
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		shrineInstanceId = fields.shrineInstanceId :: string,
		expectedLevel = fields.expectedLevel :: number,
	}
end

function ShrineRemoval.new(
	DataService: DataSource,
	clock: (() -> number)?,
	checkAccess: ((Player, Types.PlayerDoc, string) -> string?)?
): ShrineRemoval
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[BaseService.ShrineRemoval] DataService.GetLoadedData and Transact required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.Dismantle(
		player: Player,
		rawRequest: Types.DismantleShrineRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local level = string.format("%.0f", request.expectedLevel)
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Base.DismantleShrine",
			signature = `shrine={#request.shrineInstanceId}:{request.shrineInstanceId};level={level}`,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local accessProblem = if checkAccess
				then checkAccess(player, draft, request.shrineInstanceId)
				else nil
			if accessProblem then
				return { ok = false, code = accessProblem }
			end
			local timestamp = now()
			local removed: ShrineDismantling.Result? = nil
			local ok, problem = ShrineAccounting.RemoveShrineToDraft(
				draft,
				timestamp,
				request.shrineInstanceId,
				function(state, time, metadata, production, progression)
					local result, removalError =
						ShrineDismantling.Dismantle(state, draft.base, time, {
							shrineInstanceId = request.shrineInstanceId,
							expectedLevel = request.expectedLevel,
						}, metadata, production, progression)
					removed = result
					return if result then result.production else nil, removalError
				end
			)
			local result = removed
			if not ok or not result then
				return { ok = false, code = problem or "DismantleFailed" }
			end
			-- The bridge removes the canonical record and writes surviving accounting together.
			-- Do not replace its settled records with the reducer's separate ownership-only view.
			return {
				ok = true,
				values = {
					shrineInstanceId = result.shrineInstanceId,
					shrineId = result.shrineId,
					buildSlotId = result.buildSlotId,
					level = result.level,
					settledAt = timestamp,
				},
			}
		end)
	end

	return api
end

return table.freeze(ShrineRemoval)
