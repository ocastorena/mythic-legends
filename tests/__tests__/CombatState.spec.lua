--!strict
-- ServerStorage/Tests/__tests__/CombatState.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local CombatState =
	require(game:GetService("ServerScriptService").Services.CombatService.CombatState)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ATTACK = { cost = 20, cooldownSeconds = 1, durationSeconds = 0.5 }

local function newState(spawn: number?): CombatState.State
	return CombatState.New(0, {
		maximum = 100,
		spawn = spawn or 100,
		recoveryPerSecond = 10,
	})
end

local function shield(cost: number): CombatState.ShieldTuning
	return {
		cost = cost,
		minimum = cost,
		raiseSeconds = 0.25,
		raiseTimeoutSeconds = 1,
		lowerSeconds = 0.25,
		lowerTimeoutSeconds = 0.75,
	}
end

local function raise(
	state: CombatState.State,
	at: number,
	sequence: number,
	tuning: CombatState.ShieldTuning
)
	expect(CombatState.BeginGuard(state, at, sequence, tuning)).toBe(true)
	expect(CombatState.Marker(state, at + tuning.raiseSeconds, sequence, "Raised")).toBe(true)
	expect(state.protecting).toBe(true)
end

describe("CombatState Stamina accounting", function()
	it(
		"allows nine one-second sword starts, rejects second nine, and permits second ten",
		function()
			local state = newState()
			for second = 0, 8 do
				expect(CombatState.TryAttack(state, second, ATTACK)).toBe(true)
			end
			expect(state.stamina).toBe(0)
			expect(CombatState.TryAttack(state, 9, ATTACK)).toBe(false)
			expect(state.stamina).toBe(10)
			expect(CombatState.TryAttack(state, 10, ATTACK)).toBe(true)
			expect(state.stamina).toBe(0)
		end
	)

	it("recovers an attack in two lowered seconds and a full bar in ten", function()
		local attackState = newState(0)
		expect(CombatState.TryAttack(attackState, 1, ATTACK)).toBe(false)
		expect(CombatState.TryAttack(attackState, 2, ATTACK)).toBe(true)
		expect(attackState.stamina).toBe(0)
		local fullState = newState(0)
		CombatState.Advance(fullState, 10)
		expect(fullState.stamina).toBe(100)
		CombatState.Advance(fullState, 100)
		expect(fullState.stamina).toBe(100)
	end)

	it("recovers during attacks and charges every accepted swing before any hit", function()
		local state = newState()
		expect(CombatState.TryAttack(state, 0, ATTACK)).toBe(true)
		expect(state.stamina).toBe(80)
		CombatState.Advance(state, 0.25)
		expect(state.stamina).toBe(82.5)
		expect(CombatState.TryAttack(state, 0.25, ATTACK)).toBe(false)
		expect(state.stamina).toBe(82.5)
	end)

	it("never credits raising, guarding, or lowering time after the Shield is lowered", function()
		local state = newState(60)
		expect(CombatState.BeginGuard(state, 0, 1, shield(30))).toBe(true)
		expect(CombatState.Marker(state, 0, 1, "Raised")).toBe(true)
		CombatState.Advance(state, 0.125)
		expect(state.phase).toBe("Raising")
		expect(state.stamina).toBe(60)
		CombatState.Advance(state, 100)
		expect(state.phase).toBe("Guarding")
		expect(state.stamina).toBe(60)
		CombatState.ReleaseGuard(state, 100, 1, false)
		expect(CombatState.Marker(state, 100.125, 1, "Lowered")).toBe(true)
		expect(state.phase).toBe("Lowering")
		expect(state.stamina).toBe(60)
		CombatState.Advance(state, 100.25)
		expect(state.phase).toBe("Lowered")
		expect(state.stamina).toBe(60)
		CombatState.Advance(state, 100.75)
		expect(state.stamina).toBe(65)
	end)

	it("does not move accounting backwards or credit the same interval twice", function()
		local state = newState(0)
		CombatState.Advance(state, 2)
		CombatState.Advance(state, 1)
		CombatState.Advance(state, 2)
		expect(state.lastUpdatedAt).toBe(2)
		expect(state.stamina).toBe(20)
		CombatState.Advance(state, 3)
		expect(state.stamina).toBe(30)
	end)
end)

