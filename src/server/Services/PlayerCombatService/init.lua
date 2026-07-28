-- ServerScriptService/Services/PlayerCombatService
-- Owns non-lethal melee combat. Clients request a swing only; this service validates the
-- equipped profile, resolves targets, and applies the resulting positional impact.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local KnockbackUtil = require(script.KnockbackUtil)
local RagdollUtil = require(script.RagdollUtil)

local log = LogUtil.For("PlayerCombatService")

local WeaponsData = nil
local CombatEvent = nil
local CombatVfxEvent = nil
local Arena: BasePart? = nil

-- userId -> timestamp. Swing cooldown, recovery, and immunity are deliberately separate:
-- a player cannot swing while their short server-owned knockback is resolving, but remains
-- protected for a little longer so simultaneous attackers cannot chain-launch them.
local nextSwingAt: { [number]: number } = {}
local recoveryUntil: { [number]: number } = {}
local hitImmuneUntil: { [number]: number } = {}
local activeAttacks: { [number]: any } = {}
local nextAttackId = 0

local EPSILON = 0.001

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return nil, nil, nil
	end

	return character, humanoid, root
end

local function isInsideArena(position: Vector3, heightAllowanceStuds: number?): boolean
	if not Arena then
		return false
	end

	local localPosition = Arena.CFrame:PointToObjectSpace(position)
	local radius = math.max(Arena.Size.X, Arena.Size.Z) * 0.5
	local horizontalDistance = Vector2.new(localPosition.X, localPosition.Z).Magnitude
	local heightAllowance = type(heightAllowanceStuds) == "number" and math.max(0, heightAllowanceStuds) or 0
	return horizontalDistance <= radius
		and math.abs(localPosition.Y) <= Arena.Size.Y * 0.5 + heightAllowance
end

local function getPlanarDirection(vector: Vector3, fallback: Vector3): Vector3
	local planar = Vector3.new(vector.X, 0, vector.Z)
	return if planar.Magnitude > EPSILON then planar.Unit else fallback
end

local function getEquippedMeleeTool(character: Model): (Tool?, string?, any?)
	local equippedTool: Tool? = nil
	local weaponId: string? = nil
	local profile = nil

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local candidateId, candidateProfile = WeaponsData.GetProfile(child)
			if candidateProfile and candidateProfile.combatKind == "Melee" then
				-- Roblox normally allows one equipped tool. Reject ambiguous manipulated states
				-- instead of letting child order decide which profile the player can use.
				if equippedTool then
					return nil, nil, nil
				end

				equippedTool = child
				weaponId = candidateId
				profile = candidateProfile
			end
		end
	end

	return equippedTool, weaponId, profile
end

local function hasLineOfSight(attackerCharacter: Model, targetCharacter: Model, attackerRoot: BasePart, targetRoot: BasePart): boolean
	local origin = attackerRoot.Position + Vector3.yAxis * 1.5
	local destination = targetRoot.Position + Vector3.yAxis * 1.5
	local direction = destination - origin
	if direction.Magnitude <= EPSILON then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	params.IgnoreWater = true

	local obstruction = workspace:Raycast(origin, direction, params)
	return obstruction == nil or obstruction.Instance:IsDescendantOf(targetCharacter)
end

