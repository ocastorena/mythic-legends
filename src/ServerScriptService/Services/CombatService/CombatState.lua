--!strict
-- ServerScriptService/Services/CombatService/CombatState
-- Pure, mutable combat accounting. Callers own character eligibility and hit authorization.

export type Phase = "Lowered" | "Raising" | "Guarding" | "Lowering"
export type Marker = "Raised" | "Lowered"
export type Tuning = { maximum: number, spawn: number, recoveryPerSecond: number }
export type AttackTuning = { cost: number, cooldownSeconds: number, durationSeconds: number }
export type ShieldTuning = {
	cost: number,
	minimum: number,
	raiseSeconds: number,
	raiseTimeoutSeconds: number,
	lowerSeconds: number,
	lowerTimeoutSeconds: number,
}
export type State = {
	stamina: number,
	maximum: number,
	recoveryPerSecond: number,
	phase: Phase,
	protecting: boolean,
	swingEndsAt: number,
	nextAttackAt: number,
	guardSequence: number,
	lastGuardSequence: number,
	lastUpdatedAt: number,
	phaseStartedAt: number,
	shield: ShieldTuning?,
	queuedMarker: boolean,
}

local CombatState = {}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function validShield(tuning: ShieldTuning, maximum: number): boolean
	return isFinite(tuning.cost)
		and isFinite(tuning.minimum)
		and tuning.cost > 0
		and tuning.minimum >= tuning.cost
		and tuning.minimum <= maximum
		and isFinite(tuning.raiseSeconds)
		and isFinite(tuning.raiseTimeoutSeconds)
		and tuning.raiseSeconds >= 0
		and tuning.raiseTimeoutSeconds >= tuning.raiseSeconds
		and isFinite(tuning.lowerSeconds)
		and isFinite(tuning.lowerTimeoutSeconds)
		and tuning.lowerSeconds >= 0
		and tuning.lowerTimeoutSeconds >= tuning.lowerSeconds
end

local function startLowering(state: State, at: number, forced: boolean)
	if forced then
		state.protecting = false
	end
	if state.phase == "Lowered" or state.phase == "Lowering" then
		return
	end
	state.phase = "Lowering"
	state.phaseStartedAt = at
	state.queuedMarker = false
end

local function finishLowering(state: State, at: number)
	state.phase = "Lowered"
	state.phaseStartedAt = at
	state.protecting = false
	state.queuedMarker = false
	state.shield = nil
end

function CombatState.New(now: number, tuning: Tuning): State
	assert(isFinite(now), "[CombatState] Invalid initial timestamp")
	assert(
		isFinite(tuning.maximum)
			and tuning.maximum > 0
			and isFinite(tuning.spawn)
			and tuning.spawn >= 0
			and tuning.spawn <= tuning.maximum
			and isFinite(tuning.recoveryPerSecond)
			and tuning.recoveryPerSecond >= 0,
		"[CombatState] Invalid Stamina tuning"
	)
	return {
		stamina = tuning.spawn,
		maximum = tuning.maximum,
		recoveryPerSecond = tuning.recoveryPerSecond,
		phase = "Lowered",
		protecting = false,
		swingEndsAt = now,
		nextAttackAt = now,
		guardSequence = 0,
		lastGuardSequence = 0,
		lastUpdatedAt = now,
		phaseStartedAt = now,
		shield = nil,
		queuedMarker = false,
	}
end

function CombatState.Advance(state: State, now: number)
	if not isFinite(now) then
		return
	end
	local target = math.max(now, state.lastUpdatedAt)
	-- Resolve deadlines before adding recovery: a lazy refresh may span both missing-marker
	-- timeouts and then eligible lowered time, but cannot credit either guard transition.
	while true do
		local shield = state.shield
		if not shield or (state.phase ~= "Raising" and state.phase ~= "Lowering") then
			break
		end
		local isRaising = state.phase == "Raising"
		local minimum = if isRaising then shield.raiseSeconds else shield.lowerSeconds
		local timeout = if isRaising then shield.raiseTimeoutSeconds else shield.lowerTimeoutSeconds
		local transitionAt = math.max(
			state.lastUpdatedAt,
			state.phaseStartedAt + (if state.queuedMarker then minimum else timeout)
		)
		if transitionAt > target then
			break
		end
		state.lastUpdatedAt = transitionAt
		if isRaising then
			if state.queuedMarker and state.stamina >= shield.minimum then
				state.phase = "Guarding"
				state.phaseStartedAt = transitionAt
				state.protecting = true
				state.queuedMarker = false
			else
				startLowering(state, transitionAt, true)
			end
		else
			finishLowering(state, transitionAt)
		end
	end
	if state.phase == "Lowered" then
		state.stamina = math.min(
			state.maximum,
			state.stamina + (target - state.lastUpdatedAt) * state.recoveryPerSecond
		)
	end
	state.lastUpdatedAt = target
