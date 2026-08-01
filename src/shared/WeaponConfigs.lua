-- ReplicatedStorage/WeaponConfigs
-- Static weapon identity and balance. Poses and hitboxes are authored on each Model.

export type WeaponConfig = {
	ModelName: string,
	AttackCooldown: number,
	Knockback: number,
	MaxTargets: number,
	StarterSlot: string?,
}

local WeaponConfigs: { [string]: WeaponConfig } = {
	WoodenSword = {
		ModelName = "WoodenSword",
		AttackCooldown = 0.72,
		Knockback = 56,
		MaxTargets = 1,
		StarterSlot = "Right",
	},
	WoodenShield = {
		ModelName = "WoodenShield",
		AttackCooldown = 0.9,
		Knockback = 38,
		MaxTargets = 1,
		StarterSlot = "Left",
	},
}

return table.freeze(WeaponConfigs)
