--!strict
-- ServerScriptService/Services/BaseService/ShrineWorkers
-- Retry-safe assignment commands; ownership, accounting, and slots commit in one transaction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerTypes = require(ServerScriptService.Shared.Types)

local Types = require(ReplicatedStorage.Shared.Types)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAssignments = require(script.Parent.ShrineAssignments)

local ShrineWorkers = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type ShrineWorkers = {
	Assign: (Player, Types.AssignShrineWorkerRequest) -> Types.TransactionResult,
	Remove: (Player, Types.RemoveShrineWorkerRequest) -> Types.TransactionResult,
}

type Action = "Assign" | "Remove"
type Request = {
	requestId: string,
	expectedRevision: number,
	shrineInstanceId: string,
	slotId: number,
	workerId: string,
}

local COMMON_FIELDS =
	{ requestId = true, expectedRevision = true, shrineInstanceId = true, slotId = true }

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

local function parseRequest(value: unknown, action: Action): Request?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local fields = value :: { [string]: unknown }
	local workerField = if action == "Assign" then "workerId" else "expectedWorkerId"
	for key in fields do
		if type(key) ~= "string" or (not COMMON_FIELDS[key] and key ~= workerField) then
			return nil
		end
	end
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.shrineInstanceId)
		or not whole(fields.slotId)
		or (fields.slotId :: number) < 1
		or not isId(fields[workerField])
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		shrineInstanceId = fields.shrineInstanceId :: string,
		slotId = fields.slotId :: number,
		workerId = fields[workerField] :: string,
	}
end

function ShrineWorkers.new(
	DataService: DataSource,
	clock: (() -> number)?,
	checkAccess: ((Player, Types.PlayerDoc, string) -> string?)?
): ShrineWorkers
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[BaseService.ShrineWorkers] DataService.GetLoadedData and Transact required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	local function run(player: Player, rawRequest: unknown, action: Action): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest, action)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		-- Length-prefixed IDs make delimiter-containing selections unambiguous. Operation names
		-- separate Assign/Remove receipts; callers never supply either operation or signature.
		local signature =
			`shrine={#request.shrineInstanceId}:{request.shrineInstanceId};slot={request.slotId};worker={#request.workerId}:{request.workerId}`
		local operation = if action == "Assign"
			then "Base.AssignShrineWorker"
			else "Base.RemoveShrineWorker"
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = operation,
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local accessProblem = if checkAccess
				then checkAccess(player, draft, request.shrineInstanceId)
				else nil
			if accessProblem then
				return { ok = false, code = accessProblem }
			end
			local timestamp = now()
			local ok, problem = ShrineAccounting.ChangeAssignmentsToDraft(
				draft,
				timestamp,
				function(state, time, metadata, production, progression)
					if action == "Assign" then
						return ShrineAssignments.Assign(state, time, {
							workerId = request.workerId,
							shrineInstanceId = request.shrineInstanceId,
							slotId = request.slotId,
						}, metadata, production, progression)
					end
					return ShrineAssignments.Remove(state, time, {
						shrineInstanceId = request.shrineInstanceId,
						slotId = request.slotId,
						expectedWorkerId = request.workerId,
					}, metadata, production, progression)
				end
			)
			return {
				ok = ok,
				code = problem,
				values = if ok
					then {
						shrineInstanceId = request.shrineInstanceId,
						slotId = request.slotId,
						workerId = request.workerId,
						settledAt = timestamp,
					}
					else nil,
			}
		end)
	end

	function api.Assign(
		player: Player,
		request: Types.AssignShrineWorkerRequest
	): Types.TransactionResult
		return run(player, request, "Assign")
	end

	function api.Remove(
		player: Player,
		request: Types.RemoveShrineWorkerRequest
	): Types.TransactionResult
		return run(player, request, "Remove")
	end

	return api
end

return table.freeze(ShrineWorkers)
