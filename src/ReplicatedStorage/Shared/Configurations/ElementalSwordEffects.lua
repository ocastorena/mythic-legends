--!strict
-- ReplicatedStorage/Shared/Configurations/ElementalSwordEffects
-- Approved automatic sword effects. These definitions alone do not activate combat effects.

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)

local ElementalSwordEffects: { [string]: Types.ElementalSwordEffect } = {
	fire_burn = {
		element = "Fire",
		kind = "Burn",
		description = "On an unblocked hit, burns the opponent's Stamina over time.",
		staminaPerSecond = 15,
		durationSeconds = 2,
	},
	water_slow = {
		element = "Water",
		kind = "Slow",
		description = "On an unblocked hit, briefly slows the opponent's walking.",
		walkSpeedMultiplier = 0.75,
		durationSeconds = 2,
	},
	earth_root = {
		element = "Earth",
		kind = "Root",
		description = "On an unblocked hit, briefly prevents walking and jumping after the opponent lands. Knockback, attacking, and guarding remain possible.",
		rootSeconds = 0.75,
		landingTimeoutSeconds = 3,
		recoverySeconds = 3,
	},
	air_knockback = {
		element = "Air",
		kind = "Push",
		description = "Adds horizontal knockback to the same unblocked hit, without increasing upward launch.",
		horizontalMultiplier = 1.15,
	},
	light_weaken = {
		element = "Light",
		kind = "Weaken",
		description = "On an unblocked hit, briefly reduces the opponent's outgoing horizontal weapon knockback.",
		horizontalMultiplier = 0.8,
		durationSeconds = 2,
	},
	dark_refund = {
		element = "Dark",
		kind = "Refund",
		description = "Returns a little Stamina after an unblocked hit, up to maximum. The full attack cost is still required upfront.",
		stamina = 3,
	},
}

return FreezeUtil.DeepFreeze(ElementalSwordEffects)
