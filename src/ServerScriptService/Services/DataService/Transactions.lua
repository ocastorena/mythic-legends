--!strict
-- ServerScriptService/Services/DataService/Transactions
-- Session-atomic, non-yielding mutations. A committed result is NOT a durable-save acknowledgement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)

local Transactions = {}
local busy: { [Types.PlayerDoc]: boolean } = {}
export type Mutator = (Types.PlayerDoc) -> Types.TransactionOutcome

local function whole(value: number): boolean
	return value == value and value >= 0 and value < 2 ^ 53 and value % 1 == 0
end

local function plainTable(value: any): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

-- Dynamic access is confined to this recursive saved-value boundary. Reject cycles,
-- metatables and non-serializable values before touching the live profile.
local function clone(value: any, ancestors: { [any]: boolean }?, depth: number?): any
	local kind = type(value)
	if kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "Non-finite saved number")
	elseif kind ~= "table" then
		assert(kind == "nil" or kind == "string" or kind == "boolean", "Invalid saved value")
	end
	if kind ~= "table" then
		return value
	end
	local seen = ancestors or {}
	local nesting = depth or 0
	assert(nesting < 32 and not seen[value] and getmetatable(value) == nil, "Invalid saved table")
	seen[value] = true
	local result = {}
	for key, child in pairs(value) do
		assert(type(key) == "string" or (type(key) == "number" and whole(key)), "Invalid saved key")
		result[key] = clone(child, seen, nesting + 1)
	end
	seen[value] = nil
	return result
end

