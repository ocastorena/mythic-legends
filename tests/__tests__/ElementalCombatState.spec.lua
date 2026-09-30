--!strict
-- ServerStorage/Tests/__tests__/ElementalCombatState.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local CombatState = require(ServerScriptService.Services.CombatService.CombatState)
local Equipment = require(ReplicatedStorage.Shared.Configurations.Equipment)
local Effects = require(ReplicatedStorage.Shared.Configurations.ElementalSwordEffects)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local TIMED = { "fire_burn", "water_slow", "earth_root", "light_weaken" }
local sword = Equipment.definitions.wooden_sword
local ATTACK: CombatState.AttackTuning = {
	cost = sword.staminaCost :: number,
	cooldownSeconds = sword.cooldownSeconds :: number,
	durationSeconds = 0.5,
}

local function newState(spawn: number?): CombatState.State
	return CombatState.New(0, {
		maximum = Equipment.combat.staminaMaximum,
		spawn = if spawn ~= nil then spawn else Equipment.combat.staminaSpawn,
		recoveryPerSecond = Equipment.combat.staminaRegenPerSecond,
	})
end

local function shield(): CombatState.ShieldTuning
	return {
		cost = 30,
		minimum = 30,
		raiseSeconds = 0.25,
		raiseTimeoutSeconds = 1,
		lowerSeconds = 0.25,
		lowerTimeoutSeconds = 0.75,
	}
end

local function apply(state: CombatState.State, now: number, id: string)
	expect(CombatState.ApplyNegative(state, now, id, Effects[id])).toBe(true)
end

local function effect(state: CombatState.State, now: number)
	return (
		assert(CombatState.GetEffect(state, now), "[ElementalCombatState.spec] Expected effect")
	)
end

local function raise(state: CombatState.State)
	expect(CombatState.BeginGuard(state, 0, 1, shield())).toBe(true)
	expect(CombatState.Marker(state, 0.25, 1, "Raised")).toBe(true)
	expect(state.protecting).toBe(true)
end

local function root(state: CombatState.State): number
	apply(state, 0, "earth_root")
	local token = effect(state, 0).token
	expect(CombatState.ObserveEarth(state, 0.125, token, true, false)).toBe(false)
	expect(CombatState.ObserveEarth(state, 0.25, token, false, true)).toBe(true)
	return token
end

