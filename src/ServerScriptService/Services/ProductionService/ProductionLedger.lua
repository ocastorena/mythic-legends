--!strict
-- Earned work stays at its producing stand, separated by Material ID. This bridges the
-- prototype's single-worker stands until the full Shrine/batch/XP system is implemented.

export type MaterialWork = { stored: number, progress: number }
export type State = { lastAccruedAt: number, materials: { [string]: MaterialWork } }

local ProductionLedger = {}

local function copy(state: State): State
	local materials = {}
	for materialId, work in pairs(state.materials) do
		materials[materialId] = { stored = work.stored, progress = work.progress }
	end
	return { lastAccruedAt = state.lastAccruedAt, materials = materials }
end

function ProductionLedger.Accrue(
	state: State,
	now: number,
	materialId: string?,
	rate: number,
	capacity: number
): State
	local result = copy(state)
	local elapsed = math.max(0, now - state.lastAccruedAt)
	result.lastAccruedAt = math.max(now, state.lastAccruedAt)
	if not materialId or rate <= 0 or elapsed == 0 then
		return result
	end

	local stored = 0
	for _, work in pairs(result.materials) do
		stored += work.stored
	end
	local available = math.max(0, math.floor(capacity) - stored)
	if available == 0 then
		-- A replacement with smaller storage cannot erase work already earned.
		return result
	end

	local work = result.materials[materialId] or { stored = 0, progress = 0 }
	local earned = work.progress + rate * elapsed / 60
	-- Snap only machine-scale arithmetic error so splitting an interval does not
	-- delay a completed item (for example ten increments of 0.1).
	local nearestWhole = math.round(earned)
	if math.abs(earned - nearestWhole) <= 1e-12 * math.max(1, math.abs(earned)) then
		earned = nearestWhole
	end
	local completed = math.min(math.floor(earned), available)
	work.stored += completed
	work.progress = if completed == available then 0 else earned - completed
	result.materials[materialId] = work
	return result
end

function ProductionLedger.Collect(state: State): (State, { [string]: number })
	local result = copy(state)
	local collected = {}
	for materialId, work in pairs(result.materials) do
		if work.stored > 0 then
			collected[materialId] = work.stored
			work.stored = 0
		end
	end
	return result, collected
end

return table.freeze(ProductionLedger)
