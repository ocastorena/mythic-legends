-- ReplicatedStorage/Metadata/Weapons
local Weapons = {
	Combat = {
		stamina = {
			maximum = 100,
			regenPerSecond = 18,
		},
		knockbackImmunitySeconds = 0.65,
	},

	-- Prefer WeaponId = "wooden_sword" on authored Tools. These aliases preserve the
	-- temporary presentation asset and common display-name variants during migration.
	ToolAliases = {
		bat = "wooden_sword",
		woodenshield = "wooden_shield",
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
			staminaCost = 20,

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

		wooden_shield = {
			displayName = "Wooden Shield",
			rarity = "Common",
			thumbnail = "",
			description = "A sturdy starter shield. Toggle it to brace in place, absorb a hit, and slide back a short distance.",
			combatKind = "Shield",
			weaponFamily = "Shield",
			arenaOnly = true,
			arenaHeightAllowanceStuds = 12,

			shield = {
				toggleCooldownSeconds = 0.2,
				depletedCooldownSeconds = 0.5,
				impactStaminaCost = 30,
				-- Blocking covers a narrow frontal cone; side and rear swings bypass it.
				blockArcDegrees = 110,
				slidePlanarDeltaV = 28,
				slideControlSeconds = 0.1,

				pose = {
					blendSeconds = 0.08,
					ikSmoothTime = 0.04,
					-- Targets and poles are relative to HumanoidRootPart.
					passiveHandTarget = CFrame.new(1.35, -0.65, 0.1),
					passiveElbowPole = CFrame.new(2.4, 0.2, -0.2),
					passiveGripOffset = CFrame.Angles(math.rad(-90), math.rad(180), math.rad(180))
						* CFrame.Angles(math.rad(-20), 0, 0),

					-- Flip around the grip axis in guard so the shield's authored top is
					-- vertical while the arm IK keeps it positioned in front of the body.
					guardGripOffset = CFrame.Angles(math.rad(180), 0, 0),
					guardHandTarget = CFrame.new(0.7, 0.05, -1.05)
						* CFrame.Angles(math.rad(-180), math.rad(-105), 0),
					guardElbowPole = CFrame.new(1.8, 0.35, -0.65),

					-- The right leg plants forward with its shin upright. The left foot
					-- reaches behind the body so its knee can settle onto the floor.
					frontFootTarget = CFrame.new(0.55, -2.7, -0.9),
					frontKneePole = CFrame.new(0.7, -1.3, -2),
					kneelingFootTarget = CFrame.new(-0.55, -2.6, 1.45),
					kneelingKneePole = CFrame.new(-0.7, -3, -0.45),

					-- The root moves visually while leg IK creates the kneeling stance.
					-- Humanoid.HipHeight stays unchanged, so the avatar does not sink
					-- into the arena or alter its physical ground clearance.
					crouchRootOffset = CFrame.new(0, -0.78, 0)
						* CFrame.Angles(math.rad(-5), 0, 0),
				},
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

function Weapons.IsShieldTool(tool: Tool): boolean
	local _, profile = Weapons.GetProfile(tool)
	return profile ~= nil and profile.combatKind == "Shield"
end

function Weapons.IsCombatTool(tool: Tool): boolean
	local _, profile = Weapons.GetProfile(tool)
	return profile ~= nil and (profile.combatKind == "Melee" or profile.combatKind == "Shield")
end

return Weapons