describe("Elemental CombatState Stamina accounting", function()
	it("integrates Fire and ordinary recovery as one partition-invariant net rate", function()
		local lazy, frequent = newState(), newState()
		apply(lazy, 0, "fire_burn")
		apply(frequent, 0, "fire_burn")
		for _, at in { 0.125, 0.3, 0.75, 1, 1.7, 2 } do
			CombatState.Advance(frequent, at)
		end
		CombatState.Advance(lazy, 2)
		expect(lazy.stamina).toBe(90)
		expect(frequent.stamina).toBeCloseTo(lazy.stamina, 10)
		expect(CombatState.GetEffect(lazy, 2)).toBeNil()
		CombatState.Advance(lazy, 1)
		CombatState.Advance(lazy, 2)
		expect(lazy.stamina).toBe(90)
		CombatState.Advance(lazy, 2.5)
		expect(lazy.stamina).toBe(95)
		CombatState.Advance(lazy, 20)
		expect(lazy.stamina).toBe(100)
		local empty = newState(0)
		apply(empty, 0, "fire_burn")
		CombatState.Advance(empty, 2)
		expect(empty.stamina).toBe(0)
		CombatState.Advance(empty, 3)
		expect(empty.stamina).toBe(10)
	end)

	it(
		"settles Fire threshold crossings during raising, guarding, and existing lowering chronologically",
		function()
			local scenarios: {
				{
					spawn: number,
					prepare: (CombatState.State) -> (),
					samples: { number },
					at: number,
					stamina: number,
					loweredAt: number,
				}
			} =
				{
					{
						spawn = 33,
						prepare = function(state)
							expect(CombatState.BeginGuard(state, 0, 1, shield())).toBe(true)
							expect(CombatState.Marker(state, 0, 1, "Raised")).toBe(true)
							apply(state, 0, "fire_burn")
						end,
						samples = { 0.1, 0.2, 0.3, 0.9, 0.95, 1.5, 2 },
						at = 2,
						stamina = 13.5,
						loweredAt = 0.95,
					},
					{
						spawn = 45,
						prepare = function(state)
							raise(state)
							apply(state, 0.25, "fire_burn")
						end,
						samples = { 0.5, 1, 1.25, 1.4, 1.9, 2, 2.25 },
						at = 2.25,
						stamina = 17.5,
						loweredAt = 2,
					},
					{
						spawn = 33,
						prepare = function(state)
							raise(state)
							CombatState.ReleaseGuard(state, 1, 1, false)
							apply(state, 1, "fire_burn")
						end,
						samples = { 1.1, 1.2, 1.3, 1.7, 1.75, 2, 3 },
						at = 3,
						stamina = 15.5,
						loweredAt = 1.75,
					},
				}
			for _, scenario in scenarios do
				local lazy, frequent = newState(scenario.spawn), newState(scenario.spawn)
				scenario.prepare(lazy)
				scenario.prepare(frequent)
				for _, at in scenario.samples do
					CombatState.Advance(frequent, at)
				end
				CombatState.Advance(lazy, scenario.at)
				for _, state in { lazy, frequent } do
					expect(state.stamina).toBeCloseTo(scenario.stamina, 10)
					expect(state.phaseStartedAt).toBeCloseTo(scenario.loweredAt, 10)
					expect(state.phase).toBe("Lowered")
					expect(state.protecting).toBe(false)
					expect(state.shield).toBeNil()
				end
			end
		end
	)

	it(
		"removes depleted protection before another block without shortening forced lowering",
		function()
			local state = newState(33)
			raise(state)
			apply(state, 0.25, "fire_burn")
			CombatState.Advance(state, 0.451)
			expect(state.phase).toBe("Lowering")
			expect(state.protecting).toBe(false)
			expect(state.phaseStartedAt).toBeCloseTo(0.45, 10)
			local before = state.stamina
			expect(CombatState.Block(state, 0.451)).toBe(false)
			expect(state.stamina).toBe(before)
			CombatState.ReleaseGuard(state, 0.5, nil, true)
			expect(state.phaseStartedAt).toBeCloseTo(0.45, 10)
			CombatState.Advance(state, 1.19)
			expect(state.phase).toBe("Lowering")
			CombatState.Advance(state, 1.2)
			expect(state.phase).toBe("Lowered")
			-- Fractional refresh partitions must not turn an expiry/minimum tie into guard loss.
			for _, step in { 2, 0.03, 0.07 } do
				local exact = newState(60)
				raise(exact)
				apply(exact, 0.25, "fire_burn")
				for index = 1, math.floor(2 / step) do
					CombatState.Advance(exact, 0.25 + index * step)
				end
				CombatState.Advance(exact, 2.25)
				expect(exact.stamina).toBeCloseTo(30, 10)
				expect(exact.phase).toBe("Guarding")
				expect(exact.protecting).toBe(true)
				expect(CombatState.GetEffect(exact, 2.25)).toBeNil()
				expect(CombatState.Block(exact, 2.25)).toBe(true)
				expect(exact.stamina).toBeCloseTo(0, 10)
			end
		end
	)

	it(
		"charges the full swing before Dark refunds and never invents guard recovery or exceeds maximum",
		function()
			local poor = newState(17)
			expect(CombatState.TryAttack(poor, 0, ATTACK)).toBe(false)
			expect(poor.stamina).toBe(17)
			local state = newState(20)
			apply(state, 0, "light_weaken")
			expect(CombatState.TryAttack(state, 0, ATTACK)).toBe(true)
			expect(state.stamina).toBe(0)
			CombatState.Refund(state, 0, 3)
			expect(state.stamina).toBe(3)
			expect(effect(state, 0).effectId).toBe("light_weaken")
			expect(CombatState.TryAttack(state, 1, ATTACK)).toBe(false)
			expect(state.stamina).toBe(13)
			local guarding = newState(60)
			raise(guarding)
			CombatState.Refund(guarding, 5, 3)
			expect(guarding.stamina).toBe(63)
			expect(guarding.phase).toBe("Guarding")
			local full = newState(99)
			CombatState.Refund(full, 0, 3)
			expect(full.stamina).toBe(100)
		end
	)
end)

