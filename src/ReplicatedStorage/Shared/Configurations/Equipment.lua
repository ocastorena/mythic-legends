--!strict
-- ReplicatedStorage/Shared/Configurations/Equipment

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)
-- Canonical static metadata for Model-based Arena combat equipment.

-- Client fallbacks and the prototype wooden profiles share one set of tuning values.
local PRESENTATION_DEFAULTS = {
	cooldownSeconds = 1,
	swingDurationSeconds = 0.72,
	raiseSeconds = 0.2,
	raiseTimeoutSeconds = 0.8,
	lowerSeconds = 0.2,
	lowerTimeoutSeconds = 0.8,
	hitStartFallbackSeconds = 0.22,
	contactWindowSeconds = 0.22,
	slideDurationSeconds = 0.32,
	launchControlSeconds = 0.1,
	maximumReactionSeconds = 3.5,
	landingRecoverySeconds = 0.2,
	shieldSlideFullSpeedFraction = 0.55,
}

local Equipment: Types.EquipmentConfiguration = {
	presentationDefaults = PRESENTATION_DEFAULTS,
	combat = {
		staminaMaximum = 100,
		staminaSpawn = 100,
		staminaRegenPerSecond = 10,
		knockbackImmunitySeconds = 0.65,
		arenaHeightAllowanceStuds = 20,
	},

	profiles = {
		wooden_sword = {
			displayName = "Wooden Sword",
			description = "A dependable starter sword for non-lethal Arena knockback.",
			rarity = "Common",
			kind = "PrimaryWeapon",
			modelName = "WoodenSword",
			thumbnail = "",

			staminaCost = 20,
			cooldownSeconds = PRESENTATION_DEFAULTS.cooldownSeconds,
			swingDurationSeconds = PRESENTATION_DEFAULTS.swingDurationSeconds,
			animationId = "rbxassetid://126682224103556",
			hitStartFallbackSeconds = PRESENTATION_DEFAULTS.hitStartFallbackSeconds,
			contactWindowSeconds = PRESENTATION_DEFAULTS.contactWindowSeconds,
			hitStopSeconds = 0.045,
			reachStuds = 5.25,
			serverToleranceStuds = 6,
			requireLineOfSight = true,
			planarKnockback = 56,
			verticalKnockback = 58,
			tumbleAngularSpeed = 5.5,
			launchControlSeconds = PRESENTATION_DEFAULTS.launchControlSeconds,
			maximumReactionSeconds = PRESENTATION_DEFAULTS.maximumReactionSeconds,
			landingRecoverySeconds = PRESENTATION_DEFAULTS.landingRecoverySeconds,
			airTrailSeconds = 3.5,
			impactSoundId = "rbxassetid://7171761940",
		},

		wooden_shield = {
			displayName = "Wooden Shield",
			description = "A sturdy starter shield that trades Stamina for protection.",
			rarity = "Common",
			kind = "Shield",
			modelName = "WoodenShield",
			thumbnail = "",

			impactStaminaCost = 30,
			minimumGuardStamina = 30,
			raiseSeconds = PRESENTATION_DEFAULTS.raiseSeconds,
			raiseTimeoutSeconds = PRESENTATION_DEFAULTS.raiseTimeoutSeconds,
			lowerSeconds = PRESENTATION_DEFAULTS.lowerSeconds,
			lowerTimeoutSeconds = PRESENTATION_DEFAULTS.lowerTimeoutSeconds,
			blockArcDegrees = 360,
			slideKnockback = 40,
			slideDurationSeconds = PRESENTATION_DEFAULTS.slideDurationSeconds,
			raiseAnimationId = "rbxassetid://14022926289",
			holdAnimationId = "rbxassetid://13382364012",
			lowerAnimationId = "rbxassetid://13382274130",
		},
	},
}

return FreezeUtil.DeepFreeze(Equipment)
