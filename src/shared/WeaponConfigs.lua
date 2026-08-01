-- ReplicatedStorage/WeaponConfigs
-- Static weapon identity and balance. Poses and hitboxes are authored on each Model.

export type WeaponConfig = {
	ModelName: string,
	AttackCooldown: number,
	HitStartFallback: number,
	HitWindowDuration: number,
	Knockback: number,
	MaxTargets: number,
	StarterSlot: string?,
}

local WeaponConfigs: { [string]: WeaponConfig } = {
	WoodenSword = {
		ModelName = "WoodenSword",
		AttackCooldown = 0.72,
		HitStartFallback = 0.22,
		HitWindowDuration = 0.1,
		Knockback = 56,
		MaxTargets = 1,
		StarterSlot = "Right",
	},
	WoodenShield = {
		ModelName = "WoodenShield",
		AttackCooldown = 0.9,
		HitStartFallback = 0.22,
		HitWindowDuration = 0.1,
		Knockback = 38,
		MaxTargets = 1,
		StarterSlot = "Left",
	},
}

return table.freeze(WeaponConfigs)