describe("Elemental CombatState overlap and deadlines", function()
	it(
		"keeps the first of every timed-effect pairing with no replacement, extension, or queued successor",
		function()
			for _, firstId in TIMED do
				for _, laterId in TIMED do
					local state = newState()
					apply(state, 0, firstId)
					local first = effect(state, 0)
					expect(CombatState.ApplyNegative(state, 0.125, laterId, Effects[laterId])).toBe(
						false
					)
					expect(effect(state, 0.125)).toEqual(first)
					expect(state.effectSequence).toBe(first.token)
					expect(CombatState.GetEffect(state, first.expiresAt)).toBeNil()
					apply(state, first.expiresAt, laterId)
					expect(effect(state, first.expiresAt).token > first.token).toBe(true)
				end
			end
			for _, laterId in TIMED do
				local state = newState()
				root(state)
				local active = effect(state, 0.25)
				expect(CombatState.ApplyNegative(state, 0.5, laterId, Effects[laterId])).toBe(false)
				expect(effect(state, 0.5)).toEqual(active)
			end
		end
	)

	it(
		"requires a post-launch airborne observation and landing before rooting for exactly the configured time",
		function()
			local state = newState()
			apply(state, 0, "earth_root")
			local token = effect(state, 0).token
			expect(CombatState.ObserveEarth(state, 0, token, false, true)).toBe(false)
			expect(CombatState.ObserveEarth(state, 0.05, token, false, true)).toBe(false)
			expect(effect(state, 0.05).phase).toBe("Pending")
			expect(CombatState.ObserveEarth(state, 0.1, token, true, false)).toBe(false)
			expect(CombatState.ObserveEarth(state, 0.1, token, false, true)).toBe(false)
			expect(CombatState.ObserveEarth(state, 0.15, token, true, true)).toBe(false)
			expect(CombatState.ObserveEarth(state, 0.25, token, false, true)).toBe(true)
			local active = effect(state, 0.25)
			expect(active.phase).toBe("Active")
			expect(active.startedAt).toBe(0)
			expect(active.expiresAt).toBe(1)
			expect(CombatState.ObserveEarth(state, 0.5, token, false, true)).toBe(false)
			expect(effect(state, 0.999).expiresAt).toBe(1)
			expect(CombatState.GetEffect(state, 1)).toBeNil()
			expect(state.earthProtectedUntil).toBe(4)
			expect(CombatState.ApplyNegative(state, 3.999, "earth_root", Effects.earth_root)).toBe(
				false
			)
			apply(state, 4, "earth_root")
		end
	)

	it(
		"lets the pending timeout win at its exact deadline with no Earth protection, and ignores stale tokens",
		function()
			local state = newState()
			apply(state, 0, "earth_root")
			local expiredToken = effect(state, 0).token
			expect(CombatState.ObserveEarth(state, 1, expiredToken, true, false)).toBe(false)
			expect(CombatState.ObserveEarth(state, 3, expiredToken, false, true)).toBe(false)
			expect(CombatState.GetEffect(state, 3)).toBeNil()
			expect(state.earthProtectedUntil <= 3).toBe(true)
			apply(state, 3, "earth_root")
			local nextToken = effect(state, 3).token
			expect(nextToken > expiredToken).toBe(true)
			expect(CombatState.ObserveEarth(state, 3.1, expiredToken, true, false)).toBe(false)
			expect(CombatState.ObserveEarth(state, 3.2, nextToken, false, true)).toBe(false)
			CombatState.ClearEffects(state, 3.2)
			apply(state, 3.2, "earth_root")
			local replacement = effect(state, 3.2)
			expect(replacement.token > nextToken).toBe(true)
			expect(CombatState.ObserveEarth(state, 3.3, nextToken, true, false)).toBe(false)
			expect(CombatState.ObserveEarth(state, 3.4, replacement.token, false, true)).toBe(false)
			expect(effect(state, 3.4).phase).toBe("Pending")
		end
	)

	it(
		"starts Earth recovery at the actual root deadline even after a delayed refresh, blocking Earth only",
		function()
			local state = newState()
			root(state)
			CombatState.Advance(state, 2)
			expect(state.earthProtectedUntil).toBe(4)
			expect(CombatState.ApplyNegative(state, 2, "earth_root", Effects.earth_root)).toBe(
				false
			)
			apply(state, 2, "water_slow")
			expect(CombatState.GetMovement(state, 2).walkSpeedMultiplier).toBe(0.75)
			CombatState.Advance(state, 4)
			apply(state, 4, "earth_root")
			local delayed = newState()
			root(delayed)
			CombatState.Advance(delayed, 10)
			expect(delayed.earthProtectedUntil <= 10).toBe(true)
			apply(delayed, 10, "earth_root")
		end
	)
end)

