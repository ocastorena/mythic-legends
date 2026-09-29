--!strict
-- ServerScriptService/Services/BaseService/ShrineDismantling
-- Detached removal of an empty Shrine and its logical build-slot ownership.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local BaseState = require(ServerScriptService.Shared.BaseState)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

export type State = ShrineAccrual.State
export type Metadata = ShrineAccrual.Metadata
export type Request = { shrineInstanceId: string, expectedLevel: number }
export type Result = {
	production: State,
	shrines: { [string]: Types.ShrineRecord },
	shrineInstanceId: string,
	shrineId: string,
	buildSlotId: number,
	level: number,
}

local REQUEST_FIELDS = { shrineInstanceId = true, expectedLevel = true }
local ShrineDismantling = {}

local function parseRequest(rawRequest: unknown): Request?
	if type(rawRequest) ~= "table" or getmetatable(rawRequest) ~= nil then
		return nil
	end
	local fields = rawRequest :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	local id = fields.shrineInstanceId
	local level = fields.expectedLevel
	if
		type(id) ~= "string"
		or #id == 0
		or #id > 128
		or type(level) ~= "number"
		or level ~= level
		or level < 1
		or level >= 2 ^ 53
		or level % 1 ~= 0
	then
		return nil
	end
	return { shrineInstanceId = id, expectedLevel = level }
end

local function viewsMatch(state: State, shrines: { [string]: Types.ShrineRecord }): boolean
	for id, built in shrines do
		local accounting = state.shrines[id]
		if
			not accounting
			or accounting.shrineId ~= built.shrineId
			or accounting.level ~= built.level
		then
			return false
		end
	end
	for id in state.shrines do
		if not shrines[id] then
			return false
		end
	end
	return true
end

-- Both views must describe the SAME authenticated loaded profile, including every built Shrine.
-- Commit the returned accounting ledger and base.shrines together with revision/receipt protection.
-- The result is not a whole Base: preserve purchased slots, the Station, and legacy stands, and
-- never create refunds or delete a runtime model before that future live transaction succeeds.
function ShrineDismantling.Dismantle(
	state: State,
	base: Types.BaseRecord,
	now: number,
	rawRequest: Request,
	metadata: Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (Result?, string?)
	local request = parseRequest(rawRequest)
	if not request then
		return nil, "InvalidRequest"
	end
	if not BaseState.GetStatus(base) then
		return nil, "InvalidBaseState"
	end
	local problem = ShrineAccrual.Validate(state, now, metadata, production, progression)
	if problem then
		return nil, problem
	end
	if now < state.lastAccruedAt then
		return nil, "BackdatedChange"
	end
	-- BaseState has validated the optional load-boundary fields before this narrowing.
	local builtShrines = base.shrines :: { [string]: Types.ShrineRecord }
	if not viewsMatch(state, builtShrines) then
		return nil, "ShrineStateMismatch"
	end
	local built = builtShrines[request.shrineInstanceId]
	if not built then
		return nil, "ShrineNotOwned"
	end
	if built.level ~= request.expectedLevel then
		return nil, "LevelChanged"
	end
	if next(state.shrines[request.shrineInstanceId].workerIdsBySlot) ~= nil then
		return nil, "ShrineOccupied"
	end

	local settled, accrualError =
		ShrineAccrual.Accrue(state, now, metadata, production, progression)
	if not settled then
		return nil, accrualError
	end
	if settled.shrines[request.shrineInstanceId].stored > 0 then
		-- A due batch may have completed output after its worker was removed. Collect it first.
		return nil, "MaterialsStored"
	end

	local shrines: { [string]: Types.ShrineRecord } = {}
	for id, record in builtShrines do
		if id ~= request.shrineInstanceId then
			shrines[id] = table.clone(record)
		end
	end
	-- Unfinished work belongs to this Shrine and is discarded; earned XP belongs to workers.
	settled.shrines[request.shrineInstanceId] = nil
	return {
		production = settled,
		shrines = shrines,
		shrineInstanceId = request.shrineInstanceId,
		shrineId = built.shrineId,
		buildSlotId = built.buildSlotId,
		level = built.level,
	},
		nil
end

return table.freeze(ShrineDismantling)
