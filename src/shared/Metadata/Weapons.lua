-- ReplicatedStorage/Metadata/Weapons
local Weapons = {
	-- Prefer WeaponId = "wooden_sword" on authored Tools. These aliases preserve the
	-- temporary presentation asset and common display-name variants during migration.
	ToolAliases = {
		bat = "wooden_sword",
		woodensword = "wooden_sword",
	},

	Profiles = {
		wooden_sword = {
			displayName = "Wooden Sword",
			rarity = "Common",
			thumbnail = "",
			description = "A dependable training sword built for close-range arena combat. Its light frame delivers a sharp burst of knockback without dealing lethal damage.",
			combatKind = "Melee",
			weaponFamily = "Sword",
			arenaOnly = true,
			arenaHeightAllowanceStuds = 12,

			swing = {
				cooldownSeconds = 0.72,
				impactDelaySeconds = 0.12,
			},

			target = {
				maxTargets = 1,
				-- A deliberately tight forward sector: close to the temporary placeholder's authored
				-- 2 x 2 x 3 contact volume, with only a small server-side forgiveness margin.
				reachStuds = 5.25,
				arcDegrees = 90,
				maxVerticalDifference = 4,
				requireLineOfSight = true,
			},

			impact = {
				-- Velocity changes, not raw physical force. The server mass-scales this
				-- before applying it so every character receives the intended launch.
				-- This is a compact starter-sword pop: enough vertical lift to clearly
				-- leave the ground, without turning one hit into an arena clear.
				planarDeltaV = 56,
				verticalDeltaV = 58,
				-- The ragdoll normally ends half a second after a confirmed landing. This
				-- maximum is only a failsafe for a player who misses the arena entirely.
				ragdollMaxSeconds = 3.5,
				ragdollLandingRecoverySeconds = 0.5,
				hitImmunitySeconds = 1.1,
				serverOwnershipSeconds = 0.8,
			},

			vfx = {
				-- Presentation values only. Hit confirmation and physics remain server-owned.
				hitBurstParticles = 26,
				impactSound = {
					-- Creator Store: "Sword Hit (Impact)" by BushSeed.
					id = "rbxassetid://7171761940",
					volume = 0.65,
					minDistance = 7,
					maxDistance = 60,
				},
				-- The client emits these by distance travelled, so the smoke forms a
				-- real path behind an airborne ragdoll instead of a cloud around it.
				airTrailParticlesPerStud = 1.15,
				airTrailSeconds = 3.5,
				airTrailBurstParticles = 8,
			},
		},
	},
}

local function normalizeId(value: string): string
	local normalized = string.lower(value)
	normalized = string.gsub(normalized, "[^%w]+", "_")
	normalized = string.gsub(normalized, "^_+", "")
	normalized = string.gsub(normalized, "_+$", "")
	return normalized
end

function Weapons.GetId(tool: Tool): string?
	local configuredId = tool:GetAttribute("WeaponId")
	local rawId = if type(configuredId) == "string" and configuredId ~= "" then configuredId else tool.Name
	local normalizedId = normalizeId(rawId)
	if normalizedId == "" then
		return nil
	end

	local alias = Weapons.ToolAliases[normalizedId]
	if type(alias) == "string" then
		local normalizedAlias = normalizeId(alias)
		return normalizedAlias ~= "" and normalizedAlias or nil
	end

	return normalizedId
end

function Weapons.GetProfile(tool: Tool): (string?, any?)
	local weaponId = Weapons.GetId(tool)
	return weaponId, weaponId and Weapons.Profiles[weaponId] or nil
end

function Weapons.IsMeleeTool(tool: Tool): boolean
	local _, profile = Weapons.GetProfile(tool)
	return profile ~= nil and profile.combatKind == "Melee"
end

return Weapons
