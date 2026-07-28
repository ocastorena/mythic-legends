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
local KnockdownUtil = require(script.KnockdownUtil)
local PositionHistory = require(script.PositionHistory)
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
local lastAcceptedSequence: { [number]: number } = {}
local pendingKnockbacks: { [number]: any } = {}
local nextAttackId = 0
local nextKnockbackId = 0
local positionHistory = PositionHistory.new(0.6, 1 / 30)

local EPSILON = 0.001
local MAX_FUTURE_CLIENT_SECONDS = 0.1
local HISTORY_SAMPLE_TOLERANCE_SECONDS = 0.075

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

local function isWithinTargetConfig(attackerCFrame: CFrame, targetPosition: Vector3, targetConfig: any): (boolean, number, number)
	local forward = getPlanarDirection(attackerCFrame.LookVector, Vector3.new(0, 0, -1))
	local offset = targetPosition - attackerCFrame.Position
	if math.abs(offset.Y) > targetConfig.maxVerticalDifference then
		return false, math.huge, -1
	end

	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local distance = horizontal.Magnitude
	if distance > targetConfig.reachStuds then
		return false, distance, -1
	end

	local direction = getPlanarDirection(horizontal, forward)
	local facing = forward:Dot(direction)
	local minimumForwardDot = math.cos(math.rad(targetConfig.arcDegrees * 0.5))
	return facing >= minimumForwardDot, distance, facing
end

local function findTargets(attacker: Player, attackerCharacter: Model, attackerRoot: BasePart, profile: any): { Player }
	local targetConfig = profile.target
	local candidates = {}

	for _, target in ipairs(Players:GetPlayers()) do
		if target ~= attacker and (hitImmuneUntil[target.UserId] or 0) <= os.clock() then
			local targetCharacter, _, targetRoot = getAliveCharacter(target)
			if targetCharacter and targetRoot and isInsideArena(targetRoot.Position, profile.arenaHeightAllowanceStuds) then
				local isWithinArc, distance, facing = isWithinTargetConfig(attackerRoot.CFrame, targetRoot.Position, targetConfig)
				if isWithinArc
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

