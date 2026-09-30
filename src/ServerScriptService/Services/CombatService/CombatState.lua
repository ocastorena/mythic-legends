--!strict
-- ServerScriptService/Services/CombatService/CombatState
-- Pure, mutable combat accounting. Callers own character eligibility and hit authorization.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

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
export type NegativeEffect = {
	effectId: string,
	kind: "Burn" | "Slow" | "Root" | "Weaken",
	phase: "Pending" | "Active",
	token: number,
	startedAt: number,
	expiresAt: number,
	staminaPerSecond: number?,
	walkSpeedMultiplier: number?,
	horizontalMultiplier: number?,
	rootSeconds: number?,
	recoverySeconds: number?,
	hasObservedAirborne: boolean?,
	airborneObservedAt: number?,
}
export type Movement = {
	walkSpeedMultiplier: number,
	blockJump: boolean,
	blockRotation: boolean,
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
	negativeEffect: NegativeEffect?,
	earthProtectedUntil: number,
	effectSequence: number,
}

local CombatState = {}
local ROUNDING_EPSILON = 2 ^ -52

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
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
		negativeEffect = nil,
		earthProtectedUntil = 0,
		effectSequence = 0,
	}
end

function CombatState.Advance(state: State, now: number)
	if not isFinite(now) then
		return
	end
	local target = math.max(now, state.lastUpdatedAt)
	-- Every interval has one net Stamina rate. Split at effect/guard deadlines and the first
	-- burn-driven minimum crossing, so lazy updates cannot credit guard time as recovery or
	-- subtract a burn only after regeneration has already been capped at maximum.
	while true do
		local at = state.lastUpdatedAt
		local effect = state.negativeEffect
		if effect and effect.expiresAt <= at then
			if effect.kind == "Root" and effect.phase == "Active" then
				state.earthProtectedUntil = effect.expiresAt + (effect.recoverySeconds or 0)
			end
			state.negativeEffect = nil
			effect = nil
		end

		local shield = state.shield
		local transitionAt: number? = nil
		if shield and (state.phase == "Raising" or state.phase == "Lowering") then
			local isRaising = state.phase == "Raising"
			local minimum = if isRaising then shield.raiseSeconds else shield.lowerSeconds
			local timeout = if isRaising
				then shield.raiseTimeoutSeconds
				else shield.lowerTimeoutSeconds
			transitionAt = math.max(
				at,
				state.phaseStartedAt + (if state.queuedMarker then minimum else timeout)
			)
			if transitionAt <= at then
				if isRaising then
					if state.queuedMarker and state.stamina >= shield.minimum then
						state.phase = "Guarding"
						state.phaseStartedAt = at
						state.protecting = true
						state.queuedMarker = false
					else
						startLowering(state, at, true)
					end
				else
					finishLowering(state, at)
				end
				continue
			end
		end
		if at >= target then
			break
		end

		local nextAt = target
		if transitionAt then
			nextAt = math.min(nextAt, transitionAt)
		end
		if effect then
			nextAt = math.min(nextAt, effect.expiresAt)
		end
		local burnRate = if effect and effect.kind == "Burn"
			then effect.staminaPerSecond or 0
			else 0
		local reachesMinimum = false
		if
			burnRate > 0
			and shield
			and state.phase ~= "Lowered"
			and (state.phase ~= "Lowering" or state.protecting)
		then
			local crossingAt = at + math.max(0, state.stamina - shield.minimum) / burnRate
			-- Repeated integrations can place the same mathematical boundary a few machine
			-- steps apart. Normalize that arithmetic tie, not a gameplay grace interval.
			local roundoff = 64 * ROUNDING_EPSILON * math.max(1, math.abs(at), math.abs(nextAt))
			if crossingAt > at and math.abs(crossingAt - nextAt) <= roundoff then
				crossingAt = nextAt
			end
			if crossingAt <= at then
				-- At the exact minimum, retain guard if no further burning time is requested.
				-- Otherwise the next positive interval crosses below it immediately. Releasing
				-- an already-lowering guard removes protection without restarting that deadline.
				startLowering(state, at, true)
				continue
			elseif crossingAt <= nextAt then
				nextAt = crossingAt
				reachesMinimum = true
			end
		end
		local recovery = if state.phase == "Lowered" then state.recoveryPerSecond else 0
		state.stamina =
			math.clamp(state.stamina + (nextAt - at) * (recovery - burnRate), 0, state.maximum)
		if reachesMinimum and shield then
			-- Avoid a rounding-only sub-threshold value when Fire ends exactly at the minimum.
			state.stamina = shield.minimum
		end
		state.lastUpdatedAt = nextAt
	end
end

local function positive(value: unknown): boolean
	return isFinite(value) and (value :: number) > 0
end

local function multiplier(value: unknown): boolean
	return positive(value) and (value :: number) <= 1
end

local function deadline(at: number, duration: number): number?
	local result = at + duration
	return if isFinite(result) and result > at then result else nil
end

