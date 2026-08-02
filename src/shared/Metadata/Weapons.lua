-- ReplicatedStorage/Metadata/Weapons
-- Canonical static metadata for Model-based Arena combat equipment.

local Weapons = {
	Combat = {
		staminaMaximum = 100,
		staminaRegenPerSecond = 18,
		knockbackImmunitySeconds = 0.65,
		arenaHeightAllowanceStuds = 20,
	},

	Profiles = {
		wooden_sword = {
			displayName = "Wooden Sword",
			description = "A dependable starter sword for non-lethal Arena knockback.",
			rarity = "Common",
			kind = "PrimaryWeapon",
			modelName = "WoodenSword",
			thumbnail = "",

			staminaCost = 20,
			cooldownSeconds = 0.72,
			animationId = "rbxassetid://126682224103556",
			hitStartFallbackSeconds = 0.22,
			contactWindowSeconds = 0.22,
			hitStopSeconds = 0.045,
			reachStuds = 5.25,
			serverToleranceStuds = 6,
			requireLineOfSight = true,
			planarKnockback = 56,
			verticalKnockback = 58,
			tumbleAngularSpeed = 5.5,
			launchControlSeconds = 0.1,
			maximumReactionSeconds = 3.5,
			landingRecoverySeconds = 0.2,
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

			activationCooldownSeconds = 0.2,
			impactStaminaCost = 30,
			blockArcDegrees = 360,
			slideKnockback = 40,
			slideDurationSeconds = 0.32,
			raiseAnimationId = "rbxassetid://14022926289",
			holdAnimationId = "rbxassetid://13382364012",
			lowerAnimationId = "rbxassetid://13382274130",
		},
	},
}

return table.freeze(Weapons)