local function applyImpact(
	attacker: Player,
	attackerRoot: BasePart,
	target: Player,
	profile: any,
	swingSequence: number
): boolean
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
	local launchVelocity = direction * impact.planarDeltaV + Vector3.yAxis * impact.verticalDeltaV
	local ragdollMaxSeconds = type(impact.ragdollMaxSeconds) == "number" and math.max(0, impact.ragdollMaxSeconds) or 0
	local landingRecoverySeconds = type(impact.ragdollLandingRecoverySeconds) == "number"
		and math.max(0, impact.ragdollLandingRecoverySeconds)
		or 0
	local baseOwnershipSeconds = math.max(0, impact.serverOwnershipSeconds)
	local preservePlayerOwnership = impact.preservePlayerOwnership == true
	local immunityUntil = now + impact.hitImmunitySeconds
	-- Reserve immunity before changing the reaction state. That prevents simultaneous
	-- swings from stacking separate launches onto the same target.
	hitImmuneUntil[target.UserId] = immunityUntil
	local function releaseImmunityReservation()
		if hitImmuneUntil[target.UserId] == immunityUntil then
			hitImmuneUntil[target.UserId] = nil
		end
	end

	if not preservePlayerOwnership and not KnockbackUtil.ClaimServerOwnership(targetCharacter, target) then
		releaseImmunityReservation()
		return false
	end

	local ragdolled = false
	local ragdollToken: number? = nil
	local knockedDown = false
	local knockdownToken: number? = nil
	if impact.reactionMode == "Knockdown" and ragdollMaxSeconds > 0 then
		knockedDown, knockdownToken = KnockdownUtil.Start(targetCharacter, ragdollMaxSeconds)
	elseif ragdollMaxSeconds > 0 then
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
		if knockedDown then
			KnockdownUtil.Stop(targetCharacter, knockdownToken)
		end
		KnockbackUtil.ReleaseCharacter(targetCharacter)
		releaseImmunityReservation()
		return false
	end

	-- This is a safety release only. A normal landing returns ownership as soon as
	-- the configured post-landing ragdoll recovery finishes. If a nonstandard rig cannot ragdoll,
	-- it retains the profile's short normal ownership window instead.
	local hasReaction = ragdolled or knockedDown
	local ownershipSeconds = if hasReaction
		then math.max(baseOwnershipSeconds, ragdollMaxSeconds + landingRecoverySeconds + 0.15)
		else baseOwnershipSeconds
	local tumbleSpeed = if knockedDown and type(impact.tumbleAngularSpeed) == "number"
		then math.max(0, impact.tumbleAngularSpeed)
		else 0
	local tumbleAxis = Vector3.yAxis:Cross(direction)
	local angularVelocity = if tumbleAxis.Magnitude > EPSILON then tumbleAxis.Unit * tumbleSpeed else Vector3.zero
	local launchPrepared = preservePlayerOwnership or KnockbackUtil.Apply(
		targetCharacter,
		target,
		launchVelocity,
		ownershipSeconds,
		false,
		angularVelocity
	)
	if not launchPrepared then
		if ragdolled then
			RagdollUtil.Stop(targetCharacter, ragdollToken)
		end
		if knockedDown then
			KnockdownUtil.Stop(targetCharacter, knockdownToken)
		end
		KnockbackUtil.ReleaseCharacter(targetCharacter)
		releaseImmunityReservation()
		return false
	end

	if preservePlayerOwnership and CombatVfxEvent then
		nextKnockbackId += 1
		local hitId = nextKnockbackId
		local launchDurationSeconds = type(impact.launchControlSeconds) == "number"
			and math.clamp(impact.launchControlSeconds, 0.04, 0.2)
			or 0.1
		local ackTimeoutSeconds = type(impact.knockbackAckTimeoutSeconds) == "number"
			and math.clamp(impact.knockbackAckTimeoutSeconds, 0.2, 1)
			or 0.4
		local pending = {
			target = target,
			character = targetCharacter,
		launchVelocity = launchVelocity,
			angularVelocity = angularVelocity,
			launchDurationSeconds = launchDurationSeconds,
			ownershipSeconds = ownershipSeconds,
		}
		pendingKnockbacks[hitId] = pending

		CombatVfxEvent:FireClient(
			target,
			"ApplyKnockback",
			targetCharacter,
			nil,
			0,
			attacker.UserId,
			swingSequence,
			launchVelocity,
			angularVelocity,
			hitId,
			launchDurationSeconds
		)

		-- Reliable acknowledgement, rather than delayed position sampling, decides whether
		-- a fallback is needed. This prevents a normal high-ping launch from being doubled.
		task.delay(ackTimeoutSeconds, function()
			if pendingKnockbacks[hitId] ~= pending then
				return
			end
			pendingKnockbacks[hitId] = nil

			local currentCharacter, _, currentRoot = getAliveCharacter(target)
			if currentCharacter ~= targetCharacter or not currentRoot then
				return
			end

			KnockbackUtil.ApplyVelocity(
				targetCharacter,
				target,
				launchVelocity,
				launchDurationSeconds,
				ownershipSeconds,
				angularVelocity
			)
		end)
	end

	-- Gameplay stays server-owned. The server broadcasts only a confirmed impact so every
	-- client can render the same lightweight cosmetic burst and airborne smoke locally.
	if CombatVfxEvent and profile.vfx then
		local configuredAirTrailSeconds = profile.vfx.airTrailSeconds
		local airTrailSeconds = if hasReaction and type(configuredAirTrailSeconds) == "number"
			then math.max(0, configuredAirTrailSeconds)
			else 0
		CombatVfxEvent:FireAllClients(
			"Impact",
			targetCharacter,
			profile.vfx,
			airTrailSeconds,
			attacker.UserId,
			swingSequence
		)
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
	elseif knockedDown then
		local recoveryNotified = false
		local function notifyTargetRecovered()
			if recoveryNotified then
				return
			end
			recoveryNotified = true
			if CombatVfxEvent and target.Parent == Players and target.Character == targetCharacter then
				CombatVfxEvent:FireClient(target, "Recovered", targetCharacter)
			end
			if recoveryUntil[target.UserId] == recoveryUntilAt then
				recoveryUntil[target.UserId] = os.clock()
			end
			KnockbackUtil.ReleaseCharacter(targetCharacter)
		end

		KnockdownUtil.StopAfterLanding(targetCharacter, knockdownToken, landingRecoverySeconds, function()
			if CombatVfxEvent then
				CombatVfxEvent:FireAllClients("Landed", targetCharacter)
			end
		end, function()
			notifyTargetRecovered()
		end)
		-- Falling out of the arena may never produce a valid landing. The knockdown's
		-- maximum-duration restore still needs to release the owning client's state.
		task.delay(ragdollMaxSeconds + 0.05, notifyTargetRecovered)
	end

	local interruptedAttack = activeAttacks[target.UserId]
	activeAttacks[target.UserId] = nil
	if interruptedAttack and CombatVfxEvent then
		CombatVfxEvent:FireClient(
			target,
			"Rejected",
			nil,
			nil,
			0,
			target.UserId,
			interruptedAttack.sequence
		)
	end
	return true
