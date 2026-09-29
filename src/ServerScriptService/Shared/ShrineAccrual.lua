--!strict
-- ServerScriptService/Shared/ShrineAccrual
-- Detached accounting only: callers must settle before changing inputs and commit the whole result.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local MythlingProgression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local Types = require(ReplicatedStorage.Shared.Types)
local MythlingProgressionUtil = require(script.Parent.MythlingProgressionUtil)

export type ProductionConfig = { batchIntervalSeconds: number, baseXpPerSecond: number }
export type ProgressionConfig = MythlingProgressionUtil.Config
export type Worker = { formId: string, level: number, xp: number, pendingXp: number }
export type Shrine = {
	shrineId: string,
	level: number,
	workerIdsBySlot: { [string]: string },
	stored: number,
	progress: number,
	newWork: number,
}
export type State = {
	lastAccruedAt: number,
	nextBatchAt: number,
	shrines: { [string]: Shrine },
	workers: { [string]: Worker },
}
export type FormDefinition = { element: string, baseYieldPerHour: number }
export type ShrineDefinition = {
	element: string,
	materialId: string,
	levels: { [number]: Types.ShrineLevelDef },
}
export type Metadata = {
	forms: { [string]: FormDefinition },
	shrines: { [string]: ShrineDefinition },
}

local MAX_SAFE_INTEGER = 9007199254740991
local ShrineAccrual = {}

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= MAX_SAFE_INTEGER
end

local function isInteger(value: unknown): boolean
	return isNumber(value) and (value :: number) % 1 == 0
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function canonicalSlotNumber(value: unknown): number?
	if type(value) ~= "string" then
		return nil
	end
	local slot = tonumber(value)
	if slot == nil or not isInteger(slot) or slot < 1 or tostring(slot) ~= value then
		return nil
	end
	return slot
end

-- Only correct floating-point noise immediately adjacent to an integer, not meaningful fractions.
local function snapInteger(value: number): number
	local nearest = math.round(value)
	if nearest > 0 and math.abs(value - nearest) <= math.min(1e-9, 1e-12 * math.abs(value)) then
		return nearest
	end
	return value
end

local function validate(
	state: State,
	now: number,
	metadata: Metadata,
	production: ProductionConfig,
	progression: ProgressionConfig
): string?
	if
		type(production) ~= "table"
		or not isNumber(production.batchIntervalSeconds)
		or production.batchIntervalSeconds <= 0
		or not isNumber(production.baseXpPerSecond)
		or type(progression) ~= "table"
		or not isInteger(progression.levelCap)
		or progression.levelCap < 1
		or not isNumber(progression.xpPerLevel)
		or progression.xpPerLevel <= 0
		or not isNumber(progression.yieldGainPerLevel)
		or not isNumber(progression.xpPerLevel * progression.levelCap)
	then
		return "InvalidConfiguration"
	end
	if
		type(state) ~= "table"
		or not isNumber(now)
		or not isNumber(state.lastAccruedAt)
		or not isNumber(state.nextBatchAt)
		or state.nextBatchAt <= state.lastAccruedAt
		or state.nextBatchAt > state.lastAccruedAt + production.batchIntervalSeconds
		or now + production.batchIntervalSeconds <= now
		or type(state.shrines) ~= "table"
		or type(state.workers) ~= "table"
	then
		return "InvalidState"
	end
	if
		type(metadata) ~= "table"
		or type(metadata.forms) ~= "table"
		or type(metadata.shrines) ~= "table"
	then
		return "InvalidMetadata"
	end
	for id, worker in state.workers do
		if
			not isId(id)
			or type(worker) ~= "table"
			or not isId(worker.formId)
			or not isInteger(worker.level)
			or worker.level < 1
			or worker.level > progression.levelCap
			or not isNumber(worker.xp)
			or not isNumber(worker.pendingXp)
		then
			return "InvalidWorker"
		end
		local form = metadata.forms[worker.formId]
		if
			type(form) ~= "table"
			or not isId(form.element)
			or not isNumber(form.baseYieldPerHour)
		then
			return "InvalidForm"
		end
		if
			not isNumber(
				form.baseYieldPerHour * (1 + progression.yieldGainPerLevel * (worker.level - 1))
			)
		then
			return "ArithmeticOverflow"
		end
		if
			worker.level < progression.levelCap
			and worker.xp >= progression.xpPerLevel * worker.level
		then
			return "UnresolvedLevel"
		end
	end
	local assigned: { [string]: boolean } = {}
	for id, shrine in state.shrines do
		if
			not isId(id)
			or type(shrine) ~= "table"
			or not isId(shrine.shrineId)
			or not isInteger(shrine.level)
			or shrine.level < 1
			or not isInteger(shrine.stored)
			or not isNumber(shrine.progress)
			or shrine.progress >= 1
			or not isNumber(shrine.newWork)
			or type(shrine.workerIdsBySlot) ~= "table"
		then
			return "InvalidShrine"
		end
		local definition = metadata.shrines[shrine.shrineId]
		if
			type(definition) ~= "table"
			or not isId(definition.element)
			or not isId(definition.materialId)
			or type(definition.levels) ~= "table"
		then
			return "InvalidShrineDefinition"
		end
		local level = definition.levels[shrine.level]
		if
			type(level) ~= "table"
			or not isInteger(level.capacity)
			or level.capacity < 1
			or not isInteger(level.workerSlots)
			or level.workerSlots < 1
		then
			return "InvalidShrineCapacity"
		end
		local count = 0
		for slotKey, workerId in shrine.workerIdsBySlot do
			local slot = canonicalSlotNumber(slotKey)
			if not slot or slot > level.workerSlots or not isId(workerId) then
				return "InvalidAssignment"
			end
			local worker = state.workers[workerId]
			if
				not worker
				or assigned[workerId]
				or metadata.forms[worker.formId].element ~= definition.element
			then
				return "InvalidAssignment"
			end
			assigned[workerId] = true
			count += 1
		end
		if count > level.workerSlots then
			return "InvalidAssignment"
		end
	end
	return nil
