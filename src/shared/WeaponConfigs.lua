-- ReplicatedStorage/WeaponConfigs
-- Static weapon presentation and balance. Add a matching Model under WeaponAssets.

export type WeaponConfig = {
	ModelName: string,
	HandGripOffset: CFrame,
	SheathOffset: CFrame,
	HitboxSize: Vector3,
	AttackCooldown: number,
	Knockback: number,
	MaxTargets: number,
}

local WeaponConfigs: { [string]: WeaponConfig } = {
	WoodenSword = {
		ModelName = "WoodenSword",
		-- C1 is the weapon-space offset used by the Motor6D.
		HandGripOffset = CFrame.Angles(0, 0, math.rad(90)),
		SheathOffset = CFrame.new(0.9, 0.1, 0.45) * CFrame.Angles(0, 0, math.rad(35)),
		HitboxSize = Vector3.new(0.8, 4.5, 1.2),
		AttackCooldown = 0.72,
		Knockback = 56,
		MaxTargets = 1,
	},
	WoodenShield = {
		ModelName = "WoodenShield",
		HandGripOffset = CFrame.new(0, -0.1, 0.15) * CFrame.Angles(0, math.rad(90), 0),
		SheathOffset = CFrame.new(-0.9, 0, 0.55) * CFrame.Angles(0, math.rad(180), 0),
		HitboxSize = Vector3.new(2.5, 3, 0.8),
		AttackCooldown = 0.9,
		Knockback = 38,
		MaxTargets = 1,
	},
}

return table.freeze(WeaponConfigs)
