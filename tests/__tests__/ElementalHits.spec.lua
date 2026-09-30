--!strict
-- ServerStorage/Tests/__tests__/ElementalHits.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local Effects = require(ReplicatedStorage.Shared.Configurations.ElementalSwordEffects)
local CombatState = require(ServerScriptService.Services.CombatService.CombatState)
local ElementalHits = require(ServerScriptService.Services.CombatService.ElementalHits)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function state()
	return CombatState.New(0, { maximum = 100, spawn = 100, recoveryPerSecond = 10 })
end

describe("ElementalHits", function()
	it(
		"resolves each named sword effect identically without acquisition-route or owned stat inputs",
		function()
			local kinds: { [string]: string } =
				{ fire = "Burn", water = "Slow", earth = "Root", light = "Weaken" }
			for finishId, expected in kinds do
				local item = assert(
					EquipmentCatalog.Resolve("elemental_sword", finishId),
					"[ElementalHits.spec] Expected named sword"
				)
				local attacker, target = state(), state()
				expect(ElementalHits.ApplyAcceptedHit(attacker, target, 0, item.effectId, false)).toBe(
					1
				)
				local effect =
					assert(CombatState.GetEffect(target, 0), "[ElementalHits.spec] Expected effect")
				expect(effect.kind).toBe(expected)
				expect(effect.effectId).toBe(item.effectId)
			end
		end
	)

	it(
		"keeps Shield slides unscaled and prevents every new effect/refund on paid blocks",
		function()
			for id in Effects do
				local attacker, target = state(), state()
				attacker.stamina = 80
				CombatState.ApplyNegative(attacker, 0, "light_weaken", Effects.light_weaken)
				CombatState.ApplyNegative(target, 0, "fire_burn", Effects.fire_burn)
				local retained = CombatState.GetEffect(target, 0)
				expect(ElementalHits.ApplyAcceptedHit(attacker, target, 0, id, true)).toBe(1)
				expect(attacker.stamina).toBe(80)
				expect(CombatState.GetEffect(target, 0)).toEqual(retained)
			end
		end
	)

	it(
		"applies Air before outgoing Light while leaving the target's existing timed effect intact",
		function()
			local attacker, target = state(), state()
			CombatState.ApplyNegative(attacker, 0, "light_weaken", Effects.light_weaken)
			CombatState.ApplyNegative(target, 0, "water_slow", Effects.water_slow)
			local retained = CombatState.GetEffect(target, 0)
			expect(ElementalHits.ApplyAcceptedHit(attacker, target, 0, "air_knockback", false)).toBeCloseTo(
				0.92,
				10
			)
			expect(CombatState.GetEffect(target, 0)).toEqual(retained)
			expect(ElementalHits.ApplyAcceptedHit(attacker, target, 0, nil, false)).toBe(0.8)
			expect(ElementalHits.ApplyAcceptedHit(attacker, target, 2, "air_knockback", false)).toBe(
				1.15
			)
		end
	)

	it(
		"charges full swing Stamina before a capped Dark refund even against an affected target",
		function()
			local attacker, target = state(), state()
			attacker.stamina = 19
			expect(
				CombatState.TryAttack(
					attacker,
					0,
					{ cost = 20, cooldownSeconds = 1, durationSeconds = 0.72 }
				)
			).toBe(false)
			attacker.stamina = 20
			expect(
				CombatState.TryAttack(
					attacker,
					0,
					{ cost = 20, cooldownSeconds = 1, durationSeconds = 0.72 }
				)
			).toBe(true)
			CombatState.ApplyNegative(target, 0, "earth_root", Effects.earth_root)
			expect(ElementalHits.ApplyAcceptedHit(attacker, target, 0, "dark_refund", false)).toBe(
				1
			)
			expect(attacker.stamina).toBe(3)
			expect(attacker.nextAttackAt).toBe(1)
			expect(attacker.swingEndsAt).toBe(0.72)
			expect((CombatState.GetEffect(target, 0) :: CombatState.NegativeEffect).phase).toBe(
				"Pending"
			)
			attacker.stamina = 99
			ElementalHits.ApplyAcceptedHit(attacker, target, 0, "dark_refund", false)
			expect(attacker.stamina).toBe(100)
		end
	)

	it(
		"ignores later timed effects without extending deadlines and leaves plain wooden hits effect-free",
		function()
			local attacker, target = state(), state()
			ElementalHits.ApplyAcceptedHit(attacker, target, 0, "fire_burn", false)
			local retained = CombatState.GetEffect(target, 0)
			ElementalHits.ApplyAcceptedHit(attacker, target, 1, "earth_root", false)
			expect(CombatState.GetEffect(target, 1)).toEqual(retained)
			expect(target.stamina).toBe(95)
			ElementalHits.ApplyAcceptedHit(attacker, target, 2, nil, false)
			expect(CombatState.GetEffect(target, 2)).toBeNil()
			expect(target.stamina).toBe(90)
		end
	)
end)