local function equal(left: any, right: any): boolean
	if type(left) ~= "table" or type(right) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not equal(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

-- Existing prototype consumers retain section/entry references. Preserve unchanged
-- identities while installing the detached commit, without a yield or outward callback.
local function install(target: any, source: any)
	for key in pairs(target) do
		if source[key] == nil then
			target[key] = nil
		end
	end
	for key, value in pairs(source) do
		local old = target[key]
		if not equal(old, value) then
			if type(old) == "table" and type(value) == "table" and not table.isfrozen(old) then
				install(old, value)
			else
				target[key] = value
			end
		end
	end
end

local function bounded(value: string, maximum: number, allowEmpty: boolean?): boolean
	return type(value) == "string" and (allowEmpty == true or #value > 0) and #value <= maximum
end

local function validOutcome(outcome: Types.TransactionOutcome): boolean
	if type(outcome) ~= "table" or type(outcome.ok) ~= "boolean" then
		return false
	end
	if outcome.code ~= nil and not bounded(outcome.code, Configuration.maxSignatureLength) then
		return false
	end
	if outcome.values ~= nil then
		if type(outcome.values) ~= "table" then
			return false
		end
		local count = 0
		for key, value in pairs(outcome.values) do
			count += 1
			if
				count > Configuration.maxResultFields
				or not bounded(key, Configuration.maxOperationLength)
			then
				return false
			end
			if type(value) == "string" then
				if not bounded(value, Configuration.maxSignatureLength, true) then
					return false
				end
			elseif type(value) == "number" then
				if value ~= value or math.abs(value) == math.huge then
					return false
				end
			elseif type(value) ~= "boolean" then
				return false
			end
		end
	end
	return true
end

function Transactions.GetRevision(data: Types.PlayerDoc): number
	local rawState: unknown = data.transactions
	if rawState == nil then
		return 0
	end
	if type(rawState) == "table" then
		local rawRevision = (rawState :: { [string]: unknown }).revision
		if type(rawRevision) == "number" and whole(rawRevision) then
			return rawRevision
		end
	end
	return -1 -- Invalid saved bookkeeping must fail closed, never silently restart at zero.
end

function Transactions.Run(
	data: Types.PlayerDoc,
	request: Types.TransactionRequest,
	mutate: Mutator,
	isActive: () -> boolean
): Types.TransactionResult
	local revision = Transactions.GetRevision(data)
	local function reject(code: string): Types.TransactionResult
		return { ok = false, code = code, revision = revision }
	end
	if not isActive() then
		return reject("DataUnavailable")
	end
	if busy[data] then
		return reject("TransactionBusy")
	end
	if
		not whole(revision)
		or revision >= 2 ^ 53 - 1
		or type(request) ~= "table"
		or not bounded(request.id, Configuration.maxRequestIdLength)
		or not bounded(request.operation, Configuration.maxOperationLength)
		or not bounded(request.signature, Configuration.maxSignatureLength, true)
		or type(request.expectedRevision) ~= "number"
		or not whole(request.expectedRevision)
	then
		return reject("InvalidTransaction")
	end
	local state = data.transactions or { revision = 0, receipts = {} }
	if type(state.receipts) ~= "table" then
		return reject("InvalidTransaction")
	end
	local receipt = state.receipts[request.id]
	if receipt then
		if not plainTable(receipt) or not plainTable(receipt.result) then
			return reject("InvalidTransaction")
		end
		if
			receipt.expectedRevision ~= request.expectedRevision
			or receipt.operation ~= request.operation
			or receipt.signature ~= request.signature
		then
			return reject("RequestConflict")
		end
		local replayOk, replay = pcall(function(): Types.TransactionResult?
			local saved = receipt.result
			if
				not validOutcome(saved)
				or type(saved.revision) ~= "number"
				or not whole(saved.revision)
				or saved.revision ~= request.expectedRevision + 1
				or saved.revision > revision
			then
				return nil
			end
			-- Validate the entire stored value, then return only the documented result fields.
			local restored: Types.TransactionResult = clone(saved)
			return {
				ok = restored.ok,
				code = restored.code,
				values = restored.values,
				revision = restored.revision,
				replayed = true,
			}
		end)
		return if replayOk and replay then replay else reject("InvalidTransaction")
	end
	-- An evicted receipt cannot run again against the newer persisted revision.
	if request.expectedRevision ~= revision then
		return reject("StaleRevision")
	end
	local prefix = `{request.expectedRevision}:`
	if string.sub(request.id, 1, #prefix) ~= prefix or #request.id == #prefix then
		return reject("InvalidTransaction")
	end
	busy[data] = true
	local ok, result = pcall(function(): Types.TransactionResult
		local draft: Types.PlayerDoc = clone(data)
		local worker = coroutine.create(mutate)
		local resumed, outcome = coroutine.resume(worker, draft)
		if coroutine.status(worker) ~= "dead" then
			pcall(task.cancel, worker)
			return reject("MutationYielded")
		end
		if not resumed or not validOutcome(outcome) then
			return reject("MutationFailed")
		end
		if not isActive() then
			return reject("DataUnavailable")
		end
		local answer: Types.TransactionResult = {
			ok = outcome.ok,
			code = outcome.code,
			values = clone(outcome.values),
			revision = revision + 1,
		}
		-- Rejections record their original answer but discard every gameplay edit.
		local staged: Types.PlayerDoc = clone(if outcome.ok then draft else data)
		local nextState: Types.TransactionState = clone(state)
		nextState.revision = answer.revision
		nextState.receipts[request.id] = {
			expectedRevision = request.expectedRevision,
			operation = request.operation,
			signature = request.signature,
			result = clone(answer),
		}
		local minimum = answer.revision - Configuration.maxRequestReceipts
		for id, saved in pairs(nextState.receipts) do
			if saved.result.revision <= minimum then
				nextState.receipts[id] = nil
			end
		end
		staged.transactions = nextState
		install(data, staged)
		return answer
	end)
	busy[data] = nil
	return if ok then result else reject("MutationFailed")
end

-- Transitional writes in the prototype Base/Loadout code must invalidate stale
-- revision-bound commands too. New gameplay uses Run, never this compatibility hook.
function Transactions.Invalidate(data: Types.PlayerDoc)
	assert(not busy[data], "Direct writes are not allowed inside a transaction")
	local state = data.transactions or { revision = 0, receipts = {} }
	assert(whole(state.revision) and state.revision < 2 ^ 53 - 1, "Invalid transaction revision")
	state.revision += 1
	data.transactions = state
end

return table.freeze(Transactions)