end

local function cloneState(state: State): State
	local result = table.clone(state)
	result.shrines = {}
	result.workers = {}
	for id, shrine in state.shrines do
		local copy = table.clone(shrine)
		copy.workerIdsBySlot = table.clone(shrine.workerIdsBySlot)
		result.shrines[id] = copy
	end
	for id, worker in state.workers do
		result.workers[id] = table.clone(worker)
	end
	return result
end

local function getOrderedSlots(shrine: Shrine): { number }
	local slots = {}
	for slotKey in shrine.workerIdsBySlot do
		table.insert(slots, tonumber(slotKey) :: number)
	end
	table.sort(slots)
	return slots
end

local function getCapacity(shrine: Shrine, metadata: Metadata): number
	return metadata.shrines[shrine.shrineId].levels[shrine.level].capacity
end

local function getRates(
	state: State,
	metadata: Metadata,
	progression: ProgressionConfig
): { [string]: number }
	local rates: { [string]: number } = {}
	for id, shrine in state.shrines do
		local rate = 0
		if shrine.stored < getCapacity(shrine, metadata) then
			for _, slot in getOrderedSlots(shrine) do
				local workerId = shrine.workerIdsBySlot[tostring(slot)]
				local worker = state.workers[workerId]
				rate += MythlingProgressionUtil.GetYield(
					metadata.forms[worker.formId].baseYieldPerHour,
					worker.level,
					progression
				) / 3600
			end
		end
		rates[id] = rate
	end
	return rates
end

-- After a boundary there are no pending contributions. Coalesce only identical complete batches,
-- ending at or just before the FIRST level/full-storage event. Floor is deliberately conservative:
-- a fractional event takes one final batch, without a rounded-up ratio skipping an event.
local function getBatchCount(
	state: State,
	maximum: number,
	rates: { [string]: number },
	metadata: Metadata,
	production: ProductionConfig,
	progression: ProgressionConfig
): number
	local count = maximum
	local xpPerBatch = production.baseXpPerSecond * production.batchIntervalSeconds
	for id, shrine in state.shrines do
		local space = getCapacity(shrine, metadata) - shrine.stored
		if space > 0 then
			local workPerBatch = rates[id] * production.batchIntervalSeconds
			if workPerBatch > 0 then
				count = math.min(
					count,
					math.max(1, math.floor((space - shrine.progress) / workPerBatch))
				)
			end
			if xpPerBatch > 0 then
				for _, slot in getOrderedSlots(shrine) do
					local workerId = shrine.workerIdsBySlot[tostring(slot)]
					local worker = state.workers[workerId]
					if worker.level < progression.levelCap then
						local needed = MythlingProgressionUtil.GetNextLevelXp(
							worker.level,
							progression
						) - worker.xp
						count = math.min(count, math.max(1, math.floor(needed / xpPerBatch)))
					end
				end
			end
		end
	end
	return count
end

