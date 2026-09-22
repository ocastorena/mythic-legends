--!strict
-- ServerScriptService/Services/CombatService
-- Server-owned R15 loadouts, Arena state, Stamina, guard validation, and hit authorization.

local Players = game:GetService("Players")
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
local ServerTypes = require(ServerScriptService.Domain.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local EquipmentPresentation = require(script.EquipmentPresentation)
local ArenaBounds = require(script.ArenaBounds)
local CombatMath = require(script.CombatMath)
local CombatState = require(script.CombatState)
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
local getLoadoutRemote: RemoteFunction
local equipRemote: RemoteFunction
local arena: BasePart

local CombatService = {}

local EQUIPMENT_FOLDER_NAME = "EquippedEquipment"
local STATE_STEP_SECONDS = 0.1
local MAX_SEQUENCE = 2_147_483_647
local MAX_REACH = 20
local MAX_COOLDOWN = 5
local DEFAULT_ARENA_HEIGHT_ALLOWANCE = 20
local SHIELD_BUBBLE_NAME = "ShieldBubble"
local SHIELD_BUBBLE_SIZE = 9

type MovementState = {
	character: Model,
	humanoid: Humanoid,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
}

type AuthorizedSwing = {
	sequence: number,
	weaponId: string,
	expiresAt: number,
}

type ImpactReactionType = Types.CombatReactionType

type CombatRuntime = {
	accounting: CombatState.State,
	immunityUntil: number,
	guardShieldId: string?,
	lastSwingSequence: number,
	lastHitSequence: number,
	authorizedSwing: AuthorizedSwing?,
	movement: MovementState?,
}

type PlayerLifecycle = {
	trove: TroveInstance,
	characterTrove: TroveInstance,
	characterGeneration: number,
}

local runtimes: { [Player]: CombatRuntime } = {}
local playerLifecycles: { [Player]: PlayerLifecycle } = {}
local nextLoadoutRequestAt: { [Player]: number } = {}
local nextHitId = 0
local serviceTrove: TroveInstance?
local shieldTweens: { [Model]: Tween } = {}
local loadoutLimiter = RateLimiter.new(12, 4)
local guardLimiter = RateLimiter.new(16, 8)
local startAttackLimiter = RateLimiter.new(8, 4)
local reportHitLimiter = RateLimiter.new(12, 6)

local function getNumber(value: unknown, fallback: number, minimum: number, maximum: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function getProfile(definitionId: unknown): Types.EquipmentProfile?
	if type(definitionId) ~= "string" or #definitionId > 64 then
		return nil
	end
	local profile = Equipment.profiles[definitionId]
	return if type(profile) == "table" then profile else nil
end

local function getAliveR15Character(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		not character
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
		guardShieldId = nil,
		lastSwingSequence = 0,
		lastHitSequence = 0,
		authorizedSwing = nil,
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
	if movement.humanoid.Parent == movement.character and movement.humanoid.Health > 0 then
		movement.humanoid.WalkSpeed = movement.walkSpeed
		movement.humanoid.JumpPower = movement.jumpPower
		movement.humanoid.JumpHeight = movement.jumpHeight
		movement.humanoid.AutoRotate = movement.autoRotate
	end
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

type EquipmentEntries = { [string]: { definitionId: string } }
type Loadout = { primaryWeaponInstanceId: string?, shieldInstanceId: string? }
type LoadoutSnapshot = {
	equipment: { { instanceId: string, definitionId: string } },
	primaryWeaponInstanceId: string?,
	shieldInstanceId: string?,
}
type LoadoutResult = { ok: boolean, code: string?, snapshot: LoadoutSnapshot }
local function getEquipmentAndLoadout(player: Player): (EquipmentEntries, Loadout)
	return DataService.GetData(player).equipment, DataService.GetData(player).combatLoadout
end

local function getOwnedDefinition(
	equipment: EquipmentEntries,
	instanceId: unknown,
	expectedKind: string
): string?
	if type(instanceId) ~= "string" or instanceId == "" then
		return nil
	end
	local entry = equipment[instanceId]
	local definitionId = type(entry) == "table" and entry.definitionId or nil
	local profile = getProfile(definitionId)
	return if profile and profile.kind == expectedKind then definitionId else nil
end

local function findOwnedInstance(equipment: EquipmentEntries, expectedKind: string): string?
	local best: string? = nil
	for instanceId, entry in equipment do
		local definitionId = type(entry) == "table" and entry.definitionId or nil
		local profile = getProfile(definitionId)
		if type(instanceId) == "string" and profile and profile.kind == expectedKind then
			if not best or instanceId < best then
				best = instanceId
			end
		end
	end
	return best
end

local function resolveLoadout(player: Player): (string, string)
	local equipment, loadout = getEquipmentAndLoadout(player)
	local changed = false
	local primaryInstanceId = loadout.primaryWeaponInstanceId
	local shieldInstanceId = loadout.shieldInstanceId
	if not getOwnedDefinition(equipment, primaryInstanceId, "PrimaryWeapon") then
		primaryInstanceId = findOwnedInstance(equipment, "PrimaryWeapon")
		loadout.primaryWeaponInstanceId = primaryInstanceId
		changed = true
	end
	if not getOwnedDefinition(equipment, shieldInstanceId, "Shield") then
		shieldInstanceId = findOwnedInstance(equipment, "Shield")
		loadout.shieldInstanceId = shieldInstanceId
		changed = true
	end
	if changed then
		DataService.MarkDirty(player)
	end
	return getOwnedDefinition(equipment, primaryInstanceId, "PrimaryWeapon") or "",
		getOwnedDefinition(equipment, shieldInstanceId, "Shield") or ""
end

local function snapshotLoadout(player: Player): LoadoutSnapshot
	local equipment, loadout = getEquipmentAndLoadout(player)
	local entries: { { instanceId: string, definitionId: string } } = {}
	for instanceId, entry in equipment do
		local definitionId = type(entry) == "table" and entry.definitionId or nil
		if
			type(instanceId) == "string"
			and type(definitionId) == "string"
			and getProfile(definitionId)
		then
			table.insert(entries, {
				instanceId = instanceId,
				definitionId = definitionId,
			})
		end
	end
	table.sort(entries, function(a: { instanceId: string }, b: { instanceId: string })
		return a.instanceId < b.instanceId
	end)
	return {
		equipment = entries,
		primaryWeaponInstanceId = loadout.primaryWeaponInstanceId,
		shieldInstanceId = loadout.shieldInstanceId,
	}
end

local function getGuardProfile(player: Player): (string?, Types.EquipmentProfile?)
	local character = getAliveR15Character(player)
	local data = DataService.GetLoadedData(player)
	if not character or not data or not isCharacterInArena(character) then
		return nil, nil
	end
	local definitionId =
		getOwnedDefinition(data.equipment, data.combatLoadout.shieldInstanceId, "Shield")
	if not definitionId or character:GetAttribute("LeftEquipped") ~= definitionId then
		return nil, nil
	end
	local motor = character:FindFirstChild("LeftHandMotor", true)
	if not motor or not motor:IsA("Motor6D") then
		return nil, nil
	end
	return definitionId, getProfile(definitionId)
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
	if state.phase ~= "Lowered" and character and humanoid then
		if not runtime.movement then
			runtime.movement = {
				character = character,
				humanoid = humanoid,
				walkSpeed = humanoid.WalkSpeed,
				jumpPower = humanoid.JumpPower,
				jumpHeight = humanoid.JumpHeight,
				autoRotate = humanoid.AutoRotate,
			}
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	else
		restoreMovement(runtime)
	end
	local currentCharacter = player.Character
	if currentCharacter then
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
		local shieldId = getGuardProfile(player)
		if not shieldId or shieldId ~= runtime.guardShieldId then
			CombatState.ReleaseGuard(runtime.accounting, now, nil, true)
		end
	else
		runtime.guardShieldId = nil
	end
	if runtime.authorizedSwing and now > runtime.authorizedSwing.expiresAt then
		runtime.authorizedSwing = nil
	end
	publishRuntime(player, runtime, now)
	return runtime
end

local function forceLowerGuard(player: Player)
	local now = os.clock()
	local runtime = refreshRuntime(player, now)
	CombatState.ReleaseGuard(runtime.accounting, now, nil, true)
	runtime.authorizedSwing = nil
	publishRuntime(player, runtime, now)
end

local function applyResolvedLoadout(player: Player, character: Model)
	local primaryId, shieldId = resolveLoadout(player)
	character:SetAttribute("RightEquipped", primaryId)
	character:SetAttribute("LeftEquipped", shieldId)
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
		local shieldId, profile = getGuardProfile(player)
		local tuning = profile and shieldTuning(profile)
		local accepted = false
		if shieldId and tuning and character:GetAttribute("CombatReady") == true then
			accepted = CombatState.BeginGuard(runtime.accounting, now, sequence, tuning)
		end
		if accepted then
			runtime.guardShieldId = shieldId
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

local function getEquippedPrimary(character: Model): (string?, Types.EquipmentProfile?)
	local definitionId = character:GetAttribute("RightEquipped")
	local profile = getProfile(definitionId)
	if type(definitionId) ~= "string" or not profile or profile.kind ~= "PrimaryWeapon" then
		return nil, nil
	end
	local folder = character:FindFirstChild(EQUIPMENT_FOLDER_NAME)
	local model = folder and folder:FindFirstChild("RightEquipment")
	local motor = character:FindFirstChild("RightHandMotor", true)
	if
		not model
		or not model:IsA("Model")
		or model:GetAttribute("EquipmentId") ~= definitionId
		or not motor
		or not motor:IsA("Motor6D")
	then
		return nil, nil
	end
	return definitionId, profile
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
	local weaponId, profile = getEquippedPrimary(character)
	if not weaponId or not profile then
		return
	end
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
		weaponId = weaponId,
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
	local weaponId, profile = getEquippedPrimary(attackerCharacter)
	if not weaponId or not profile then
		return
	end
	local now = os.clock()
	local runtime = refreshRuntime(player, now)
	local authorization = runtime.authorizedSwing
	if
		not authorization
		or authorization.sequence ~= payload.sequence
		or authorization.weaponId ~= weaponId
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
	local shieldProfile = getProfile(targetCharacter:GetAttribute("LeftEquipped"))
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
		launchVelocity = direction * getNumber(profile.planarKnockback, 56, 0, 100)
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
	playerLifetime.characterTrove:Add(function()
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
		forceLowerGuard(player)
		getRuntime(player).authorizedSwing = nil
		presentation.Clear(character)
	end)
	playerLifetime.characterTrove:Connect(character.AncestryChanged, function(_, parent)
		if not parent and isCurrent() then
			forceLowerGuard(player)
			getRuntime(player).authorizedSwing = nil
		end
	end)
end

local function equipOwnedInstance(player: Player, instanceId: unknown): (boolean, string?)
	if type(instanceId) ~= "string" then
		return false, "InvalidEquipment"
	end
	local equipment, loadout = getEquipmentAndLoadout(player)
	local entry = equipment[instanceId]
	local definitionId = type(entry) == "table" and entry.definitionId or nil
	local profile = getProfile(definitionId)
	if not profile then
		return false, "NotOwned"
	end
	if profile.kind == "PrimaryWeapon" then
		loadout.primaryWeaponInstanceId = instanceId
	elseif profile.kind == "Shield" then
		loadout.shieldInstanceId = instanceId
	else
		return false, "UnsupportedEquipment"
	end
	DataService.MarkDirty(player)
	local character = player.Character
	if character then
		forceLowerGuard(player)
		applyResolvedLoadout(player, character)
	end
	return true, nil
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
	nextLoadoutRequestAt[player] = nil
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
	loadoutLimiter:Forget(player)
	guardLimiter:Forget(player)
	startAttackLimiter:Forget(player)
	reportHitLimiter:Forget(player)
end

function CombatService.Init(serviceContext: ServerTypes.Context)
	Equipment = serviceContext.Configurations.Equipment
	DataService = serviceContext.Services.DataService
	equipmentAssets = serviceContext.Instances.EquipmentAssets
	presentation = EquipmentPresentation.new(equipmentAssets, Equipment.profiles)
	startAttack = serviceContext.Remotes.Combat.StartAttack
	reportHit = serviceContext.Remotes.Combat.ReportHit
	setShieldGuardRemote = serviceContext.Remotes.Combat.SetShieldGuard
	combatReaction = serviceContext.Remotes.Combat.Reaction
	combatImpact = serviceContext.Remotes.Combat.Impact
	getLoadoutRemote = serviceContext.Remotes.Combat.GetLoadout
	equipRemote = serviceContext.Remotes.Combat.Equip
	arena = serviceContext.Instances.Arena
end

function CombatService.Start()
	if not lifecycle:Start() then
		return
	end
	local trove = lifecycle.trove
	serviceTrove = trove

	for _, authoringName in { "R15WeaponPositioningRig", "WeaponPosePreview" } do
		local authoringInstance = workspace:FindFirstChild(authoringName)
		if authoringInstance then
			authoringInstance:Destroy()
		end
	end

	getLoadoutRemote.OnServerInvoke = function(player: Player): LoadoutResult?
		if
			not DataService.Load(player)
			or not lifecycle:IsRunning()
			or player.Parent ~= Players
		then
			return nil
		end
		if not loadoutLimiter:Allow(player) then
			return { ok = false, code = "RateLimited", snapshot = snapshotLoadout(player) }
		end
		resolveLoadout(player)
		return { ok = true, snapshot = snapshotLoadout(player) }
	end
	equipRemote.OnServerInvoke = function(player: Player, instanceId: unknown): LoadoutResult?
		if
			not DataService.Load(player)
			or not lifecycle:IsRunning()
			or player.Parent ~= Players
		then
			return nil
		end
		if not loadoutLimiter:Allow(player) then
			return { ok = false, code = "RateLimited", snapshot = snapshotLoadout(player) }
		end
		local now = os.clock()
		if now < (nextLoadoutRequestAt[player] or 0) then
			return { ok = false, code = "RateLimited", snapshot = snapshotLoadout(player) }
		end
		nextLoadoutRequestAt[player] = now + 0.5
		local ok, reason = equipOwnedInstance(player, instanceId)
		return { ok = ok, code = reason, snapshot = snapshotLoadout(player) }
	end

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
		stateAccumulator += deltaTime
		if stateAccumulator < STATE_STEP_SECONDS then
			return
		end
		stateAccumulator %= STATE_STEP_SECONDS
		local now = os.clock()
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
	RemoteUtil.ClearServerHandler(getLoadoutRemote)
	RemoteUtil.ClearServerHandler(equipRemote)
	if serviceTrove then
		serviceTrove:Destroy()
		serviceTrove = nil
	end
	for player in pairs(playerLifecycles) do
		onPlayerRemoving(player)
	end
	loadoutLimiter:Clear()
	guardLimiter:Clear()
	startAttackLimiter:Clear()
	reportHitLimiter:Clear()
end

return CombatService