describe("CombatState Shield payments", function()
	it(
		"blocks three full-cost wooden hits and immediately removes protection on the third",
		function()
			local state = newState()
			raise(state, 0, 1, shield(30))
			for hit = 1, 3 do
				expect(CombatState.Block(state, hit)).toBe(true)
			end
			expect(state.stamina).toBe(10)
			expect(state.phase).toBe("Lowering")
			expect(state.protecting).toBe(false)
			expect(CombatState.Block(state, 3)).toBe(false)
			expect(state.stamina).toBe(10)
		end
	)

	it(
		"blocks four crafted hits with the same accounting and no independent block counter",
		function()
			local state = newState()
			raise(state, 0, 1, shield(25))
			for hit = 1, 4 do
				expect(CombatState.Block(state, hit)).toBe(true)
			end
			expect(state.stamina).toBe(0)
			expect(state.phase).toBe("Lowering")
			expect(state.protecting).toBe(false)
		end
	)

	it("rejects partial-Stamina guard and requires a fresh sequence after recovery", function()
		local state = newState(20)
		expect(CombatState.BeginGuard(state, 0, 1, shield(30))).toBe(false)
		expect(state.lastGuardSequence).toBe(1)
		expect(CombatState.BeginGuard(state, 1, 1, shield(30))).toBe(false)
		expect(state.stamina).toBe(30)
		raise(state, 1, 2, shield(30))
		expect(CombatState.Block(state, 2)).toBe(true)
		expect(state.stamina).toBe(0)
		expect(state.protecting).toBe(false)
	end)

	it("rechecks the full payment before blocking and never pays a partial block", function()
		local state = newState(30)
		raise(state, 0, 1, shield(30))
		-- Simulate an external authoritative Stamina change before incoming-hit resolution.
		state.stamina = 29
		expect(CombatState.Block(state, 1)).toBe(false)
		expect(state.stamina).toBe(29)
		expect(state.protecting).toBe(false)
		expect(state.phase).toBe("Lowering")
	end)

	it("snapshots Shield costs and transition timing for the accepted guard", function()
		local tuning = shield(30)
		local state = newState()
		expect(CombatState.BeginGuard(state, 0, 1, tuning)).toBe(true)
		tuning.cost = 1
		tuning.minimum = 1
		tuning.raiseSeconds = 0
		tuning.lowerTimeoutSeconds = 0
		expect(CombatState.Marker(state, 0, 1, "Raised")).toBe(true)
		expect(state.protecting).toBe(false)
		CombatState.Advance(state, 0.25)
		expect(CombatState.Block(state, 1)).toBe(true)
		expect(state.stamina).toBe(70)
		CombatState.ReleaseGuard(state, 1, nil, true)
		CombatState.Advance(state, 1.5)
		expect(state.phase).toBe("Lowering")
	end)

	it("rejects invalid guard thresholds without spending Stamina", function()
		local state = newState()
		local tuning = shield(30)
		tuning.minimum = 29
		expect(CombatState.BeginGuard(state, 0, 1, tuning)).toBe(false)
		tuning.minimum = 101
		expect(CombatState.BeginGuard(state, 0, 2, tuning)).toBe(false)
		tuning.minimum = 0
		tuning.cost = 0
		expect(CombatState.BeginGuard(state, 0, 3, tuning)).toBe(false)
		expect(state.stamina).toBe(100)
		expect(state.phase).toBe("Lowered")
	end)
end)

