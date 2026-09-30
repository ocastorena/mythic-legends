--!strict
-- ServerScriptService/Services/CraftingService/CraftingCommands
-- Read-only Station views and strict commands using DataService's mutation-preparation timestamp.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local CraftingJobs = require(script.Parent.CraftingJobs)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc, number) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type CraftingCommands = {
	GetStation: (Player, Types.GetCraftingStationRequest) -> Types.CraftingStationViewResult,
	Start: (Player, Types.StartCraftingRequest) -> Types.TransactionResult,
	Cancel: (Player, Types.CancelCraftingRequest) -> Types.TransactionResult,
}
export type AccessCheck = (Player, Types.PlayerDoc, string?) -> string?

local CraftingCommands = {}
local START_FIELDS = {
	requestId = true,
	expectedRevision = true,
	stationInstanceId = true,
	recipeId = true,
	expectedGoldCost = true,
	expectedMaterialId = true,
	expectedMaterialQuantity = true,
	expectedDefinitionId = true,
	expectedFinishId = true,
	expectedQuantity = true,
	expectedDurationSeconds = true,
}
local CANCEL_FIELDS = { requestId = true, expectedRevision = true, jobId = true }
local VIEW_FIELDS = { stationInstanceId = true }

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function positiveWhole(value: unknown): boolean
	return whole(value) and (value :: number) > 0
end

local function closed(value: unknown, allowed: { [string]: boolean }): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if type(key) ~= "string" or not allowed[key] then
			return false
		end
	end
	return true
end

local function parseStart(value: unknown): Types.StartCraftingRequest?
	if not closed(value, START_FIELDS) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.stationInstanceId)
		or not isId(fields.recipeId)
		or not whole(fields.expectedGoldCost)
		or not isId(fields.expectedMaterialId)
		or not positiveWhole(fields.expectedMaterialQuantity)
		or not isId(fields.expectedDefinitionId)
		or not isId(fields.expectedFinishId)
		or not positiveWhole(fields.expectedQuantity)
		or not positiveWhole(fields.expectedDurationSeconds)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		stationInstanceId = fields.stationInstanceId :: string,
		recipeId = fields.recipeId :: string,
		expectedGoldCost = fields.expectedGoldCost :: number,
		expectedMaterialId = fields.expectedMaterialId :: string,
		expectedMaterialQuantity = fields.expectedMaterialQuantity :: number,
		expectedDefinitionId = fields.expectedDefinitionId :: string,
		expectedFinishId = fields.expectedFinishId :: string,
		expectedQuantity = fields.expectedQuantity :: number,
		expectedDurationSeconds = fields.expectedDurationSeconds :: number,
	}
end

local function parseCancel(value: unknown): Types.CancelCraftingRequest?
	if not closed(value, CANCEL_FIELDS) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.jobId)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		jobId = fields.jobId :: string,
	}
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if type(state) == "table" and getmetatable(state) == nil then
		local revision = (state :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function idPart(value: string): string
	return `{#value}:{value}`
end

local function numericPart(value: number): string
	return string.format("%.0f", value + 0)
end

function CraftingCommands.new(
	DataService: DataSource,
	jobs: CraftingJobs.CraftingJobs,
	clock: (() -> number)?,
	checkAccess: AccessCheck?
): CraftingCommands
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[CraftingService.CraftingCommands] DataService.GetLoadedData and Transact required"
	)
	assert(
		type(jobs) == "table"
			and type(jobs.ReadStation) == "function"
			and type(jobs.StartToDraft) == "function"
			and type(jobs.CancelToDraft) == "function",
		"[CraftingService.CraftingCommands] CraftingJobs required"
	)
	local sampleTime = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.GetStation(
		player: Player,
		rawRequest: Types.GetCraftingStationRequest
	): Types.CraftingStationViewResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local revision = currentRevision(loaded)
		if revision < 0 then
			return { ok = false, code = "InvalidTransaction", revision = revision }
		end
		if not closed(rawRequest, VIEW_FIELDS) or not isId(rawRequest.stationInstanceId) then
			return { ok = false, code = "InvalidRequest", revision = revision }
		end
		local accessProblem = if checkAccess
			then checkAccess(player, loaded, rawRequest.stationInstanceId)
			else nil
		if accessProblem then
			return { ok = false, code = accessProblem, revision = revision }
		end
		local sampled, now = pcall(sampleTime)
		if not sampled or type(now) ~= "number" or now ~= now or now < 0 or now >= 2 ^ 53 then
			return { ok = false, code = "InvalidTimestamp", revision = revision }
		end
		local view, problem = jobs.ReadStation(loaded, now, rawRequest.stationInstanceId)
		if not view then
			return { ok = false, code = problem, revision = revision }
		end
		return { ok = true, revision = revision, view = view }
	end

	function api.Start(
		player: Player,
		rawRequest: Types.StartCraftingRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseStart(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local signature = table.concat({
			`station={idPart(request.stationInstanceId)}`,
			`recipe={idPart(request.recipeId)}`,
			`gold={numericPart(request.expectedGoldCost)}`,
			`material={idPart(request.expectedMaterialId)}`,
			`materials={numericPart(request.expectedMaterialQuantity)}`,
			`definition={idPart(request.expectedDefinitionId)}`,
			`finish={idPart(request.expectedFinishId)}`,
			`quantity={numericPart(request.expectedQuantity)}`,
			`duration={numericPart(request.expectedDurationSeconds)}`,
		}, ";")
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Crafting.Start",
			signature = signature,
		}, function(draft: Types.PlayerDoc, now: number): Types.TransactionOutcome
			-- World checks belong after receipt/revision admission, never before committed retries.
			local accessProblem = if checkAccess
				then checkAccess(player, draft, request.stationInstanceId)
				else nil
			if accessProblem then
				return { ok = false, code = accessProblem }
			end
			return jobs.StartToDraft(draft, now, request)
		end)
	end

	function api.Cancel(
		player: Player,
		rawRequest: Types.CancelCraftingRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseCancel(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Crafting.Cancel",
			signature = `job={idPart(request.jobId)}`,
		}, function(draft: Types.PlayerDoc, now: number): Types.TransactionOutcome
			-- Cancel uses the saved permanent Station; job/receipt validation remains with its owner.
			local accessProblem = if checkAccess then checkAccess(player, draft, nil) else nil
			if accessProblem then
				return { ok = false, code = accessProblem }
			end
			return jobs.CancelToDraft(draft, now, request.jobId)
		end)
	end

	return api
end

return table.freeze(CraftingCommands)