describe("Elemental CombatState projections and cleanup", function()
	it(
		"composes Water and Earth with guard movement without independently locking attacks or guard",
		function()
			local water = newState()
			apply(water, 0, "water_slow")
			expect(CombatState.GetMovement(water, 0)).toEqual({
				walkSpeedMultiplier = 0.75,
				blockJump = false,
				blockRotation = false,
			})
			expect(CombatState.BeginGuard(water, 0.1, 1, shield())).toBe(true)
			expect(CombatState.Marker(water, 0.35, 1, "Raised")).toBe(true)
			expect(CombatState.GetMovement(water, 2)).toEqual({
				walkSpeedMultiplier = 0,
				blockJump = true,
				blockRotation = true,
			})
			CombatState.ReleaseGuard(water, 2, 1, false)
			expect(CombatState.Marker(water, 2, 1, "Lowered")).toBe(true)
			expect(CombatState.GetMovement(water, 2.25)).toEqual({
				walkSpeedMultiplier = 1,
				blockJump = false,
				blockRotation = false,
			})
			local attacker, defender = newState(), newState()
			root(attacker)
			root(defender)
			expect(CombatState.GetMovement(attacker, 0.25)).toEqual({
				walkSpeedMultiplier = 0,
				blockJump = true,
				blockRotation = false,
			})
			expect(CombatState.TryAttack(attacker, 0.25, ATTACK)).toBe(true)
			expect(CombatState.BeginGuard(defender, 0.25, 1, shield())).toBe(true)
			expect(CombatState.Marker(defender, 0.5, 1, "Raised")).toBe(true)
			expect(CombatState.GetMovement(defender, 1)).toEqual({
				walkSpeedMultiplier = 0,
				blockJump = true,
				blockRotation = true,
			})
			expect(CombatState.GetMovement(attacker, 1).walkSpeedMultiplier).toBe(1)
		end
	)

	it(
		"snapshots accepted tuning and returns detached projections with exact Light expiry",
		function()
			local state = newState()
			local tuning = table.clone(Effects.light_weaken)
			local raw = tuning :: any
			apply(state, 0, "fire_burn")
			CombatState.ClearEffects(state, 0)
			expect(CombatState.ApplyNegative(state, 0, "light_weaken", tuning)).toBe(true)
			raw.durationSeconds = 200
			raw.horizontalMultiplier = 0.1
			local snapshot = effect(state, 0)
			snapshot.expiresAt = 100
			snapshot.horizontalMultiplier = 0.2
			expect(CombatState.GetHorizontalMultiplier(state, 1)).toBe(0.8)
			expect(1.15 * CombatState.GetHorizontalMultiplier(state, 1)).toBeCloseTo(0.92, 10)
			expect(effect(state, 1).expiresAt).toBe(2)
			expect(CombatState.GetHorizontalMultiplier(state, 2)).toBe(1)
			local fire = newState()
			local burn = table.clone(Effects.fire_burn)
			expect(CombatState.ApplyNegative(fire, 0, "fire_burn", burn)).toBe(true)
			local rawBurn = burn :: any
			rawBurn.staminaPerSecond = 100
			rawBurn.durationSeconds = 100
			CombatState.Advance(fire, 2)
			expect(fire.stamina).toBe(90)
		end
	)

	it(
		"clears effects without refilling Stamina, resetting paid action timing, or reusing tokens",
		function()
			local state = newState()
			expect(CombatState.TryAttack(state, 0, ATTACK)).toBe(true)
			apply(state, 0, "fire_burn")
			local token = effect(state, 0).token
			CombatState.ClearEffects(state, 0.1)
			expect(state.stamina).toBe(79.5)
			expect(state.nextAttackAt).toBe(1)
			expect(state.swingEndsAt).toBe(0.5)
			expect(CombatState.GetEffect(state, 0.1)).toBeNil()
			expect(state.effectSequence).toBe(token)
			expect(CombatState.TryAttack(state, 0.2, ATTACK)).toBe(false)
			apply(state, 0.2, "water_slow")
			expect(effect(state, 0.2).token > token).toBe(true)
			CombatState.ClearEffects(state, 0.2)
			expect(CombatState.GetMovement(state, 0.2)).toEqual({
				walkSpeedMultiplier = 1,
				blockJump = false,
				blockRotation = false,
			})
		end
	)
end)