describe("CombatState action exclusion and cleanup", function()
	it("keeps the complete swing lock independent of cooldown or hit authorization", function()
		local state = newState()
		local longSwing = { cost = 20, cooldownSeconds = 1, durationSeconds = 2 }
		expect(CombatState.TryAttack(state, 0, longSwing)).toBe(true)
		expect(CombatState.TryAttack(state, 1, ATTACK)).toBe(false)
		expect(CombatState.BeginGuard(state, 1, 1, shield(30))).toBe(false)
		expect(state.swingEndsAt).toBe(2)
		expect(state.nextAttackAt).toBe(1)
		expect(CombatState.BeginGuard(state, 2, 1, shield(30))).toBe(false)
		expect(CombatState.BeginGuard(state, 2, 2, shield(30))).toBe(true)
	end)

	it("rejects attacks throughout raising, guarding, and unprotected lowering", function()
		local state = newState()
		expect(CombatState.BeginGuard(state, 0, 1, shield(30))).toBe(true)
		expect(CombatState.TryAttack(state, 0.125, ATTACK)).toBe(false)
		expect(CombatState.Marker(state, 0.25, 1, "Raised")).toBe(true)
		expect(CombatState.TryAttack(state, 1, ATTACK)).toBe(false)
		CombatState.ReleaseGuard(state, 1, nil, true)
		expect(state.protecting).toBe(false)
		expect(CombatState.TryAttack(state, 1.5, ATTACK)).toBe(false)
		expect(state.stamina).toBe(100)
		expect(CombatState.TryAttack(state, 1.75, ATTACK)).toBe(true)
	end)

	it("normal release retains protection until the lower marker's minimum time", function()
		local state = newState()
		raise(state, 0, 1, shield(30))
		CombatState.ReleaseGuard(state, 1, 1, false)
		expect(state.protecting).toBe(true)
		expect(CombatState.Marker(state, 1, 1, "Lowered")).toBe(true)
		CombatState.Advance(state, 1.125)
		expect(state.protecting).toBe(true)
		expect(CombatState.Block(state, 1.125)).toBe(true)
		CombatState.Advance(state, 1.25)
		expect(state.phase).toBe("Lowered")
		expect(state.protecting).toBe(false)
		expect(state.stamina).toBe(70)
	end)

	it(
		"bounds a missing raise marker and credits only time after both cleanup deadlines",
		function()
			local state = newState(30)
			expect(CombatState.BeginGuard(state, 0, 1, shield(30))).toBe(true)
			CombatState.Advance(state, 4)
			expect(state.phase).toBe("Lowered")
			expect(state.protecting).toBe(false)
			expect(state.stamina).toBe(52.5)
			expect(CombatState.Marker(state, 4, 1, "Raised")).toBe(false)
		end
	)

	it("bounds a missing lower marker and recovers immediately after its deadline", function()
		local state = newState(60)
		raise(state, 0, 1, shield(30))
		CombatState.ReleaseGuard(state, 1, 1, false)
		CombatState.Advance(state, 3)
		expect(state.phase).toBe("Lowered")
		expect(state.stamina).toBe(72.5)
	end)

	it(
		"queues an early raise marker and rejects stale markers and stale release requests",
		function()
			local state = newState()
			expect(CombatState.BeginGuard(state, 0, 2, shield(30))).toBe(true)
			expect(CombatState.Marker(state, 0, 1, "Raised")).toBe(false)
			expect(CombatState.Marker(state, 0, 2, "Lowered")).toBe(false)
			expect(CombatState.Marker(state, 0, 2, "Raised")).toBe(true)
			CombatState.ReleaseGuard(state, 0.125, 1, false)
			expect(state.phase).toBe("Raising")
			expect(state.protecting).toBe(false)
			CombatState.Advance(state, 0.25)
			expect(state.phase).toBe("Guarding")
			expect(state.protecting).toBe(true)
		end
	)

	it("does not let a late raise marker resurrect guard after its timeout", function()
		local state = newState()
		expect(CombatState.BeginGuard(state, 0, 1, shield(30))).toBe(true)
		expect(CombatState.Marker(state, 1, 1, "Raised")).toBe(false)
		expect(state.phase).toBe("Lowering")
		expect(state.protecting).toBe(false)
	end)

	it("does not restart or shorten lowering on repeated Arena or Equipment cleanup", function()
		local state = newState(60)
		raise(state, 0, 1, shield(30))
		CombatState.ReleaseGuard(state, 1, 1, false)
		CombatState.ReleaseGuard(state, 1.125, nil, true)
		expect(state.protecting).toBe(false)
		expect(state.phaseStartedAt).toBe(1)
		CombatState.ReleaseGuard(state, 1.5, nil, true)
		expect(state.phase).toBe("Lowering")
		expect(state.phaseStartedAt).toBe(1)
		CombatState.Advance(state, 1.75)
		expect(state.phase).toBe("Lowered")
		expect(state.stamina).toBe(60)
		CombatState.Advance(state, 2)
		expect(state.stamina).toBe(62.5)
	end)

	it("preserves paid attack timing and Stamina during Equipment or Arena cleanup", function()
		local state = newState()
		expect(CombatState.TryAttack(state, 0, ATTACK)).toBe(true)
		CombatState.ReleaseGuard(state, 0.125, nil, true)
		expect(state.stamina).toBe(81.25)
		expect(state.swingEndsAt).toBe(0.5)
		expect(state.nextAttackAt).toBe(1)
		expect(CombatState.BeginGuard(state, 0.25, 1, shield(30))).toBe(false)
		expect(CombatState.TryAttack(state, 0.75, ATTACK)).toBe(false)
		expect(CombatState.TryAttack(state, 1, ATTACK)).toBe(true)
	end)

	it("requires a fresh guard after depletion without restoring a block allowance", function()
		local state = newState()
		raise(state, 0, 1, shield(30))
		for hit = 1, 3 do
			expect(CombatState.Block(state, hit)).toBe(true)
		end
		CombatState.Advance(state, 5.75)
		expect(state.stamina).toBe(30)
		expect(CombatState.BeginGuard(state, 5.75, 1, shield(30))).toBe(false)
		raise(state, 5.75, 2, shield(30))
		expect(CombatState.Block(state, 6)).toBe(true)
		expect(state.stamina).toBe(0)
		expect(state.protecting).toBe(false)
	end)
end)