end

function CombatState.TryAttack(state: State, now: number, tuning: AttackTuning): boolean
	CombatState.Advance(state, now)
	local at = state.lastUpdatedAt
	if
		not isFinite(now)
		or not isFinite(tuning.cost)
		or tuning.cost < 0
		or not isFinite(tuning.cooldownSeconds)
		or tuning.cooldownSeconds < 0
		or not isFinite(tuning.durationSeconds)
		or tuning.durationSeconds < 0
		or state.phase ~= "Lowered"
		or at < state.swingEndsAt
		or at < state.nextAttackAt
		or state.stamina < tuning.cost
	then
		return false
	end
	state.stamina -= tuning.cost
	state.nextAttackAt = at + tuning.cooldownSeconds
	state.swingEndsAt = at + tuning.durationSeconds
	return true
end

function CombatState.BeginGuard(
	state: State,
	now: number,
	sequence: number,
	tuning: ShieldTuning
): boolean
	CombatState.Advance(state, now)
	if not isFinite(sequence) or sequence % 1 ~= 0 or sequence <= state.lastGuardSequence then
		return false
	end
	-- A rejected held input cannot become a fresh guard when Stamina or an action lock recovers.
	state.lastGuardSequence = sequence
	local at = state.lastUpdatedAt
	if
		not isFinite(now)
		or not validShield(tuning, state.maximum)
		or state.phase ~= "Lowered"
		or at < state.swingEndsAt
		or state.stamina < tuning.minimum
	then
		return false
	end
	state.shield = {
		cost = tuning.cost,
		minimum = tuning.minimum,
		raiseSeconds = tuning.raiseSeconds,
		raiseTimeoutSeconds = tuning.raiseTimeoutSeconds,
		lowerSeconds = tuning.lowerSeconds,
		lowerTimeoutSeconds = tuning.lowerTimeoutSeconds,
	}
	state.guardSequence = sequence
	state.phase = "Raising"
	state.phaseStartedAt = at
	state.protecting = false
	state.queuedMarker = false
	CombatState.Advance(state, at)
	return true
end

function CombatState.Marker(state: State, now: number, sequence: number, marker: Marker): boolean
	CombatState.Advance(state, now)
	if
		not isFinite(now)
		or sequence ~= state.guardSequence
		or (marker ~= "Raised" and marker ~= "Lowered")
	then
		return false
	end
	if
		(marker == "Raised" and state.phase ~= "Raising")
		or (marker == "Lowered" and state.phase ~= "Lowering")
	then
		return false
	end
	state.queuedMarker = true
	CombatState.Advance(state, state.lastUpdatedAt)
	return true
end

function CombatState.ReleaseGuard(state: State, now: number, sequence: number?, forced: boolean)
	CombatState.Advance(state, now)
	if
		not isFinite(now)
		or (sequence ~= nil and sequence ~= state.guardSequence)
		or (not forced and sequence == nil)
	then
		return
	end
	startLowering(state, state.lastUpdatedAt, forced)
	CombatState.Advance(state, state.lastUpdatedAt)
end

function CombatState.Block(state: State, now: number): boolean
	CombatState.Advance(state, now)
	local shield = state.shield
	if not isFinite(now) or not shield or not state.protecting then
		return false
	end
	if state.stamina < shield.minimum or state.stamina < shield.cost then
		startLowering(state, state.lastUpdatedAt, true)
		CombatState.Advance(state, state.lastUpdatedAt)
		return false
	end
	state.stamina -= shield.cost
	if state.stamina < shield.minimum then
		startLowering(state, state.lastUpdatedAt, true)
		CombatState.Advance(state, state.lastUpdatedAt)
	end
	return true
end

return table.freeze(CombatState)
