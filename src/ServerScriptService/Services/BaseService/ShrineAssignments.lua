--!strict
-- ServerScriptService/Services/BaseService/ShrineAssignments
-- Pure per-profile assignment commands. Live ownership resolution and commit belong to the adapter.

local ServerScriptService = game:GetService("ServerScriptService")

local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

export type State = ShrineAccrual.State
export type Metadata = ShrineAccrual.Metadata
export type AssignRequest = { workerId: string, shrineInstanceId: string, slotId: number }
export type RemoveRequest = {
	shrineInstanceId: string,
	slotId: number,
	expectedWorkerId: string,
}

local ASSIGN_FIELDS = { workerId = true, shrineInstanceId = true, slotId = true }
local REMOVE_FIELDS = { shrineInstanceId = true, slotId = true, expectedWorkerId = true }
local ShrineAssignments = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isSlot(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 1
		and value < 2 ^ 53
		and value % 1 == 0
end

local function hasOnlyFields(request: unknown, fields: { [string]: boolean }): boolean
	if type(request) ~= "table" or getmetatable(request) ~= nil then
		return false
	end
	for key in request do
		if type(key) ~= "string" or not fields[key] then
			return false
		end
	end
	return true
end

local function parseAssign(request: unknown): AssignRequest?
	if not hasOnlyFields(request, ASSIGN_FIELDS) then
		return nil
	end
	-- Dynamic reads are confined to the request boundary; the returned record is validated.
	local fields = request :: { [string]: unknown }
	if
		not isId(fields.workerId)
		or not isId(fields.shrineInstanceId)
		or not isSlot(fields.slotId)
	then
		return nil
	end
	return {
		workerId = fields.workerId :: string,
		shrineInstanceId = fields.shrineInstanceId :: string,
		slotId = fields.slotId :: number,
	}
end

local function parseRemove(request: unknown): RemoveRequest?
	if not hasOnlyFields(request, REMOVE_FIELDS) then
		return nil
	end
	local fields = request :: { [string]: unknown }
	if
		not isId(fields.expectedWorkerId)
		or not isId(fields.shrineInstanceId)
		or not isSlot(fields.slotId)
	then
		return nil
	end
	return {
		shrineInstanceId = fields.shrineInstanceId :: string,
		slotId = fields.slotId :: number,
		expectedWorkerId = fields.expectedWorkerId :: string,
	}
end

local function validateChange(
	state: State,
	now: number,
	metadata: Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): string?
	local problem = ShrineAccrual.Validate(state, now, metadata, production, progression)
	if problem then
		return problem
	end
	-- Accrual can ignore an old clock read, but roster changes cannot be applied retrospectively.
	if now < state.lastAccruedAt then
		return "BackdatedChange"
	end
	return nil
end

local function validateDestination(
	state: State,
	shrineInstanceId: string,
	slotId: number,
	metadata: Metadata
): string?
	local shrine = state.shrines[shrineInstanceId]
	if not shrine then
		return "ShrineNotOwned"
	end
	local level = metadata.shrines[shrine.shrineId].levels[shrine.level]
	if slotId > level.workerSlots then
		return "InvalidSlot"
	end
	return nil
end

-- State must contain ONLY the authenticated player's owned Shrines/workers. These pure functions
-- never authenticate a Player or accept ownership from a client. A future service must build that
-- view from its loaded profile and commit all returned accounting/slot changes in one transaction.
function ShrineAssignments.Assign(
	state: State,
	now: number,
	rawRequest: AssignRequest,
	metadata: Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (State?, string?)
	local request = parseAssign(rawRequest)
	if not request then
		return nil, "InvalidRequest"
	end
	local problem = validateChange(state, now, metadata, production, progression)
	if problem then
		return nil, problem
	end
	problem = validateDestination(state, request.shrineInstanceId, request.slotId, metadata)
	if problem then
		return nil, problem
	end
	local worker = state.workers[request.workerId]
	if not worker then
		return nil, "WorkerNotOwned"
	end
	for _, shrine in state.shrines do
		for _, workerId in shrine.workerIdsBySlot do
			if workerId == request.workerId then
				return nil, "WorkerAlreadyAssigned"
			end
		end
	end
	local target = state.shrines[request.shrineInstanceId]
	local slotKey = tostring(request.slotId)
	if target.workerIdsBySlot[slotKey] ~= nil then
		return nil, "SlotOccupied"
	end
	if metadata.forms[worker.formId].element ~= metadata.shrines[target.shrineId].element then
		return nil, "ElementMismatch"
	end

	local result, accrualError = ShrineAccrual.Accrue(state, now, metadata, production, progression)
	if not result then
		return nil, accrualError
	end
	result.shrines[request.shrineInstanceId].workerIdsBySlot[slotKey] = request.workerId
	return result, nil
end

function ShrineAssignments.Remove(
	state: State,
	now: number,
	rawRequest: RemoveRequest,
	metadata: Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (State?, string?)
	local request = parseRemove(rawRequest)
	if not request then
		return nil, "InvalidRequest"
	end
	local problem = validateChange(state, now, metadata, production, progression)
	if problem then
		return nil, problem
	end
	problem = validateDestination(state, request.shrineInstanceId, request.slotId, metadata)
	if problem then
		return nil, problem
	end
	local slotKey = tostring(request.slotId)
	if
		state.shrines[request.shrineInstanceId].workerIdsBySlot[slotKey] ~= request.expectedWorkerId
	then
		return nil, "AssignmentChanged"
	end

	local result, accrualError = ShrineAccrual.Accrue(state, now, metadata, production, progression)
	if not result then
		return nil, accrualError
	end
	result.shrines[request.shrineInstanceId].workerIdsBySlot[slotKey] = nil
	return result, nil
end

return table.freeze(ShrineAssignments)
