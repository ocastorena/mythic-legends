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
				animationId = "rbxassetid://126682224103556",
				animationSpeed = 2,
				activeWindowSeconds = 0.22,
				hitStopSeconds = 0.045,
			},

			target = {
				maxTargets = 1,
				-- The client uses the authored blade geometry. Reach is only a loose server
				-- sanity check, with enough tolerance for normal live-server replication delay.
				reachStuds = 5.25,
				serverToleranceStuds = 6,
				requireLineOfSight = true,
			},

			impact = {
				-- Light swords use a rigid launch/air-tumble instead of splitting the
				-- avatar into a floor-bouncing multi-body ragdoll.
				reactionMode = "Knockdown",
				tumbleAngularSpeed = 5.5,
				-- The target's owning client eases toward this launch velocity.
				launchControlSeconds = 0.1,
				-- This is a compact starter-sword pop: enough vertical lift to clearly
				-- leave the ground, without turning one hit into an arena clear.
				planarDeltaV = 56,
				verticalDeltaV = 58,
				-- The ragdoll normally ends half a second after a confirmed landing. This
				-- maximum is only a failsafe for a player who misses the arena entirely.
				ragdollMaxSeconds = 3.5,
				ragdollLandingRecoverySeconds = 0.2,
			},

			vfx = {
				-- Presentation values only. Hit confirmation and physics remain server-owned.
				hitBurstParticles = 26,
				impactSound = {
					-- Creator Store: "Sword Hit (Impact)" by BushSeed.
					id = "rbxassetid://7171761940",
					volume = 0.65,
					-- Skip the asset's quiet lead-in so the transient lands with the burst.
					startTimeSeconds = 0.06,
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
