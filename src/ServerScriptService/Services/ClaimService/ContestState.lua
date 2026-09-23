--!strict
-- ServerScriptService/Services/ClaimService/ContestState
-- Deterministic contest accounting. The caller rechecks ownership/capacity before accepting a winner.

export type Phase = "ACTIVE" | "OVERTIME" | "ENDED"
export type Meter = {
	progress: number,
	inside: boolean,
	visitOrder: number?,
	completionAt: number?,
	decaysAt: number?,
}
export type Candidate = { userId: number, completionAt: number, visitOrder: number }
export type Occupants = { [number]: boolean }
export type State = {
	phase: Phase,
	startAt: number,
	expireAt: number,
	fillRate: number,
	drainRate: number,
	lastUpdatedAt: number,
	meters: { [number]: Meter },
	occupants: Occupants,
	visitOrders: { [number]: number },
	nextVisitOrder: number,
	pendingCandidates: { [number]: Candidate },
	pendingEndAt: number?,
	endedAt: number?,
	winnerUserId: number?,
}

local ContestState = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function sortedCandidates(state: State): { Candidate }
	local candidates = {}
	for _, candidate in state.pendingCandidates do
		table.insert(candidates, {
			userId = candidate.userId,
			completionAt = candidate.completionAt,
			visitOrder = candidate.visitOrder,
		})
	end
	table.sort(candidates, function(left: Candidate, right: Candidate): boolean
		if left.completionAt ~= right.completionAt then
			return left.completionAt < right.completionAt
		end
		if left.visitOrder ~= right.visitOrder then
			return left.visitOrder < right.visitOrder
		end
		return left.userId < right.userId
	end)
	return candidates
end

local function endContest(state: State, at: number)
	state.phase = "ENDED"
	state.endedAt = at
	state.pendingEndAt = nil
	table.clear(state.meters)
	table.clear(state.occupants)
	table.clear(state.visitOrders)
	table.clear(state.pendingCandidates)
end

local function settleMeters(state: State, untilTime: number)
	for userId, meter in state.meters do
		if meter.inside and state.occupants[userId] == true then
			-- Resolve against this visit's fixed completion time instead of summing tick deltas;
			-- frequent updates cannot drift an exact-at-deadline capture beyond its deadline.
			local completedAt = meter.completionAt
				or state.lastUpdatedAt + (100 - meter.progress) / state.fillRate
			if completedAt <= untilTime then
				meter.progress = 100
				state.pendingCandidates[userId] = {
					userId = userId,
					completionAt = completedAt,
					visitOrder = meter.visitOrder or math.huge,
				}
			else
				meter.progress =
					math.clamp(100 - (completedAt - untilTime) * state.fillRate, 0, 100)
			end
			meter.completionAt = completedAt
		else
			local decaysAt = meter.decaysAt
			if decaysAt then
				meter.progress = math.clamp((decaysAt - untilTime) * state.drainRate, 0, 100)
			end
			if meter.progress == 0 then
				state.meters[userId] = nil
			end
		end
	end
	state.lastUpdatedAt = untilTime
end

local function settle(state: State, at: number)
	table.clear(state.pendingCandidates)
	-- A deadline before this sample uses the previous occupancy. New arrivals cannot revive
	-- a ring that was already empty at expiry. An occupied ring has no further time limit.
	if state.phase == "ACTIVE" and state.expireAt < at then
		if next(state.occupants) == nil then
			settleMeters(state, math.max(state.lastUpdatedAt, state.expireAt))
			state.pendingEndAt = state.expireAt
			return
		end
		state.phase = "OVERTIME"
	end
	settleMeters(state, at)
end

local function considerEnding(state: State, at: number)
	if state.phase == "ACTIVE" and at >= state.expireAt then
		if next(state.occupants) == nil then
			state.pendingEndAt = state.expireAt
		else
			state.phase = "OVERTIME"
		end
	elseif state.phase == "OVERTIME" and next(state.occupants) == nil then
		state.pendingEndAt = at
	end
end

function ContestState.New(
	startAt: number,
	expireAt: number,
	fillRate: number,
	drainRate: number
): State
	assert(
		isFinite(startAt)
			and isFinite(expireAt)
			and expireAt >= startAt
			and isFinite(fillRate)
			and fillRate > 0
			and isFinite(drainRate)
			and drainRate >= 0,
		"[ContestState] Invalid contest timing"
	)
	return {
		phase = "ACTIVE",
		startAt = startAt,
		expireAt = expireAt,
		fillRate = fillRate,
		drainRate = drainRate,
		lastUpdatedAt = startAt,
		meters = {},
		occupants = {},
		visitOrders = {},
		nextVisitOrder = 0,
		pendingCandidates = {},
		pendingEndAt = nil,
		endedAt = nil,
		winnerUserId = nil,
	}
