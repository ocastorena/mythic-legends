--!strict
-- ServerScriptService/Services/CombatService
-- Server-owned R15 loadouts, Arena state, Stamina, guard validation, and hit authorization.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local TweenService = game:GetService("TweenService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
local log = LogUtil.For("CombatService")
type TroveInstance = Trove.Trove

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local EquipmentPresentation = require(script.EquipmentPresentation)
local ArenaBounds = require(script.ArenaBounds)
local CombatMath = require(script.CombatMath)
local CombatState = require(script.CombatState)
local ElementalHits = require(script.ElementalHits)
local EarthLanding = require(script.EarthLanding)
local MovementRestrictions = require(script.MovementRestrictions)
local CombatRuntimeConfiguration = require(ReplicatedStorage.Shared.Configurations.CombatRuntime)
local LoadoutRequests = require(script.LoadoutRequests)
local LoadoutRequestsConfiguration =
	require(ReplicatedStorage.Shared.Configurations.LoadoutRequests)
local LoadoutCommands = require(script.LoadoutCommands)
local LoadoutUtil = require(script.LoadoutUtil)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local lifecycle = ServiceLifecycle.new("CombatService")
local presentation: { Clear: (Model) -> (), Rebuild: (Model) -> () }
local Equipment: Types.EquipmentConfiguration
local DataService: ServerTypes.DataApi
local equipmentAssets: Folder
local startAttack: RemoteEvent
local reportHit: RemoteEvent
local setShieldGuardRemote: RemoteEvent
local combatReaction: RemoteEvent
local combatImpact: RemoteEvent
local getLoadoutRemote: RemoteFunction?
local equipRemote: RemoteFunction?
local equipEquipmentRemote: RemoteFunction?
local unequipEquipmentRemote: RemoteFunction?
local loadoutRequests: LoadoutRequests.Requests?
local loadoutCommands: LoadoutCommands.LoadoutCommands?
local arena: BasePart

local CombatService = {}

local MAX_SEQUENCE = 2_147_483_647
local MAX_REACH = 20
local MAX_COOLDOWN = 5
local DEFAULT_ARENA_HEIGHT_ALLOWANCE = 20
local SHIELD_BUBBLE_NAME = "ShieldBubble"
local SHIELD_BUBBLE_SIZE = 9

type AuthorizedSwing = {
	sequence: number,
	selection: LoadoutUtil.Selection,
	expiresAt: number,
}

type ImpactReactionType = Types.CombatReactionType

type CombatRuntime = {
	accounting: CombatState.State,
	immunityUntil: number,
	guardShield: LoadoutUtil.Selection?,
	lastSwingSequence: number,
	lastHitSequence: number,
	authorizedSwing: AuthorizedSwing?,
	character: Model?,
	movement: MovementRestrictions.MovementRestrictions?,
}

type PlayerLifecycle = {
	trove: TroveInstance,
	characterTrove: TroveInstance,
	characterGeneration: number,
}

local runtimes: { [Player]: CombatRuntime } = {}
local playerLifecycles: { [Player]: PlayerLifecycle } = {}
local nextHitId = 0
local serviceTrove: TroveInstance?
local shieldTweens: { [Model]: Tween } = {}
local loadoutLimiter: RateLimiter.RateLimiter?
local guardLimiter = RateLimiter.new(16, 8)
local startAttackLimiter = RateLimiter.new(8, 4)
local reportHitLimiter = RateLimiter.new(12, 6)

local function getNumber(value: unknown, fallback: number, minimum: number, maximum: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function getAliveR15Character(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
		or character.Parent == nil
		or not humanoid
		or humanoid.Health <= 0
		or humanoid.RigType ~= Enum.HumanoidRigType.R15
		or not root
		or not root:IsA("BasePart")
	then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function isCharacterInArena(character: Model): boolean
	local root = character:FindFirstChild("HumanoidRootPart")
	local allowance = getNumber(
		Equipment.combat.arenaHeightAllowanceStuds,
		DEFAULT_ARENA_HEIGHT_ALLOWANCE,
		0,
		100
	)
	return root ~= nil
		and root:IsA("BasePart")
		and ArenaBounds.Contains(arena, root.Position, allowance)
end

local function getRuntime(player: Player): CombatRuntime
	local runtime: CombatRuntime? = runtimes[player]
	if runtime then
		return runtime
	end
	local created: CombatRuntime = {
		accounting = CombatState.New(os.clock(), {
			maximum = Equipment.combat.staminaMaximum,
			spawn = Equipment.combat.staminaSpawn,
			recoveryPerSecond = Equipment.combat.staminaRegenPerSecond,
		}),
		immunityUntil = 0,
		guardShield = nil,
		lastSwingSequence = 0,
		lastHitSequence = 0,
		authorizedSwing = nil,
		character = player.Character,
		movement = nil,
	}
	runtimes[player] = created
	return created
end

local function restoreMovement(runtime: CombatRuntime)
	local movement = runtime.movement
	if not movement then
		return
	end
	runtime.movement = nil
	movement.Clear()
end

local function clearShieldBubble(character: Model?)
	if character then
		local tween = shieldTweens[character]
		if tween then
			shieldTweens[character] = nil
			tween:Cancel()
			tween:Destroy()
		end
	end
	local bubble = character and character:FindFirstChild(SHIELD_BUBBLE_NAME)
	if bubble then
		bubble:Destroy()
	end
end

local function createShieldBubble(character: Model, root: BasePart)
	clearShieldBubble(character)
	local bubble = Instance.new("Part")
	bubble.Name = SHIELD_BUBBLE_NAME
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one
	bubble.CFrame = root.CFrame
	bubble.Color = Color3.fromRGB(104, 213, 255)
	bubble.Material = Enum.Material.ForceField
	bubble.Transparency = 1
	bubble.CastShadow = false
	bubble.Anchored = false
	bubble.CanCollide = false
	bubble.CanTouch = false
	-- The attacking client's blade sweep must contact the bubble before body geometry.
	bubble.CanQuery = true
	bubble.Massless = true
	bubble.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Name = "ShieldBubbleWeld"
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	local tween = TweenService:Create(
		bubble,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Size = Vector3.one * SHIELD_BUBBLE_SIZE,
			Transparency = 0.48,
		}
	)
	shieldTweens[character] = tween
	tween:Play()
end

local function snapshotLoadout(player: Player): LoadoutRequests.Snapshot
	local data = DataService.GetLoadedData(player)
	assert(data, "[CombatService] Loadout requires an active profile")
	return LoadoutUtil.Snapshot(data)
end

local function getGuardProfile(player: Player): (LoadoutUtil.Selection?, Types.EquipmentProfile?)
	local character = getAliveR15Character(player)
	local data = DataService.GetLoadedData(player)
	if not character or not data or not isCharacterInArena(character) then
		return nil, nil
	end
	local selection = LoadoutUtil.GetMounted(data, character, "Shield")
	return selection, if selection then selection.item.profile else nil
end

local function shieldTuning(profile: Types.EquipmentProfile): CombatState.ShieldTuning?
	local cost, minimum = profile.impactStaminaCost, profile.minimumGuardStamina
	local raise, raiseTimeout = profile.raiseSeconds, profile.raiseTimeoutSeconds
	local lower, lowerTimeout = profile.lowerSeconds, profile.lowerTimeoutSeconds
	if
		not cost
		or not minimum
		or not raise
		or not raiseTimeout
		or not lower
		or not lowerTimeout
	then
		return nil
	end
	return {
		cost = cost,
		minimum = minimum,
		raiseSeconds = raise,
		raiseTimeoutSeconds = raiseTimeout,
		lowerSeconds = lower,
		lowerTimeoutSeconds = lowerTimeout,
	}
end

local function publishRuntime(player: Player, runtime: CombatRuntime, now: number)
	local state = runtime.accounting
	local character, humanoid, root = getAliveR15Character(player)
	if character and humanoid and runtime.character == character then
		local movement = runtime.movement or MovementRestrictions.new(character, humanoid)
		runtime.movement = movement
		movement.Apply(CombatState.GetMovement(state, now))
	else
		restoreMovement(runtime)
	end
	local currentCharacter = player.Character
	if currentCharacter and currentCharacter == runtime.character then
		local effect = CombatState.GetEffect(state, now)
		local serverNow = workspace:GetServerTimeNow()
		currentCharacter:SetAttribute("CombatEffectId", if effect then effect.effectId else "")
		currentCharacter:SetAttribute("CombatEffectKind", if effect then effect.kind else "")
		currentCharacter:SetAttribute("CombatEffectPhase", if effect then effect.phase else "")
		currentCharacter:SetAttribute("CombatEffectToken", if effect then effect.token else 0)
		currentCharacter:SetAttribute(
			"CombatEffectStartedAt",
			if effect then serverNow + effect.startedAt - now else 0
		)
		currentCharacter:SetAttribute(
			"CombatEffectExpiresAt",
			if effect then serverNow + effect.expiresAt - now else 0
		)
		currentCharacter:SetAttribute(
			"EarthProtectedUntil",
			if state.earthProtectedUntil > now
				then serverNow + state.earthProtectedUntil - now
				else 0
		)
		currentCharacter:SetAttribute("HasStaminaBurn", effect ~= nil and effect.kind == "Burn")
		currentCharacter:SetAttribute("GuardSequence", state.guardSequence)
		currentCharacter:SetAttribute("GuardPhase", state.phase)
		currentCharacter:SetAttribute("SwingLocked", now < state.swingEndsAt)
		currentCharacter:SetAttribute("ShieldGuarding", state.protecting)
		if state.protecting and character and root then
			if not character:FindFirstChild(SHIELD_BUBBLE_NAME) then
				createShieldBubble(character, root)
			end
		else
			clearShieldBubble(currentCharacter)
		end
	end
	player:SetAttribute("CombatStamina", state.stamina)
	player:SetAttribute("MaxCombatStamina", state.maximum)
	player:SetAttribute("KnockbackImmune", now < runtime.immunityUntil)
end

local function refreshRuntime(player: Player, now: number): CombatRuntime
	local runtime = getRuntime(player)
	CombatState.Advance(runtime.accounting, now)
	if runtime.accounting.phase ~= "Lowered" then
		local shield = getGuardProfile(player)
		if
			not shield
			or not runtime.guardShield
			or not LoadoutUtil.Same(shield, runtime.guardShield)
		then
			CombatState.ReleaseGuard(runtime.accounting, now, nil, true)
		end
	else
		runtime.guardShield = nil
	end
	if runtime.authorizedSwing and now > runtime.authorizedSwing.expiresAt then
		runtime.authorizedSwing = nil
	end
	publishRuntime(player, runtime, now)
	return runtime
end

local function observeEarth(player: Player, runtime: CombatRuntime, now: number)
	local effect = runtime.accounting.negativeEffect
	if not effect or effect.kind ~= "Root" or effect.phase ~= "Pending" then
		return
	end
	local character, humanoid, root = getAliveR15Character(player)
	if not character or character ~= runtime.character or not humanoid or not root then
		return
	end
	local observation =
		EarthLanding.Sample(character, humanoid, root, CombatRuntimeConfiguration.earthLanding)
	if
		CombatState.ObserveEarth(
			runtime.accounting,
			now,
			effect.token,
			observation.airborne,
			observation.supported
		)
	then
		publishRuntime(player, runtime, now)
	end
end

local function forceLowerGuard(player: Player)
	local now = os.clock()
	local runtime = refreshRuntime(player, now)
	CombatState.ReleaseGuard(runtime.accounting, now, nil, true)
	runtime.authorizedSwing = nil
	publishRuntime(player, runtime, now)
end

local function applyResolvedLoadout(player: Player, character: Model)
	local data = DataService.GetLoadedData(player)
	if not data then
		return
	end
	LoadoutUtil.WriteAttributes(character, data)
	getRuntime(player).authorizedSwing = nil
	presentation.Rebuild(character)
end

local function handleGuardRequest(player: Player, input: unknown)
	if type(input) ~= "table" then
		return
	end
	local payload = input :: { [string]: unknown }
	local sequence = payload.sequence
	local action = payload.action
	local character = player.Character
	if
		not character
		or payload.character ~= character
		or type(sequence) ~= "number"
		or not CombatMath.IsValidSequence(sequence, MAX_SEQUENCE)
	then
		return
	end
	if action ~= "Begin" and action ~= "Raised" and action ~= "Release" and action ~= "Lowered" then
		return
	end
	-- Release/finish are idempotent cleanup, including when other guard messages are limited.
	if (action == "Begin" or action == "Raised") and not guardLimiter:Allow(player) then
		return
	end
	local now = os.clock()
	local runtime = refreshRuntime(player, now)
	if action == "Begin" then
		local shield, profile = getGuardProfile(player)
		local tuning = profile and shieldTuning(profile)
		local accepted = false
		if shield and tuning and character:GetAttribute("CombatReady") == true then
			accepted = CombatState.BeginGuard(runtime.accounting, now, sequence, tuning)
		end
		if accepted then
			runtime.guardShield = shield
			runtime.authorizedSwing = nil
		end
		if not accepted then
			character:SetAttribute("GuardRejectedSequence", sequence)
		end
		character:SetAttribute("GuardRequestSequence", sequence)
	elseif action == "Release" then
		CombatState.ReleaseGuard(runtime.accounting, now, sequence, false)
	else
		CombatState.Marker(runtime.accounting, now, sequence, action)
	end
	publishRuntime(player, runtime, now)
end

local function updateArenaCombatState(player: Player)
	local character = getAliveR15Character(player)
	if not character then
		return
	end
	local shouldBeReady = isCharacterInArena(character)
	if character:GetAttribute("CombatReady") == shouldBeReady then
		return
	end
	forceLowerGuard(player)
	local runtime = getRuntime(player)
	runtime.authorizedSwing = nil
	character:SetAttribute("CombatReady", shouldBeReady)
	presentation.Rebuild(character)
end

local function getEquippedPrimary(player: Player, character: Model): LoadoutUtil.Selection?
	local data = DataService.GetLoadedData(player)
	return if data then LoadoutUtil.GetMounted(data, character, "PrimaryWeapon") else nil
end

local function hasLineOfSight(attackerCharacter: Model, targetCharacter: Model): boolean
	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if
		not attackerRoot
		or not attackerRoot:IsA("BasePart")
		or not targetRoot
		or not targetRoot:IsA("BasePart")
	then
		return false
	end
	local origin = attackerRoot.Position + Vector3.yAxis * 1.5
	local direction = targetRoot.Position + Vector3.yAxis * 1.5 - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	params.IgnoreWater = true
	local result = workspace:Raycast(origin, direction, params)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

local function handleMeleeSwing(player: Player, input: unknown)
	if type(input) ~= "table" then
		return
	end
	local payload = input :: { [string]: unknown }
	if
		type(payload.sequence) ~= "number"
		or not CombatMath.IsValidSequence(payload.sequence, MAX_SEQUENCE)
	then
		return
	end
	local character = getAliveR15Character(player)
	if
		not character
		or payload.character ~= character
		or character:GetAttribute("CombatReady") ~= true
		or not isCharacterInArena(character)
	then
		return
	end
	local selection = getEquippedPrimary(player, character)
	if not selection then
		return
	end
	local profile = selection.item.profile
	local now = os.clock()
	local runtime = refreshRuntime(player, now)
	if payload.sequence <= runtime.lastSwingSequence then
		return
	end
	local staminaCost = getNumber(profile.staminaCost, 0, 0, 1_000)
	local cooldown = getNumber(
		profile.cooldownSeconds,
		Equipment.presentationDefaults.cooldownSeconds,
		0.05,
		MAX_COOLDOWN
	)
	local duration = getNumber(
		profile.swingDurationSeconds,
		Equipment.presentationDefaults.swingDurationSeconds,
		0.05,
		MAX_COOLDOWN
	)
	if
		not CombatState.TryAttack(runtime.accounting, now, {
			cost = staminaCost,
			cooldownSeconds = cooldown,
			durationSeconds = duration,
		})
	then
		return
	end
	local window = getNumber(profile.contactWindowSeconds, 0.22, 0.05, 2)
	runtime.lastSwingSequence = payload.sequence
	runtime.authorizedSwing = {
		sequence = payload.sequence,
		selection = selection,
		expiresAt = now + window + 0.75,
	}
	publishRuntime(player, runtime, now)
end

local function sendImpact(
	attacker: Player,
	target: Player,
	targetCharacter: Model,
	launchVelocity: Vector3,
	angularVelocity: Vector3,
	controlSeconds: number,
	reactionType: ImpactReactionType,
	slideDurationSeconds: number,
	maximumReactionSeconds: number,
	landingRecoverySeconds: number,
	airTrailSeconds: number,
	sequence: number,
	blocked: boolean,
	profile: Types.EquipmentProfile
)
	nextHitId += 1
	local hitId = nextHitId
	local reaction: Types.CombatReaction = {
		hitId = hitId,
		character = targetCharacter,
		launchVelocity = launchVelocity,
		angularVelocity = angularVelocity,
		controlSeconds = controlSeconds,
		reactionType = reactionType,
		slideDurationSeconds = slideDurationSeconds,
		maximumReactionSeconds = maximumReactionSeconds,
		landingRecoverySeconds = landingRecoverySeconds,
	}
	combatReaction:FireClient(target, reaction)
	combatImpact:FireAllClients({
		hitId = hitId,
		targetUserId = target.UserId,
		attackerUserId = attacker.UserId,
		sequence = sequence,
		blocked = blocked,
		airTrailSeconds = airTrailSeconds,
		impactSoundId = profile.impactSoundId,
	})
end

local function handleHitReport(player: Player, input: unknown)
	if type(input) ~= "table" then
		return
	end
	local payload = input :: { [string]: unknown }
	if
		type(payload.sequence) ~= "number"
		or not CombatMath.IsValidSequence(payload.sequence, MAX_SEQUENCE)
		or type(payload.targetUserId) ~= "number"
		or payload.targetUserId % 1 ~= 0
	then
		return
	end
	local target = Players:GetPlayerByUserId(payload.targetUserId)
	if not target or target == player then
		return
	end
	local attackerCharacter, _, attackerRoot = getAliveR15Character(player)
	local targetCharacter, _, targetRoot = getAliveR15Character(target)
	if
		not attackerCharacter
		or payload.character ~= attackerCharacter
		or not attackerRoot
		or not targetCharacter
		or payload.targetCharacter ~= targetCharacter
		or not targetRoot
		or not isCharacterInArena(attackerCharacter)
		or not isCharacterInArena(targetCharacter)
	then
		return
	end
	local selection = getEquippedPrimary(player, attackerCharacter)
	if not selection then
		return
	end
	local profile = selection.item.profile
	local now = os.clock()
	local runtime = refreshRuntime(player, now)
	local authorization = runtime.authorizedSwing
	if
		not authorization
		or authorization.sequence ~= payload.sequence
		or not LoadoutUtil.Same(authorization.selection, selection)
		or now > authorization.expiresAt
		or payload.sequence <= runtime.lastHitSequence
	then
		return
	end
	local targetRuntime = refreshRuntime(target, now)
	if now < targetRuntime.immunityUntil then
		return
	end
	local maxDistance = math.clamp(
		getNumber(profile.reachStuds, 5, 0, MAX_REACH)
			+ getNumber(profile.serverToleranceStuds, 0, 0, MAX_REACH),
		0,
		MAX_REACH
	)
	if
		(targetRoot.Position - attackerRoot.Position).Magnitude > maxDistance
		or (
			profile.requireLineOfSight == true
			and not hasLineOfSight(attackerCharacter, targetCharacter)
		)
	then
		return
	end

	-- The accepted sequence is consumed exactly once before resolving Shield behavior.
	runtime.authorizedSwing = nil
	runtime.lastHitSequence = payload.sequence

	local directionDelta = targetRoot.Position - attackerRoot.Position
	local planar = Vector3.new(directionDelta.X, 0, directionDelta.Z)
	local attackerFacing =
		Vector3.new(attackerRoot.CFrame.LookVector.X, 0, attackerRoot.CFrame.LookVector.Z)
	local direction = if planar.Magnitude > 0.001
		then planar.Unit
		elseif attackerFacing.Magnitude > 0.001 then attackerFacing.Unit
		else Vector3.zAxis
	local blocked = false
	local launchVelocity: Vector3
	local angularVelocity = Vector3.zero
	local controlSeconds: number
	local reactionType: ImpactReactionType = "Launch"
	local slideDurationSeconds = 0
	local maximumReactionSeconds = 0
	local landingRecoverySeconds = 0
	local airTrailSeconds = 0
	local _, shieldProfile = getGuardProfile(target)
	if
		targetRuntime.accounting.protecting
		and shieldProfile
		and shieldProfile.kind == "Shield"
		and CombatMath.IsWithinGuardArc(
			attackerRoot.Position,
			targetRoot.Position,
			targetRoot.CFrame.LookVector,
			getNumber(shieldProfile.blockArcDegrees, 110, 0, 360)
		)
		and CombatState.Block(targetRuntime.accounting, now)
	then
		blocked = true
		reactionType = "ShieldSlide"
		launchVelocity = direction * getNumber(shieldProfile.slideKnockback, 28, 0, 100)
		controlSeconds = 0
		slideDurationSeconds = getNumber(shieldProfile.slideDurationSeconds, 0.32, 0.08, 0.75)
	else
		local horizontalMultiplier = ElementalHits.ApplyAcceptedHit(
			runtime.accounting,
			targetRuntime.accounting,
			now,
			selection.item.effectId,
			false
		)
		launchVelocity = direction
				* getNumber(profile.planarKnockback, 56, 0, 100)
				* horizontalMultiplier
			+ Vector3.yAxis * getNumber(profile.verticalKnockback, 58, 0, 100)
		local tumbleAxis = Vector3.new(0, 1, 0):Cross(direction)
		if tumbleAxis.Magnitude > 0.001 then
			angularVelocity = tumbleAxis.Unit * getNumber(profile.tumbleAngularSpeed, 5.5, 0, 20)
		end
		controlSeconds = getNumber(profile.launchControlSeconds, 0.1, 0.05, 0.5)
		maximumReactionSeconds = getNumber(profile.maximumReactionSeconds, 3.5, 0.1, 10)
		landingRecoverySeconds = getNumber(profile.landingRecoverySeconds, 0.2, 0, 2)
		airTrailSeconds = getNumber(profile.airTrailSeconds, 3.5, 0, 10)
	end
	local immunity = getNumber(Equipment.combat.knockbackImmunitySeconds, 0.65, 0, 5)
	targetRuntime.immunityUntil = now + immunity
	-- The final paid block still slides and grants immunity even though its cost has
	-- already removed protection. Publishing immediately prevents any extra free block.
	publishRuntime(target, targetRuntime, now)
	publishRuntime(player, runtime, now)
	sendImpact(
		player,
		target,
		targetCharacter,
		launchVelocity,
		angularVelocity,
		controlSeconds,
		reactionType,
		slideDurationSeconds,
		maximumReactionSeconds,
		landingRecoverySeconds,
		airTrailSeconds,
		payload.sequence,
		blocked,
		profile
	)
end

local function cleanCharacterLifecycle(player: Player)
	local playerLifetime = playerLifecycles[player]
	if playerLifetime then
		playerLifetime.characterTrove:Clean()
	end
end

local function clearEffectAttributes(character: Model)
	for _, name in { "CombatEffectId", "CombatEffectKind", "CombatEffectPhase" } do
		character:SetAttribute(name, "")
	end
	for _, name in
		{
			"CombatEffectToken",
			"CombatEffectStartedAt",
			"CombatEffectExpiresAt",
			"EarthProtectedUntil",
		}
	do
		character:SetAttribute(name, 0)
	end
	character:SetAttribute("HasStaminaBurn", false)
end

local function clearAffectedCharacter(player: Player, character: Model)
	local runtime = runtimes[player]
	if runtime and runtime.character == character then
		local now = os.clock()
		CombatState.ClearEffects(runtime.accounting, now)
		CombatState.ReleaseGuard(runtime.accounting, now, nil, true)
		runtime.authorizedSwing = nil
		restoreMovement(runtime)
	end
	clearEffectAttributes(character)
	character:SetAttribute("ShieldGuarding", false)
	clearShieldBubble(character)
end

local function onCharacterAdded(player: Player, character: Model)
	local playerLifetime = playerLifecycles[player]
	if not lifecycle:IsRunning() or not playerLifetime or player.Character ~= character then
		return
	end
	playerLifetime.characterGeneration += 1
	local generation = playerLifetime.characterGeneration
	local function isCurrent(): boolean
		return lifecycle:IsRunning()
			and playerLifecycles[player] == playerLifetime
			and playerLifetime.characterGeneration == generation
			and player.Parent == Players
			and player.Character == character
	end
	local priorRuntime = runtimes[player]
	if priorRuntime then
		if priorRuntime.character then
			clearAffectedCharacter(player, priorRuntime.character)
		end
		restoreMovement(priorRuntime)
	end
	runtimes[player] = nil
	cleanCharacterLifecycle(player)
	character:SetAttribute("CombatReady", false)
	character:SetAttribute("ShieldGuarding", false)
	character:SetAttribute("GuardPhase", "Lowered")
	character:SetAttribute("GuardSequence", 0)
	character:SetAttribute("GuardRequestSequence", 0)
	character:SetAttribute("GuardRejectedSequence", 0)
	character:SetAttribute("SwingLocked", false)
	clearEffectAttributes(character)
	playerLifetime.characterTrove:Add(function()
		clearAffectedCharacter(player, character)
		clearShieldBubble(character)
		presentation.Clear(character)
		character:SetAttribute("CombatReady", false)
		character:SetAttribute("ShieldGuarding", false)
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not isCurrent() or not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if not DataService.Load(player) or not isCurrent() then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		log.warn(`userId {player.UserId} must use an R15 character`)
		return
	end
	refreshRuntime(player, os.clock())
	applyResolvedLoadout(player, character)
	playerLifetime.characterTrove:Connect(humanoid.Died, function()
		if not isCurrent() then
			return
		end
		clearAffectedCharacter(player, character)
		presentation.Clear(character)
	end)
	playerLifetime.characterTrove:Connect(character.AncestryChanged, function(_, parent)
		if not parent and isCurrent() then
			clearAffectedCharacter(player, character)
		end
	end)
end

local function afterLoadoutCommit(player: Player, result: Types.TransactionResult)
	if not result.ok or result.replayed or not result.values or result.values.changed ~= true then
		return
	end
	local character = getAliveR15Character(player)
	if character then
		-- Combat retains its monotonic os.clock timebase; persisted transaction timestamps must
		-- never be used to reset or advance these cooldown/transition deadlines.
		local ok, problem = pcall(function()
			forceLowerGuard(player)
			applyResolvedLoadout(player, character)
		end)
		if not ok then
			-- The save already committed. Ownership/model identity checks fail closed on a stale
			-- model, without pretending the persisted action failed and encouraging another edit.
			log.error(`Loadout presentation failed for userId {player.UserId}`, problem)
		end
	end
end

local function equipOwnedInstance(player: Player, instanceId: unknown): (boolean, string?)
	-- Compatibility adapter for the existing instance-only endpoint. New callers retain their
	-- own revision-bound request IDs through EquipEquipment; this adapter never writes live data.
	if type(instanceId) ~= "string" or #instanceId == 0 or #instanceId > 128 then
		return false, "InvalidEquipment"
	end
	local data = DataService.GetLoadedData(player)
	if not data then
		return false, "NotReady"
	end
	local entry = if type(data.equipment) == "table" then data.equipment[instanceId] else nil
	local item = if type(entry) == "table"
		then EquipmentCatalog.Resolve(entry.definitionId, entry.finishId)
		else nil
	if not item then
		return false, "NotOwned"
	end
	local revision = if type(data.transactions) == "table" then data.transactions.revision else 0
	local result = CombatService.EquipEquipment(player, {
		requestId = `{revision}:{HttpService:GenerateGUID(false)}`,
		expectedRevision = revision,
		instanceId = instanceId,
		expectedDefinitionId = item.definitionId,
		expectedFinishId = item.finishId,
	})
	return result.ok, result.code
end

local function onPlayerAdded(player: Player)
	if playerLifecycles[player] then
		return
	end
	local trove = lifecycle.trove:Extend()
	local playerLifetime: PlayerLifecycle = {
		trove = trove,
		characterTrove = trove:Extend(),
		characterGeneration = 0,
	}
	playerLifecycles[player] = playerLifetime
	trove:Connect(player.CharacterAdded, function(character)
		onCharacterAdded(player, character)
	end)
	trove:Connect(player.CharacterRemoving, function(character)
		clearAffectedCharacter(player, character)
	end)
	if player.Character then
		local character = player.Character
		trove:Add(task.defer(function()
			-- Let profile loads unwind and release a late session instead of canceling that request.
			trove:Pop(coroutine.running())
			if
				playerLifecycles[player] == playerLifetime
				and player.Parent == Players
				and player.Character == character
			then
				onCharacterAdded(player, character)
			end
		end))
	end
end

local function onPlayerRemoving(player: Player)
	local playerLifetime = playerLifecycles[player]
	if playerLifetime then
		playerLifecycles[player] = nil
		lifecycle.trove:Remove(playerLifetime.trove)
	end
	if loadoutRequests then
		loadoutRequests.Forget(player)
	end
	local runtime: CombatRuntime? = runtimes[player]
	if runtime then
		restoreMovement(runtime)
	end
	local character = player.Character
	if character then
		clearShieldBubble(character)
		presentation.Clear(character)
		character:SetAttribute("ShieldGuarding", false)
		character:SetAttribute("CombatReady", false)
	end
	player:SetAttribute("KnockbackImmune", false)
	runtimes[player] = nil
	if loadoutLimiter then
		loadoutLimiter:Forget(player)
	end
	guardLimiter:Forget(player)
	startAttackLimiter:Forget(player)
	reportHitLimiter:Forget(player)
end

function CombatService.Init(serviceContext: ServerTypes.Context)
	local burst = LoadoutRequestsConfiguration.requestBurst
	local refill = LoadoutRequestsConfiguration.requestRefillPerSecond
	assert(
		type(burst) == "number"
			and burst >= 1
			and burst < math.huge
			and burst % 1 == 0
			and type(refill) == "number"
			and refill > 0
			and refill < math.huge,
		"[CombatService] Invalid loadout request tuning"
	)
	local requestLimiter = RateLimiter.new(burst, refill)
	loadoutLimiter = requestLimiter
	local observation = CombatRuntimeConfiguration.earthLanding
	assert(
		CombatRuntimeConfiguration.stateStepSeconds > 0
			and CombatRuntimeConfiguration.stateStepSeconds < math.huge
			and observation.supportAllowanceStuds >= 0
			and observation.supportAllowanceStuds < math.huge
			and observation.minimumGroundNormalY > 0
			and observation.minimumGroundNormalY <= 1
			and observation.takeoffVelocityStudsPerSecond >= 0
			and observation.takeoffVelocityStudsPerSecond < math.huge,
		"[CombatService] Invalid runtime observation tuning"
	)
	Equipment = serviceContext.Configurations.Equipment
	DataService = serviceContext.Services.DataService
	loadoutCommands = LoadoutCommands.new(DataService)
	equipmentAssets = serviceContext.Instances.EquipmentAssets
	presentation = EquipmentPresentation.new(equipmentAssets, Equipment.definitions)
	startAttack = serviceContext.Remotes.Combat.StartAttack
	reportHit = serviceContext.Remotes.Combat.ReportHit
	setShieldGuardRemote = serviceContext.Remotes.Combat.SetShieldGuard
	combatReaction = serviceContext.Remotes.Combat.Reaction
	combatImpact = serviceContext.Remotes.Combat.Impact
	getLoadoutRemote = serviceContext.Remotes.Combat.GetLoadout
	equipRemote = serviceContext.Remotes.Combat.Equip
	equipEquipmentRemote = serviceContext.Remotes.Combat.EquipEquipment
	unequipEquipmentRemote = serviceContext.Remotes.Combat.UnequipEquipment
	loadoutRequests = LoadoutRequests.new({
		DataService = DataService,
		isAvailable = function(player)
			return lifecycle:IsRunning()
				and typeof(player) == "Instance"
				and player:IsA("Player")
				and player.Parent == Players
		end,
		allowRequest = function(player)
			return requestLimiter:Allow(player)
		end,
		snapshotLoadout = snapshotLoadout,
		equipOwnedInstance = equipOwnedInstance,
		equipEquipment = function(player: Player, input: unknown): Types.TransactionResult
			-- Canonical commands validate these untrusted payloads before any transaction edit.
			return CombatService.EquipEquipment(player, input :: Types.EquipEquipmentRequest)
		end,
		unequipEquipment = function(player: Player, input: unknown): Types.TransactionResult
			return CombatService.UnequipEquipment(player, input :: Types.UnequipEquipmentRequest)
		end,
	})
	arena = serviceContext.Instances.Arena
end

function CombatService.Start()
	if not lifecycle:Start() then
		return
	end
	local trove = lifecycle.trove
	serviceTrove = trove
	local requests = assert(loadoutRequests, "[CombatService] Init must precede Start")
	local getRemote = assert(getLoadoutRemote, "[CombatService] GetLoadout is not initialized")
	local legacyEquipRemote = assert(equipRemote, "[CombatService] Equip is not initialized")
	local equipCommandRemote =
		assert(equipEquipmentRemote, "[CombatService] EquipEquipment is not initialized")
	local unequipCommandRemote =
		assert(unequipEquipmentRemote, "[CombatService] UnequipEquipment is not initialized")

	for _, authoringName in { "R15WeaponPositioningRig", "WeaponPosePreview" } do
		local authoringInstance = workspace:FindFirstChild(authoringName)
		if authoringInstance then
			authoringInstance:Destroy()
		end
	end

	getRemote.OnServerInvoke = requests.Get
	legacyEquipRemote.OnServerInvoke = requests.Equip
	equipCommandRemote.OnServerInvoke = requests.EquipEquipment
	unequipCommandRemote.OnServerInvoke = requests.UnequipEquipment

	trove:Connect(setShieldGuardRemote.OnServerEvent, handleGuardRequest)
	trove:Connect(startAttack.OnServerEvent, function(player: Player, payload: unknown)
		if startAttackLimiter:Allow(player) then
			handleMeleeSwing(player, payload)
		end
	end)
	trove:Connect(reportHit.OnServerEvent, function(player: Player, payload: unknown)
		if reportHitLimiter:Allow(player) then
			handleHitReport(player, payload)
		end
	end)

	local stateAccumulator = 0
	trove:Connect(RunService.Heartbeat, function(deltaTime: number)
		local now = os.clock()
		-- Landing observation runs every server frame, independently of throttled publication.
		-- Its token and character identity remain fixed across subsequent hits/equipment/Arena changes.
		for player, runtime in runtimes do
			observeEarth(player, runtime, now)
		end
		stateAccumulator += deltaTime
		if stateAccumulator < CombatRuntimeConfiguration.stateStepSeconds then
			return
		end
		stateAccumulator %= CombatRuntimeConfiguration.stateStepSeconds
		for _, player in Players:GetPlayers() do
			updateArenaCombatState(player)
			refreshRuntime(player, now)
		end
	end)

	trove:Connect(Players.PlayerAdded, onPlayerAdded)
	trove:Connect(Players.PlayerRemoving, onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		trove:Add(task.defer(function()
			trove:Pop(coroutine.running())
			if player.Parent == Players then
				onPlayerAdded(player)
			end
		end))
	end
end

function CombatService.Stop()
	if not lifecycle:Stop() then
		return
	end
	loadoutCommands = nil
	if getLoadoutRemote then
		RemoteUtil.ClearServerHandler(getLoadoutRemote)
	end
	if equipRemote then
		RemoteUtil.ClearServerHandler(equipRemote)
	end
	if equipEquipmentRemote then
		RemoteUtil.ClearServerHandler(equipEquipmentRemote)
	end
	if unequipEquipmentRemote then
		RemoteUtil.ClearServerHandler(unequipEquipmentRemote)
	end
	if serviceTrove then
		serviceTrove:Destroy()
		serviceTrove = nil
	end
	for player in pairs(playerLifecycles) do
		onPlayerRemoving(player)
	end
	if loadoutLimiter then
		loadoutLimiter:Clear()
	end
	if loadoutRequests then
		loadoutRequests.Clear()
	end
	loadoutLimiter = nil
	loadoutRequests = nil
	guardLimiter:Clear()
	startAttackLimiter:Clear()
	reportHitLimiter:Clear()
end

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

function CombatService.EquipEquipment(
	player: Player,
	request: Types.EquipEquipmentRequest
): Types.TransactionResult
	local commands = loadoutCommands
	if not commands or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = commands.Equip(player, request)
	afterLoadoutCommit(player, result)
	return result
end

function CombatService.UnequipEquipment(
	player: Player,
	request: Types.UnequipEquipmentRequest
): Types.TransactionResult
	local commands = loadoutCommands
	if not commands or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = commands.Unequip(player, request)
	afterLoadoutCommit(player, result)
	return result
end

return CombatService
