--!strict
-- ReplicatedStorage/Shared/Configurations/Equipment

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)
local ElementalSwordEffects = require(script.Parent.ElementalSwordEffects)
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
			equipmentType = "Sword",
			handsRequired = 1,
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
			equipmentType = "Shield",
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
	definitions = {},
}

-- Existing combat consumers still see only the wooden profiles. The complete catalogue is
-- separate until finish-aware combat and authored crafted models are integrated deliberately.
-- These objects add static classification to the same wooden profiles, not replacement copies.
local woodenSword = Equipment.profiles.wooden_sword :: Types.EquipmentDefinition
local woodenShield = Equipment.profiles.wooden_shield :: Types.EquipmentDefinition
local elementalSword: Types.EquipmentDefinition = table.clone(woodenSword)
elementalSword.displayName = "Elemental Sword"
elementalSword.description = "A crafted one-handed sword with a fixed elemental effect."
elementalSword.rarity = "Rare"
elementalSword.stage = 1
elementalSword.modelName = ""
elementalSword.thumbnail = ""
elementalSword.sale = { gold = 25 }
elementalSword.finishes = {
	fire = {
		displayName = "Vulcan Sword",
		description = ElementalSwordEffects.fire_burn.description,
		rarity = "Rare",
		element = "Fire",
		effectId = "fire_burn",
	},
	water = {
		displayName = "Triton Sword",
		description = ElementalSwordEffects.water_slow.description,
		rarity = "Rare",
		element = "Water",
		effectId = "water_slow",
	},
	earth = {
		displayName = "Atlas Sword",
		description = ElementalSwordEffects.earth_root.description,
		rarity = "Rare",
		element = "Earth",
		effectId = "earth_root",
	},
	air = {
		displayName = "Aura Sword",
		description = ElementalSwordEffects.air_knockback.description,
		rarity = "Rare",
		element = "Air",
		effectId = "air_knockback",
	},
	light = {
		displayName = "Sol Sword",
		description = ElementalSwordEffects.light_weaken.description,
		rarity = "Rare",
		element = "Light",
		effectId = "light_weaken",
	},
	dark = {
		displayName = "Nyx Sword",
		description = ElementalSwordEffects.dark_refund.description,
		rarity = "Rare",
		element = "Dark",
		effectId = "dark_refund",
	},
}

local elementalShield: Types.EquipmentDefinition = table.clone(woodenShield)
elementalShield.displayName = "Elemental Shield"
elementalShield.description = "A crafted Shield with improved Stamina efficiency."
elementalShield.rarity = "Rare"
elementalShield.stage = 1
elementalShield.modelName = ""
elementalShield.thumbnail = ""
elementalShield.sale = { gold = 25 }
elementalShield.impactStaminaCost = 25
elementalShield.minimumGuardStamina = 25
elementalShield.finishes = {
	fire = {
		displayName = "Vulcan Shield",
		description = elementalShield.description,
		rarity = "Rare",
		element = "Fire",
	},
	water = {
		displayName = "Triton Shield",
		description = elementalShield.description,
		rarity = "Rare",
		element = "Water",
	},
	earth = {
		displayName = "Atlas Shield",
		description = elementalShield.description,
		rarity = "Rare",
		element = "Earth",
	},
	air = {
		displayName = "Aura Shield",
		description = elementalShield.description,
		rarity = "Rare",
		element = "Air",
	},
	light = {
		displayName = "Sol Shield",
		description = elementalShield.description,
		rarity = "Rare",
		element = "Light",
	},
	dark = {
		displayName = "Nyx Shield",
		description = elementalShield.description,
		rarity = "Rare",
		element = "Dark",
	},
}

Equipment.definitions.wooden_sword = woodenSword
Equipment.definitions.wooden_shield = woodenShield
Equipment.definitions.elemental_sword = elementalSword
Equipment.definitions.elemental_shield = elementalShield

return FreezeUtil.DeepFreeze(Equipment)