function CombatState.ApplyNegative(
	state: State,
	now: number,
	effectId: string,
	tuning: Types.ElementalSwordEffect
): boolean
	CombatState.Advance(state, now)
	if
		not isFinite(now)
		or state.negativeEffect ~= nil
		or type(effectId) ~= "string"
		or #effectId == 0
		or #effectId > 128
		or type(tuning) ~= "table"
		or getmetatable(tuning) ~= nil
		or not isFinite(state.effectSequence)
		or state.effectSequence < 0
		or state.effectSequence % 1 ~= 0
		or state.effectSequence >= 2 ^ 53 - 1
	then
		return false
	end
	local at = state.lastUpdatedAt
	local effect: NegativeEffect
	if tuning.kind == "Burn" then
		if not positive(tuning.staminaPerSecond) or not positive(tuning.durationSeconds) then
			return false
		end
		local expiresAt = deadline(at, tuning.durationSeconds)
		if not expiresAt then
			return false
		end
		effect = {
			effectId = effectId,
			kind = "Burn",
			phase = "Active",
			token = state.effectSequence + 1,
			startedAt = at,
			expiresAt = expiresAt,
			staminaPerSecond = tuning.staminaPerSecond,
		}
	elseif tuning.kind == "Slow" then
		if not multiplier(tuning.walkSpeedMultiplier) or not positive(tuning.durationSeconds) then
			return false
		end
		local expiresAt = deadline(at, tuning.durationSeconds)
		if not expiresAt then
			return false
		end
		effect = {
			effectId = effectId,
			kind = "Slow",
			phase = "Active",
			token = state.effectSequence + 1,
			startedAt = at,
			expiresAt = expiresAt,
			walkSpeedMultiplier = tuning.walkSpeedMultiplier,
		}
	elseif tuning.kind == "Weaken" then
		if not multiplier(tuning.horizontalMultiplier) or not positive(tuning.durationSeconds) then
			return false
		end
		local expiresAt = deadline(at, tuning.durationSeconds)
		if not expiresAt then
			return false
		end
		effect = {
			effectId = effectId,
			kind = "Weaken",
			phase = "Active",
			token = state.effectSequence + 1,
			startedAt = at,
			expiresAt = expiresAt,
			horizontalMultiplier = tuning.horizontalMultiplier,
		}
	elseif tuning.kind == "Root" then
		if
			at < state.earthProtectedUntil
			or not positive(tuning.rootSeconds)
			or not positive(tuning.landingTimeoutSeconds)
			or not isFinite(tuning.recoverySeconds)
			or tuning.recoverySeconds < 0
		then
			return false
		end
		local expiresAt = deadline(at, tuning.landingTimeoutSeconds)
		local latestRootEnd = if expiresAt then deadline(expiresAt, tuning.rootSeconds) else nil
		if
			not expiresAt
			or not latestRootEnd
			or not isFinite(latestRootEnd + tuning.recoverySeconds)
		then
			return false
		end
		effect = {
			effectId = effectId,
			kind = "Root",
			phase = "Pending",
			token = state.effectSequence + 1,
			startedAt = at,
			expiresAt = expiresAt,
			rootSeconds = tuning.rootSeconds,
			recoverySeconds = tuning.recoverySeconds,
			hasObservedAirborne = false,
		}
	else
		return false
	end
	state.effectSequence = effect.token
	state.negativeEffect = table.freeze(effect)
	return true
end

function CombatState.ObserveEarth(
	state: State,
	now: number,
	token: number,
	airborne: boolean,
	supported: boolean
): boolean
	if not isFinite(now) or now < state.lastUpdatedAt then
		return false
	end
	CombatState.Advance(state, now)
	local effect = state.negativeEffect
	if
		not effect
		or effect.kind ~= "Root"
		or effect.phase ~= "Pending"
		or token ~= effect.token
		or now <= effect.startedAt
		or type(airborne) ~= "boolean"
		or type(supported) ~= "boolean"
	then
		return false
	end
	if airborne then
		if not effect.hasObservedAirborne then
			local observed: NegativeEffect = table.clone(effect)
			observed.hasObservedAirborne = true
			observed.airborneObservedAt = now
			-- Install before freezing to retain the writable field type; neither operation yields.
			state.negativeEffect = observed
			table.freeze(observed)
		end
		return false
	end
	local observedAt = effect.airborneObservedAt
	if not supported or not observedAt or now <= observedAt then
		return false
	end
	local expiresAt = deadline(now, effect.rootSeconds or 0)
	if not expiresAt then
		return false
	end
	local rooted: NegativeEffect = table.clone(effect)
	rooted.phase = "Active"
	rooted.expiresAt = expiresAt
	state.negativeEffect = rooted
	table.freeze(rooted)
	return true
end

function CombatState.Refund(state: State, now: number, amount: number)
	CombatState.Advance(state, now)
	if not isFinite(now) or not isFinite(amount) or amount < 0 then
		return
	end
	state.stamina += math.min(amount, state.maximum - state.stamina)
end

function CombatState.GetHorizontalMultiplier(state: State, now: number): number
	CombatState.Advance(state, now)
	local effect = state.negativeEffect
	return if effect and effect.kind == "Weaken" then effect.horizontalMultiplier or 1 else 1
end

function CombatState.GetMovement(state: State, now: number): Movement
	CombatState.Advance(state, now)
	local guard = state.phase ~= "Lowered"
	local effect = state.negativeEffect
	local root = effect ~= nil and effect.kind == "Root" and effect.phase == "Active"
	local slow = if effect and effect.kind == "Slow" then effect.walkSpeedMultiplier or 1 else 1
	return {
		walkSpeedMultiplier = if guard or root then 0 else slow,
		blockJump = guard or root,
		blockRotation = guard,
	}
end

function CombatState.ClearEffects(state: State, now: number)
	CombatState.Advance(state, now)
	if not isFinite(now) then
		return
	end
	state.negativeEffect = nil
	state.earthProtectedUntil = 0
	-- Do not recycle tokens: a delayed observation cannot arm a later effect after cleanup.
end

function CombatState.GetEffect(state: State, now: number): NegativeEffect?
	CombatState.Advance(state, now)
	local effect = state.negativeEffect
	return if effect then table.clone(effect) else nil
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