end

local function validateActiveAttack(attack: any): (Model?, BasePart?)
	if activeAttacks[attack.player.UserId] ~= attack then
		return nil, nil
	end

	if attack.player.Character ~= attack.character or attack.tool.Parent ~= attack.character then
		return nil, nil
	end

	local character, _, root = getAliveCharacter(attack.player)
	if character ~= attack.character or not root then
		return nil, nil
	end

	local currentWeaponId, currentProfile = WeaponsData.GetProfile(attack.tool)
	if currentWeaponId ~= attack.weaponId or currentProfile ~= attack.profile then
		return nil, nil
	end

	if attack.profile.arenaOnly ~= false and not isInsideArena(root.Position, attack.profile.arenaHeightAllowanceStuds) then
		return nil, nil
	end

	return character, root
end

local function finishAttack(attack: any, wasRejected: boolean)
	if activeAttacks[attack.player.UserId] ~= attack then
		return
	end

	activeAttacks[attack.player.UserId] = nil
	if wasRejected and CombatVfxEvent then
		CombatVfxEvent:FireClient(
			attack.player,
			"Rejected",
			nil,
			nil,
			0,
			attack.player.UserId,
			attack.sequence
		)
	end
end

local function applyRewoundPrediction(attack: any, payload: any): boolean
	if type(payload) ~= "table"
		or payload.sequence ~= attack.sequence
		or type(payload.targetUserId) ~= "number"
		or payload.targetUserId % 1 ~= 0
		or type(payload.clientTime) ~= "number"
		or payload.clientTime ~= payload.clientTime then
		return false
	end

	local target = Players:GetPlayerByUserId(payload.targetUserId)
	if not target or target == attack.player then
		return false
	end

	local now = workspace:GetServerTimeNow()
	local maxRewindSeconds = math.max(0, attack.profile.swing.maxRewindSeconds)
	if payload.clientTime > now + MAX_FUTURE_CLIENT_SECONDS or payload.clientTime < now - maxRewindSeconds then
		return false
	end

	local sampleTime = math.min(payload.clientTime, now)
	local attackerSample = positionHistory:GetClosest(
		attack.player.UserId,
		sampleTime,
		HISTORY_SAMPLE_TOLERANCE_SECONDS
	)
	local targetSample = positionHistory:GetClosest(target.UserId, sampleTime, HISTORY_SAMPLE_TOLERANCE_SECONDS)
	if not (attackerSample and targetSample) then
		return false
	end

	local isWithinArc = isWithinTargetConfig(attackerSample.cframe, targetSample.cframe.Position, attack.profile.target)
	if not isWithinArc then
		return false
	end

	local attackerCharacter, attackerRoot = validateActiveAttack(attack)
	local targetCharacter, _, targetRoot = getAliveCharacter(target)
	if not (attackerCharacter and attackerRoot and targetCharacter and targetRoot) then
		return false
	end
	if attack.profile.target.requireLineOfSight
		and not hasLineOfSight(attackerCharacter, targetCharacter, attackerRoot, targetRoot) then
		return false
	end

	return applyImpact(attack.player, attackerRoot, target, attack.profile, attack.sequence)
end