local function findTargets(attacker: Player, attackerCharacter: Model, attackerRoot: BasePart, profile: any): { Player }
	local targetConfig = profile.target
	local forward = getPlanarDirection(attackerRoot.CFrame.LookVector, Vector3.new(0, 0, -1))
	local minimumForwardDot = math.cos(math.rad(targetConfig.arcDegrees * 0.5))
	local candidates = {}

	for _, target in ipairs(Players:GetPlayers()) do
		if target ~= attacker and (hitImmuneUntil[target.UserId] or 0) <= os.clock() then
			local targetCharacter, _, targetRoot = getAliveCharacter(target)
			if targetCharacter and targetRoot and isInsideArena(targetRoot.Position, profile.arenaHeightAllowanceStuds) then
				local offset = targetRoot.Position - attackerRoot.Position
				if math.abs(offset.Y) <= targetConfig.maxVerticalDifference then
					local horizontal = Vector3.new(offset.X, 0, offset.Z)
					local distance = horizontal.Magnitude
					if distance <= targetConfig.reachStuds then
						local direction = getPlanarDirection(horizontal, forward)
						local facing = forward:Dot(direction)
						if facing >= minimumForwardDot
							and (not targetConfig.requireLineOfSight or hasLineOfSight(attackerCharacter, targetCharacter, attackerRoot, targetRoot)) then
							table.insert(candidates, {
								player = target,
								distance = distance,
								facing = facing,
							})
						end
					end
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		if math.abs(a.distance - b.distance) > EPSILON then
			return a.distance < b.distance
		end
		if math.abs(a.facing - b.facing) > EPSILON then
			return a.facing > b.facing
		end
		return a.player.UserId < b.player.UserId
	end)

	local targets = {}
	local targetLimit = math.max(1, math.floor(targetConfig.maxTargets))
	for index = 1, math.min(targetLimit, #candidates) do
		table.insert(targets, candidates[index].player)
	end
	return targets
end

local function applyImpact(attackerRoot: BasePart, target: Player, profile: any): boolean
	local targetCharacter, _, targetRoot = getAliveCharacter(target)
	if not (targetCharacter and targetRoot and isInsideArena(targetRoot.Position, profile.arenaHeightAllowanceStuds)) then
		return false
	end

	local now = os.clock()
	if (hitImmuneUntil[target.UserId] or 0) > now then
		return false
	end

	local impact = profile.impact
	local attackerForward = getPlanarDirection(attackerRoot.CFrame.LookVector, Vector3.new(0, 0, -1))
	local direction = getPlanarDirection(targetRoot.Position - attackerRoot.Position, attackerForward)
	local deltaV = direction * impact.planarDeltaV + Vector3.yAxis * impact.verticalDeltaV
	local ragdollMaxSeconds = type(impact.ragdollMaxSeconds) == "number" and math.max(0, impact.ragdollMaxSeconds) or 0
	local landingRecoverySeconds = type(impact.ragdollLandingRecoverySeconds) == "number"
		and math.max(0, impact.ragdollLandingRecoverySeconds)
		or 0
	local baseOwnershipSeconds = math.max(0, impact.serverOwnershipSeconds)
	local immunityUntil = now + impact.hitImmunitySeconds
	-- Reserve immunity before yielding for the ragdoll topology change. That prevents
	-- simultaneous swings from stacking separate launches onto the same target.
	hitImmuneUntil[target.UserId] = immunityUntil
	local function releaseImmunityReservation()
		if hitImmuneUntil[target.UserId] == immunityUntil then
			hitImmuneUntil[target.UserId] = nil
		end
	end

	if not KnockbackUtil.ClaimServerOwnership(targetCharacter, target) then
		releaseImmunityReservation()
		return false
	end

	-- Ragdoll changes the character's physics assembly. It must happen before the launch;
	-- otherwise that topology change consumes the just-applied impulse and the target only
	-- appears to fall over in place.
	local ragdolled = false
	local ragdollToken: number? = nil
	if ragdollMaxSeconds > 0 then
		ragdolled, ragdollToken = RagdollUtil.Start(targetCharacter, ragdollMaxSeconds)
	end
	if ragdolled then
		-- Let the ragdoll's constraint changes commit before enumerating the independent
		-- body assemblies that must all receive the same launch.
		RunService.Heartbeat:Wait()
	end

	local currentCharacter = select(1, getAliveCharacter(target))
	if currentCharacter ~= targetCharacter then
		if ragdolled then
			RagdollUtil.Stop(targetCharacter, ragdollToken)
		end
		KnockbackUtil.ReleaseCharacter(targetCharacter)
		releaseImmunityReservation()
		return false
	end

	-- This is a safety release only. A normal landing returns ownership as soon as
	-- the configured post-landing ragdoll recovery finishes. If a nonstandard rig cannot ragdoll,
	-- it retains the profile's short normal ownership window instead.
	local ownershipSeconds = if ragdolled
		then math.max(baseOwnershipSeconds, ragdollMaxSeconds + landingRecoverySeconds + 0.15)
		else baseOwnershipSeconds
	if not KnockbackUtil.Apply(targetCharacter, target, deltaV, ownershipSeconds) then
		if ragdolled then
			RagdollUtil.Stop(targetCharacter, ragdollToken)
		end
		KnockbackUtil.ReleaseCharacter(targetCharacter)
		releaseImmunityReservation()
		return false
	end

	-- Gameplay stays server-owned. The server broadcasts only a confirmed impact so every
	-- client can render the same lightweight cosmetic burst and airborne smoke locally.
	if CombatVfxEvent and profile.vfx then
		local configuredAirTrailSeconds = profile.vfx.airTrailSeconds
		local airTrailSeconds = if ragdolled and type(configuredAirTrailSeconds) == "number"
			then math.max(0, configuredAirTrailSeconds)
			else 0
		CombatVfxEvent:FireAllClients("Impact", targetCharacter, profile.vfx, airTrailSeconds)
	end

	local recoveryUntilAt = now + ownershipSeconds
	recoveryUntil[target.UserId] = recoveryUntilAt
	if ragdolled then
		RagdollUtil.StopAfterLanding(targetCharacter, ragdollToken, landingRecoverySeconds, function()
			if CombatVfxEvent then
				CombatVfxEvent:FireAllClients("Landed", targetCharacter)
			end
		end, function()
			KnockbackUtil.ReleaseCharacter(targetCharacter)
			if recoveryUntil[target.UserId] == recoveryUntilAt then
				recoveryUntil[target.UserId] = os.clock()
			end
		end)
	end

	activeAttacks[target.UserId] = nil
	return true
end

local function resolveAttack(attack: any)
	if activeAttacks[attack.player.UserId] ~= attack then
		return
	end
	activeAttacks[attack.player.UserId] = nil

	if attack.player.Character ~= attack.character or attack.tool.Parent ~= attack.character then
		return
	end

	local character, _, root = getAliveCharacter(attack.player)
	if character ~= attack.character or not root then
		return
	end

	local currentWeaponId, currentProfile = WeaponsData.GetProfile(attack.tool)
	if currentWeaponId ~= attack.weaponId or currentProfile ~= attack.profile then
		return
	end

	if attack.profile.arenaOnly ~= false and not isInsideArena(root.Position, attack.profile.arenaHeightAllowanceStuds) then
		return
	end

	for _, target in ipairs(findTargets(attack.player, character, root, attack.profile)) do
		applyImpact(root, target, attack.profile)
	end
end

local function handleCombatEvent(player: Player, action: string?)
	if action ~= "SwingRequest" then
		return
	end

	local character, _, root = getAliveCharacter(player)
	if not (character and root) then
		return
	end

	local tool, weaponId, profile = getEquippedMeleeTool(character)
	if not (tool and weaponId and profile) then
		return
	end

	local now = os.clock()
	if activeAttacks[player.UserId]
		or now < (nextSwingAt[player.UserId] or 0)
		or now < (recoveryUntil[player.UserId] or 0) then
		return
	end

	if profile.arenaOnly ~= false and not isInsideArena(root.Position, profile.arenaHeightAllowanceStuds) then
		return
	end

	nextSwingAt[player.UserId] = now + profile.swing.cooldownSeconds
	nextAttackId += 1
	local attack = {
		id = nextAttackId,
		player = player,
		character = character,
		tool = tool,
		weaponId = weaponId,
		profile = profile,
	}
	activeAttacks[player.UserId] = attack

	task.delay(profile.swing.impactDelaySeconds, function()
		resolveAttack(attack)
	end)
end

local function clearPlayerCombatState(player: Player, character: Model?)
	local userId = player.UserId
	local attack = activeAttacks[userId]
	if not character or (attack and attack.character == character) then
		activeAttacks[userId] = nil
	end
	nextSwingAt[userId] = nil
	recoveryUntil[userId] = nil
	hitImmuneUntil[userId] = nil

	if character then
		RagdollUtil.Stop(character)

		KnockbackUtil.ReleaseCharacter(character)
	end
end

local PlayerCombatService = {}

function PlayerCombatService.Init(context: any)
	WeaponsData = context.Metadata.Weapons
	CombatEvent = context.Remotes.CombatEvent
	CombatVfxEvent = context.Remotes.CombatVfxEvent
	Arena = context.Instances.Arena

	CombatEvent.OnServerEvent:Connect(handleCombatEvent)

	PlayerUtil.OnPlayer(function(player)
		player.CharacterRemoving:Connect(function(character)
			clearPlayerCombatState(player, character)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearPlayerCombatState(player, player.Character)
	end)

	log.info("Initialized")
end

return PlayerCombatService
