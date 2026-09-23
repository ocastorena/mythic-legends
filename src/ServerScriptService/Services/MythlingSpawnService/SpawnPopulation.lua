--!strict
-- ServerScriptService/Services/MythlingSpawnService/SpawnPopulation
-- Pending replacements retain their chosen form and independent refill deadline.

local SpawnPopulation = {}

export type Attempt = {
	id: number,
	typeId: string?,
	missingSince: number,
	deadlineAt: number,
	warned: boolean,
}
export type State = {
	target: number,
	deadlineSeconds: number,
	nextAttemptId: number,
	pending: { [number]: Attempt },
	ready: boolean,
}

function SpawnPopulation.New(target: number, deadlineSeconds: number): State
	return {
		target = target,
		deadlineSeconds = deadlineSeconds,
		nextAttemptId = 0,
		pending = {},
		ready = false,
	}
end

function SpawnPopulation.QueueDeficits(
	state: State,
	registeredCount: number,
	now: number,
	chooseForm: () -> string?
)
	local pendingCount = 0
	for _ in state.pending do
		pendingCount += 1
	end
	for _ = 1, math.max(0, state.target - registeredCount - pendingCount) do
		state.nextAttemptId += 1
		local id = state.nextAttemptId
		state.pending[id] = {
			id = id,
			typeId = chooseForm(),
			missingSince = now,
			deadlineAt = now + state.deadlineSeconds,
			warned = false,
		}
	end
end

function SpawnPopulation.GetPending(state: State): { Attempt }
	local pending: { Attempt } = {}
	for _, attempt in state.pending do
		table.insert(pending, attempt)
	end
	table.sort(pending, function(left: Attempt, right: Attempt)
		return left.id < right.id
	end)
	return pending
end

function SpawnPopulation.Complete(state: State, attemptId: number)
	state.pending[attemptId] = nil
end

function SpawnPopulation.OpenIfFilled(state: State, registeredCount: number): boolean
	if state.ready or registeredCount < state.target or next(state.pending) ~= nil then
		return false
	end
	state.ready = true
	return true
end

function SpawnPopulation.ReportDeadline(attempt: Attempt, now: number): boolean
	if attempt.warned or now < attempt.deadlineAt then
		return false
	end
	attempt.warned = true
	return true
end

return table.freeze(SpawnPopulation)