local function resolveAttack(attack: any)
	local configuredWindow = attack.profile.swing.activeWindowSeconds
	local activeWindowSeconds = if type(configuredWindow) == "number" then math.max(0, configuredWindow) else 0
	local activeWindowEndsAt = os.clock() + activeWindowSeconds

	while activeAttacks[attack.player.UserId] == attack do
		local character, root = validateActiveAttack(attack)
		if not (character and root) then
			break
		end

		for _, target in ipairs(findTargets(attack.player, character, root, attack.profile)) do
			if applyImpact(attack.player, root, target, attack.profile, attack.sequence) then
				finishAttack(attack, false)
				return
			end
		end

		if os.clock() >= activeWindowEndsAt then
			break
		end
		RunService.Heartbeat:Wait()
	end

	finishAttack(attack, true)
end

local function handleCombatEvent(player: Player, action: string?, payload: any)
	if action == "KnockbackAck" then
		local hitId = type(payload) == "table" and payload.hitId or nil
		if type(hitId) ~= "number" or hitId % 1 ~= 0 then
			return
		end

		local pending = pendingKnockbacks[hitId]
		if pending and pending.target == player and player.Character == pending.character then
			pendingKnockbacks[hitId] = nil
		end
		return
	end

	if action == "SwingPrediction" then
		local attack = activeAttacks[player.UserId]
		if attack and applyRewoundPrediction(attack, payload) then
			finishAttack(attack, false)
		end
		return
	end
	if action ~= "SwingRequest" or type(payload) ~= "table" then
		return
	end

	local sequence = payload.sequence
	local clientTime = payload.clientTime
	if type(sequence) ~= "number"
		or sequence % 1 ~= 0
		or sequence < 1
		or sequence > 2147483647
		or type(clientTime) ~= "number"
		or clientTime ~= clientTime then
		return
	end

	local function rejectRequest()
		if CombatVfxEvent then
			CombatVfxEvent:FireClient(
				player,
				"Rejected",
				nil,
				nil,
				0,
				player.UserId,
				sequence
			)
		end
	end

	local character, _, root = getAliveCharacter(player)
	if not (character and root) then
		rejectRequest()
		return
	end

	local tool, weaponId, profile = getEquippedMeleeTool(character)
	if not (tool and weaponId and profile) then
		rejectRequest()
		return
	end

	local now = os.clock()
	if activeAttacks[player.UserId]
		or sequence <= (lastAcceptedSequence[player.UserId] or 0)
		or now < (nextSwingAt[player.UserId] or 0)
		or now < (recoveryUntil[player.UserId] or 0) then
		rejectRequest()
		return
	end

	if profile.arenaOnly ~= false and not isInsideArena(root.Position, profile.arenaHeightAllowanceStuds) then
		rejectRequest()
		return
	end

	nextSwingAt[player.UserId] = now + profile.swing.cooldownSeconds
	lastAcceptedSequence[player.UserId] = sequence
	nextAttackId += 1
	local attack = {
		id = nextAttackId,
		player = player,
		character = character,
		tool = tool,
		weaponId = weaponId,
		profile = profile,
		sequence = sequence,
		clientTime = clientTime,
	}
	activeAttacks[player.UserId] = attack

	local impactDelaySeconds = math.max(0, profile.swing.impactDelaySeconds)
	if impactDelaySeconds > 0 then
		task.delay(impactDelaySeconds, resolveAttack, attack)
	else
		-- Run independently because resolution spans multiple Heartbeats while the blade
		-- is active. There is no artificial delay before the first server-side hit check.
		task.spawn(resolveAttack, attack)
	end
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
	positionHistory:Clear(userId)
	for hitId, pending in pairs(pendingKnockbacks) do
		if pending.target == player or (character and pending.character == character) then
			pendingKnockbacks[hitId] = nil
		end
	end

	if character then
		RagdollUtil.Stop(character)
		KnockdownUtil.Stop(character)

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
		lastAcceptedSequence[player.UserId] = nil
	end)

	RunService.Heartbeat:Connect(function()
		positionHistory:Record(Players:GetPlayers(), workspace:GetServerTimeNow())
	end)

	log.info("Initialized")
end

return PlayerCombatService