end

function ContestState.SetOccupants(state: State, now: number, occupants: Occupants): { Candidate }
	if state.phase == "ENDED" or state.pendingEndAt ~= nil or not isFinite(now) then
		return sortedCandidates(state)
	end
	local at = math.max(now, state.lastUpdatedAt)
	settle(state, at)
	if state.pendingEndAt ~= nil then
		return sortedCandidates(state)
	end

	for userId in state.occupants do
		if occupants[userId] == nil then
			state.visitOrders[userId] = nil
			local meter = state.meters[userId]
			if meter then
				meter.inside = false
				meter.visitOrder = nil
				meter.completionAt = nil
				meter.decaysAt = if state.drainRate > 0
					then at + meter.progress / state.drainRate
					else nil
			end
		end
	end
	-- Sorting simultaneous observations gives each visit a stable unique server order.
	local userIds = {}
	for userId in occupants do
		table.insert(userIds, userId)
	end
	table.sort(userIds)
	local nextOccupants: Occupants = {}
	for _, userId in userIds do
		local eligible = occupants[userId]
		nextOccupants[userId] = eligible
		if state.occupants[userId] == nil then
			state.nextVisitOrder += 1
			state.visitOrders[userId] = state.nextVisitOrder
		end
		if eligible then
			local meter: Meter = state.meters[userId]
				or {
					progress = 0,
					inside = false,
					visitOrder = nil,
					completionAt = nil,
					decaysAt = nil,
				}
			state.meters[userId] = meter
			if not meter.inside then
				meter.completionAt = at + (100 - meter.progress) / state.fillRate
				meter.decaysAt = nil
			end
			meter.inside = true
			meter.visitOrder = state.visitOrders[userId]
		else
			-- Full players remain occupants but lose all earned capture work immediately.
			state.meters[userId] = nil
			state.pendingCandidates[userId] = nil
		end
	end
	state.occupants = nextOccupants
	considerEnding(state, at)
	return sortedCandidates(state)
end

function ContestState.Advance(state: State, now: number): { Candidate }
	return ContestState.SetOccupants(state, now, state.occupants)
end

function ContestState.RemovePlayer(state: State, now: number, userId: number): { Candidate }
	-- Reset/disconnect differs from ordinary departure: this player's old character cannot
	-- finish a capture, while other occupants may finish exactly at its removal time.
	state.meters[userId] = nil
	state.pendingCandidates[userId] = nil
	local occupants: Occupants = {}
	for occupantId, eligible in state.occupants do
		if occupantId ~= userId then
			occupants[occupantId] = eligible
		end
	end
	return ContestState.SetOccupants(state, now, occupants)
end

function ContestState.RejectCandidate(state: State, userId: number)
	state.meters[userId] = nil
	state.pendingCandidates[userId] = nil
	if state.occupants[userId] ~= nil then
		state.occupants[userId] = false
	end
end

function ContestState.AcceptWinner(state: State, userId: number): boolean
	local candidate = state.pendingCandidates[userId]
	if state.phase == "ENDED" or not candidate then
		return false
	end
	local first = sortedCandidates(state)[1]
	if not first or first.userId ~= userId then
		return false
	end
	state.winnerUserId = userId
	endContest(state, candidate.completionAt)
	return true
end

function ContestState.Finalize(state: State)
	local endAt = state.pendingEndAt
	if state.phase ~= "ENDED" and endAt then
		endContest(state, endAt)
	else
		table.clear(state.pendingCandidates)
	end
end

function ContestState.Contains(
	x: number,
	y: number,
	z: number,
	centerX: number,
	centerY: number,
	centerZ: number,
	radius: number,
	verticalAllowance: number
): boolean
	if
		not isFinite(x)
		or not isFinite(y)
		or not isFinite(z)
		or not isFinite(centerX)
		or not isFinite(centerY)
		or not isFinite(centerZ)
		or not isFinite(radius)
		or not isFinite(verticalAllowance)
		or radius < 0
		or verticalAllowance < 0
	then
		return false
	end
	local dx, dz = x - centerX, z - centerZ
	return dx * dx + dz * dz <= radius * radius and math.abs(y - centerY) <= verticalAllowance
end

return table.freeze(ContestState)
