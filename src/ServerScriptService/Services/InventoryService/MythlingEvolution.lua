--!strict
-- ServerScriptService/Services/InventoryService/MythlingEvolution
-- Manual form changes over the detached production/XP ledger, never new acquisition grants.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MythlingProgression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

export type State = ShrineAccrual.State
export type EvolutionDefinition = Types.MythlingEvolutionDefinition
export type FormDefinition = ShrineAccrual.FormDefinition & { evolution: EvolutionDefinition? }
export type Metadata = {
	forms: { [string]: FormDefinition },
	shrines: { [string]: ShrineAccrual.ShrineDefinition },
}
export type Request = { workerId: string, expectedFormId: string, expectedTargetFormId: string }

local REQUEST_FIELDS = { workerId = true, expectedFormId = true, expectedTargetFormId = true }
local MythlingEvolution = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 53
end

local function isPlainTable(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function parseRequest(rawRequest: unknown): Request?
	if not isPlainTable(rawRequest) then
		return nil
	end
	local fields = rawRequest :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not isId(fields.workerId)
		or not isId(fields.expectedFormId)
		or not isId(fields.expectedTargetFormId)
	then
		return nil
	end
	return {
		workerId = fields.workerId :: string,
		expectedFormId = fields.expectedFormId :: string,
		expectedTargetFormId = fields.expectedTargetFormId :: string,
	}
end

local function getAccountingMetadata(metadata: Metadata): ShrineAccrual.Metadata?
	if
		not isPlainTable(metadata)
		or not isPlainTable(metadata.forms)
		or not isPlainTable(metadata.shrines)
	then
		return nil
	end
	-- Project the wider definition dictionary; accrual never changes static metadata.
	local accounting: ShrineAccrual.Metadata = { forms = {}, shrines = metadata.shrines }
	for id, definition in metadata.forms do
		accounting.forms[id] = definition
	end
	return accounting
end

local function hasValidChain(metadata: Metadata, formId: string, levelCap: number): boolean
	local startingForm = metadata.forms[formId]
	if not isPlainTable(startingForm) then
		return false
	end
	local visited: { [string]: boolean } = {}
	local element = startingForm.element
	local currentId = formId
	while true do
		if visited[currentId] then
			return false
		end
		visited[currentId] = true
		local form = metadata.forms[currentId]
		if
			not isPlainTable(form)
			or not isId(form.element)
			or form.element ~= element
			or not isNumber(form.baseYieldPerHour)
		then
			return false
		end
		local evolution = form.evolution
		if evolution == nil then
			return true
		end
		if
			not isPlainTable(evolution)
			or not isId(evolution.targetFormId)
			or not isNumber(evolution.requiredLevel)
			or evolution.requiredLevel < 1
			or evolution.requiredLevel > levelCap
			or evolution.requiredLevel % 1 ~= 0
		then
			return false
		end
		currentId = evolution.targetFormId
	end
end

-- Select state and time from one authenticated loaded profile; metadata is server-owned.
-- Commit the entire returned ledger with revision/receipt protection. A repeated stale request
-- cannot advance a second form, but this pure reducer is not a durable duplicate-request receipt.
-- The live adapter must merge earned fields without replacing unrelated owned/profile data.
function MythlingEvolution.Evolve(
	state: State,
	now: number,
	rawRequest: Request,
	metadata: Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (State?, string?)
	local request = parseRequest(rawRequest)
	if not request then
		return nil, "InvalidRequest"
	end
	local accounting = getAccountingMetadata(metadata)
	if not accounting then
		return nil, "InvalidMetadata"
	end
	local progressionConfig = progression or MythlingProgression
	local problem = ShrineAccrual.Validate(state, now, accounting, production, progressionConfig)
	if problem then
		return nil, problem
	end
	if now < state.lastAccruedAt then
		return nil, "BackdatedChange"
	end
	local worker = state.workers[request.workerId]
	if not worker then
		return nil, "WorkerNotOwned"
	end
	if worker.formId ~= request.expectedFormId then
		return nil, "FormChanged"
	end
	-- Generic link safety only; the complete six-chain launch catalogue has separate invariants.
	if not hasValidChain(metadata, worker.formId, progressionConfig.levelCap) then
		return nil, "InvalidEvolutionDefinition"
	end
	local evolution = metadata.forms[worker.formId].evolution
	if not evolution then
		return nil, "NoEvolution"
	end
	if evolution.targetFormId ~= request.expectedTargetFormId then
		return nil, "EvolutionTargetChanged"
	end

	-- OLD form supplies all preceding work. Due XP can unlock the requested form, but partial
	-- batches remain pending; this action never completes a batch early or shifts its clock.
	local settled, accrualError =
		ShrineAccrual.Accrue(state, now, accounting, production, progressionConfig)
	if not settled then
		return nil, accrualError
	end
	local evolvedWorker = settled.workers[request.workerId]
	if evolvedWorker.level < evolution.requiredLevel then
		return nil, "LevelTooLow"
	end
	evolvedWorker.formId = evolution.targetFormId
	-- Validate the new form at the settled level, including derived Yield arithmetic.
	problem = ShrineAccrual.Validate(settled, now, accounting, production, progressionConfig)
	if problem then
		return nil, problem
	end
	return settled, nil
end

return table.freeze(MythlingEvolution)