local function accumulate(
	state: State,
	elapsed: number,
	rates: { [string]: number },
	metadata: Metadata,
	production: ProductionConfig,
	progression: ProgressionConfig
): boolean
	for id, shrine in state.shrines do
		if shrine.stored < getCapacity(shrine, metadata) then
			shrine.newWork += rates[id] * elapsed
			if not isNumber(shrine.newWork) then
				return false
			end
			for _, slot in getOrderedSlots(shrine) do
				local workerId = shrine.workerIdsBySlot[tostring(slot)]
				local worker = state.workers[workerId]
				if worker.level < progression.levelCap then
					worker.pendingXp += production.baseXpPerSecond * elapsed
					if not isNumber(worker.pendingXp) then
						return false
					end
				end
			end
		end
	end
	return true
end

local function resolveBatch(
	state: State,
	metadata: Metadata,
	progression: ProgressionConfig
): boolean
	for _, shrine in state.shrines do
		local earned = snapInteger(shrine.progress + shrine.newWork)
		if not isNumber(earned) then
			return false
		end
		local available = math.max(0, getCapacity(shrine, metadata) - shrine.stored)
		local granted = math.min(available, math.floor(earned))
		shrine.stored += granted
		-- A later capacity reduction cannot erase already-earned fractional or whole output.
		-- New overflowing work is discarded, but an already-full Shrine's retained progress waits.
		if available > 0 then
			shrine.progress = if granted == available then 0 else earned - granted
		end
		shrine.newWork = 0
	end
	for _, worker in state.workers do
		if not isNumber(worker.xp + worker.pendingXp) then
			return false
		end
		worker.level, worker.xp =
			MythlingProgressionUtil.AddXp(worker.level, worker.xp, worker.pendingXp, progression)
		worker.pendingXp = 0
		if not isNumber(worker.xp) then
			return false
		end
	end
	return true
end

-- now is server-authored. This ledger is NOT a PlayerDoc or an owned-Mythling replacement record.
-- A future transaction adapter must merge these accounting fields with the existing owned state.
-- Keep the explicit profile schedule through swaps, reconnects, collection, and empty/full time.
function ShrineAccrual.Validate(
	state: State,
	now: number,
	metadata: Metadata,
	productionConfig: ProductionConfig?,
	progressionConfig: ProgressionConfig?
): string?
	return validate(
		state,
		now,
		metadata,
		productionConfig or Production,
		progressionConfig or MythlingProgression
	)
end

function ShrineAccrual.Accrue(
	state: State,
	now: number,
	metadata: Metadata,
	productionConfig: ProductionConfig?,
	progressionConfig: ProgressionConfig?
): (State?, string?)
	local production = productionConfig or Production
	local progression = progressionConfig or MythlingProgression
	local problem = ShrineAccrual.Validate(state, now, metadata, production, progression)
	if problem then
		return nil, problem
	end
	local result = cloneState(state)
	local isAtBoundary = false
	while result.lastAccruedAt < now do
		local rates = getRates(result, metadata, progression)
		for _, rate in rates do
			if not isNumber(rate) then
				return nil, "ArithmeticOverflow"
			end
		end
		local endTime = math.min(now, result.nextBatchAt)
		if isAtBoundary then
			local completeBatches =
				math.floor((now - result.lastAccruedAt) / production.batchIntervalSeconds)
			if completeBatches > 0 then
				local count =
					getBatchCount(result, completeBatches, rates, metadata, production, progression)
				endTime = result.lastAccruedAt + count * production.batchIntervalSeconds
				if endTime > now then
					-- A rounded division must never settle a not-yet-complete final batch.
					endTime = if count > 1
						then result.lastAccruedAt + (count - 1) * production.batchIntervalSeconds
						else math.min(now, result.nextBatchAt)
				end
			end
		end
		if endTime <= result.lastAccruedAt or endTime > now then
			return nil, "InvalidSchedule"
		end
		if
			not accumulate(
				result,
				endTime - result.lastAccruedAt,
				rates,
				metadata,
				production,
				progression
			)
		then
			return nil, "ArithmeticOverflow"
		end
		isAtBoundary = endTime >= result.nextBatchAt
		result.lastAccruedAt = endTime
		if isAtBoundary then
			if not resolveBatch(result, metadata, progression) then
				return nil, "ArithmeticOverflow"
			end
			result.nextBatchAt = endTime + production.batchIntervalSeconds
			if not isNumber(result.nextBatchAt) or result.nextBatchAt <= endTime then
				return nil, "InvalidSchedule"
			end
		end
	end
	return result, nil
end

return table.freeze(ShrineAccrual)
