-- ServerScriptService/ServerModules/EquipmentStateService
-- Server-owned R15 loadouts, Arena state, Stamina, guard validation, and hit authorization.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Equipment: any
local ArenaBounds: any
local DataManager: any
local EquipmentAssets: Folder
local PerformAttack: RemoteEvent
local SetShieldGuard: RemoteEvent
local CombatImpact: RemoteEvent
local CombatLoadoutRequest: RemoteFunction
local Arena: BasePart

local EquipmentStateService = {}
EquipmentStateService.Priority = 20

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

type ImpactReactionType = "Launch" | "ShieldSlide"

type CombatRuntime = {
	stamina: number,
	lastStaminaUpdate: number,
	immunityUntil: number,
	nextAttackAt: number,
	nextGuardAt: number,
	lastSwingSequence: number,
	lastHitSequence: number,
	authorizedSwing: AuthorizedSwing?,
	movement: MovementState?,
}

local runtimes: { [Player]: CombatRuntime } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}
local playerConnections: { [Player]: RBXScriptConnection } = {}
local nextLoadoutRequestAt: { [Player]: number } = {}
local nextHitId = 0
local serviceConnections: { RBXScriptConnection } = {}

local function getNumber(value: any, fallback: number, minimum: number, maximum: number): number
	if type(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function getProfile(definitionId: unknown): any?
	if type(definitionId) ~= "string" or #definitionId > 64 then
		return nil
	end
	local profile = Equipment.Profiles[definitionId]
	return if type(profile) == "table" then profile else nil
end

local function getAliveR15Character(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character
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
		Equipment.Combat.arenaHeightAllowanceStuds,
		DEFAULT_ARENA_HEIGHT_ALLOWANCE,
		0,
		100
	)
	return root ~= nil and root:IsA("BasePart") and ArenaBounds.Contains(Arena, root.Position, allowance)
end

local function getRuntime(player: Player): CombatRuntime
	local runtime = runtimes[player]
	if runtime then
		return runtime
	end
	runtime = {
		stamina = getNumber(Equipment.Combat.staminaMaximum, 100, 1, 10_000),
		lastStaminaUpdate = os.clock(),
		immunityUntil = 0,
		nextAttackAt = 0,
		nextGuardAt = 0,
		lastSwingSequence = 0,
		lastHitSequence = 0,
		authorizedSwing = nil,
		movement = nil,
	}
	runtimes[player] = runtime
	return runtime
end

local function refreshRuntime(player: Player, now: number): CombatRuntime
	local runtime = getRuntime(player)
	local maximum = getNumber(Equipment.Combat.staminaMaximum, 100, 1, 10_000)
	local regen = getNumber(Equipment.Combat.staminaRegenPerSecond, 18, 0, 1_000)
	local elapsed = math.max(0, now - runtime.lastStaminaUpdate)
	runtime.lastStaminaUpdate = now
	runtime.stamina = math.min(maximum, runtime.stamina + elapsed * regen)
	if runtime.authorizedSwing and now > runtime.authorizedSwing.expiresAt then
		runtime.authorizedSwing = nil
	end
	player:SetAttribute("CombatStamina", runtime.stamina)
	player:SetAttribute("MaxCombatStamina", maximum)
	player:SetAttribute("KnockbackImmune", now < runtime.immunityUntil)
	return runtime
end

local function spendStamina(player: Player, amount: number, now: number): boolean
	local runtime = refreshRuntime(player, now)
	if runtime.stamina + 0.001 < amount then
		return false
	end
	runtime.stamina = math.max(0, runtime.stamina - amount)
	player:SetAttribute("CombatStamina", runtime.stamina)
	return true
end

local function spendStaminaUpTo(player: Player, amount: number, now: number): number
	local runtime = refreshRuntime(player, now)
	runtime.stamina = math.max(0, runtime.stamina - math.min(runtime.stamina, amount))
	player:SetAttribute("CombatStamina", runtime.stamina)
	return runtime.stamina
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
	TweenService:Create(
		bubble,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Size = Vector3.one * SHIELD_BUBBLE_SIZE,
			Transparency = 0.48,
		}
	):Play()
end

local function getEquipmentAndLoadout(player: Player): (any, any)
	return DataManager.GetSection(player, "equipment"), DataManager.GetSection(player, "combatLoadout")
end

local function getOwnedDefinition(equipment: any, instanceId: unknown, expectedKind: string): string?
	if type(instanceId) ~= "string" or instanceId == "" then
		return nil
	end
	local entry = equipment[instanceId]
	local definitionId = type(entry) == "table" and entry.definitionId or nil
	local profile = getProfile(definitionId)
	return if profile and profile.kind == expectedKind then definitionId else nil
end

local function findOwnedInstance(equipment: any, expectedKind: string): string?
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
		DataManager.MarkDirty(player)
	end
	return getOwnedDefinition(equipment, primaryInstanceId, "PrimaryWeapon") or "",
		getOwnedDefinition(equipment, shieldInstanceId, "Shield") or ""
end

local function snapshotLoadout(player: Player): any
	local equipment, loadout = getEquipmentAndLoadout(player)
	local entries = {}
	for instanceId, entry in equipment do
		local definitionId = type(entry) == "table" and entry.definitionId or nil
		if type(instanceId) == "string" and getProfile(definitionId) then
			table.insert(entries, {
				instanceId = instanceId,
				definitionId = definitionId,
			})
		end
	end
	table.sort(entries, function(a, b)
		return a.instanceId < b.instanceId
	end)
	return {
		equipment = entries,
		primaryWeaponInstanceId = loadout.primaryWeaponInstanceId,
		shieldInstanceId = loadout.shieldInstanceId,
	}
end

local function getEquipmentFolder(character: Model): Folder
	local existing = character:FindFirstChild(EQUIPMENT_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = EQUIPMENT_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function clearEquipment(character: Model)
	local folder = character:FindFirstChild(EQUIPMENT_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	for _, motorName in { "RightHandMotor", "LeftHandMotor", "RightSheathMotor", "LeftSheathMotor" } do
		local motor = character:FindFirstChild(motorName, true)
		if motor and motor:IsA("Motor6D") then
			motor:Destroy()
		end
	end
end

local function prepareEquipmentModel(model: Model): boolean
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		warn(`[EquipmentStateManager] {model:GetFullName()} has no PrimaryPart`)
		return false
	end
	for _, attachmentName in { "HandGripAttachment", "SheathAttachment" } do
		local attachment = model:FindFirstChild(attachmentName, true)
		if not attachment or not attachment:IsA("Attachment") then
			warn(`[EquipmentStateManager] {model:GetFullName()} needs {attachmentName}`)
			return false
		end
	end
	local hitbox = model:FindFirstChild("Hitbox", true)
	if not hitbox or not hitbox:IsA("BasePart") then
		warn(`[EquipmentStateManager] {model:GetFullName()} needs a Hitbox BasePart`)
		return false
	end
	-- Rebuild one predictable rigid assembly instead of stacking runtime welds on top of
	-- authored preview welds each time the Equipment moves between hand and sheath.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") then
			descendant:Destroy()
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= primaryPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "EquipmentAssemblyWeld"
				weld.Part0 = primaryPart
				weld.Part1 = descendant
				weld.Parent = primaryPart
			end
		end
	end
	return true
end

local function cloneEquipment(character: Model, slot: string, definitionId: string): Model?
	local profile = getProfile(definitionId)
	local asset = profile and EquipmentAssets:FindFirstChild(profile.modelName)
	if not asset or not asset:IsA("Model") then
		warn(`[EquipmentStateManager] Missing authored Equipment model for {definitionId}`)
		return nil
	end
	local model = asset:Clone()
	model.Name = `{slot}Equipment`
	model:SetAttribute("EquipmentId", definitionId)
	model:SetAttribute("EquipmentSlot", slot)
	if not prepareEquipmentModel(model) then
		model:Destroy()
		return nil
	end
	model.Parent = getEquipmentFolder(character)
	return model
end

local function authoredOffset(model: Model, attachmentName: string): CFrame?
	local attachment = model:FindFirstChild(attachmentName, true)
	local primaryPart = model.PrimaryPart
	if attachment and attachment:IsA("Attachment") and primaryPart then
		return primaryPart.CFrame:ToObjectSpace(attachment.WorldCFrame)
	end
	return nil
end

local function createMotor(name: string, parent: BasePart, part0: BasePart, part1: BasePart, offset: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C1 = offset
	motor.Parent = parent
end

local function attachSlot(character: Model, slot: string, definitionId: string, combatReady: boolean)
	if definitionId == "" then
		return
	end
	local model = cloneEquipment(character, slot, definitionId)
	local primaryPart = model and model.PrimaryPart
	if not model or not primaryPart then
		return
	end
	if combatReady then
		local hand = character:FindFirstChild(`{slot}Hand`)
		local offset = authoredOffset(model, "HandGripAttachment")
		if hand and hand:IsA("BasePart") and offset then
			createMotor(`{slot}HandMotor`, hand, hand, primaryPart, offset)
		else
			model:Destroy()
		end
	else
		local torso = character:FindFirstChild("UpperTorso")
		local offset = authoredOffset(model, "SheathAttachment")
		if torso and torso:IsA("BasePart") and offset then
			createMotor(`{slot}SheathMotor`, torso, torso, primaryPart, offset)
		else
			model:Destroy()
		end
	end
end

local function rebuildAttachments(character: Model)
	clearEquipment(character)
	local combatReady = character:GetAttribute("CombatReady") == true
	attachSlot(character, "Right", character:GetAttribute("RightEquipped") or "", combatReady)
	attachSlot(character, "Left", character:GetAttribute("LeftEquipped") or "", combatReady)
end

local function applyResolvedLoadout(player: Player, character: Model)
	local primaryId, shieldId = resolveLoadout(player)
	character:SetAttribute("RightEquipped", primaryId)
	character:SetAttribute("LeftEquipped", shieldId)
	getRuntime(player).authorizedSwing = nil
	rebuildAttachments(character)
end

local function setShieldGuard(player: Player, enabled: boolean): boolean
	local runtime = getRuntime(player)
	if not enabled then
		local character = player.Character
		if character then
			character:SetAttribute("ShieldGuarding", false)
			clearShieldBubble(character)
		end
		restoreMovement(runtime)
		return true
	end
	local character, humanoid, root = getAliveR15Character(player)
	if not character
		or not humanoid
		or not root
		or character:GetAttribute("CombatReady") ~= true
		or not isCharacterInArena(character)
	then
		return false
	end
	local profile = getProfile(character:GetAttribute("LeftEquipped"))
	local shieldMotor = character:FindFirstChild("LeftHandMotor", true)
	if not profile or profile.kind ~= "Shield" or not shieldMotor or not shieldMotor:IsA("Motor6D") then
		return false
	end
	if runtime.movement then
		character:SetAttribute("ShieldGuarding", true)
		if not character:FindFirstChild(SHIELD_BUBBLE_NAME) then
			createShieldBubble(character, root)
		end
		return true
	end
	local now = os.clock()
	if now < runtime.nextGuardAt then
		return false
	end
	runtime.nextGuardAt = now + getNumber(profile.activationCooldownSeconds, 0.2, 0, 5)
	runtime.authorizedSwing = nil
	runtime.movement = {
		character = character,
		humanoid = humanoid,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	character:SetAttribute("ShieldGuarding", true)
	createShieldBubble(character, root)
	return true
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
	setShieldGuard(player, false)
	local runtime = getRuntime(player)
	runtime.authorizedSwing = nil
	character:SetAttribute("CombatReady", shouldBeReady)
	rebuildAttachments(character)
end

local function isValidSequence(value: any): boolean
	return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= MAX_SEQUENCE
end

local function getEquippedPrimary(character: Model): (string?, any?)
	local definitionId = character:GetAttribute("RightEquipped")
	local profile = getProfile(definitionId)
	if type(definitionId) ~= "string" or not profile or profile.kind ~= "PrimaryWeapon" then
		return nil, nil
	end
	local folder = character:FindFirstChild(EQUIPMENT_FOLDER_NAME)
	local model = folder and folder:FindFirstChild("RightEquipment")
	local motor = character:FindFirstChild("RightHandMotor", true)
	if not model
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
	if not attackerRoot or not attackerRoot:IsA("BasePart") or not targetRoot or not targetRoot:IsA("BasePart") then
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

local function withinGuardArc(attackerRoot: BasePart, targetRoot: BasePart, degrees: number): boolean
	local offset = attackerRoot.Position - targetRoot.Position
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local facing = targetRoot.CFrame.LookVector
	local planarFacing = Vector3.new(facing.X, 0, facing.Z)
	if planarOffset.Magnitude <= 0.001 or planarFacing.Magnitude <= 0.001 then
		return false
	end
	return planarFacing.Unit:Dot(planarOffset.Unit) >= math.cos(math.rad(math.clamp(degrees, 0, 360) * 0.5))
end

local function handleMeleeSwing(player: Player, payload: any)
	if type(payload) ~= "table" or not isValidSequence(payload.sequence) then
		return
	end
	local character = getAliveR15Character(player)
	if not character
		or character:GetAttribute("CombatReady") ~= true
		or character:GetAttribute("ShieldGuarding") == true
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
	if payload.sequence <= runtime.lastSwingSequence or now < runtime.nextAttackAt then
		return
	end
	local staminaCost = getNumber(profile.staminaCost, 0, 0, 1_000)
	if not spendStamina(player, staminaCost, now) then
		return
	end
	local cooldown = getNumber(profile.cooldownSeconds, 0.72, 0.05, MAX_COOLDOWN)
	local window = getNumber(profile.contactWindowSeconds, 0.22, 0.05, 2)
	runtime.lastSwingSequence = payload.sequence
	runtime.nextAttackAt = now + cooldown
	runtime.authorizedSwing = {
		sequence = payload.sequence,
		weaponId = weaponId,
		expiresAt = now + window + 0.75,
	}
end

local function sendImpact(
	attacker: Player,
	target: Player,
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
	profile: any
)
	nextHitId += 1
	local hitId = nextHitId
	CombatImpact:FireClient(target, "ApplyLaunch", {
		hitId = hitId,
		launchVelocity = launchVelocity,
		angularVelocity = angularVelocity,
		controlSeconds = controlSeconds,
		reactionType = reactionType,
		slideDurationSeconds = slideDurationSeconds,
		maximumReactionSeconds = maximumReactionSeconds,
		landingRecoverySeconds = landingRecoverySeconds,
	})
	CombatImpact:FireAllClients("Impact", {
		hitId = hitId,
		targetUserId = target.UserId,
		attackerUserId = attacker.UserId,
		sequence = sequence,
		blocked = blocked,
		airTrailSeconds = airTrailSeconds,
		impactSoundId = profile.impactSoundId,
	})
end

local function handleHitReport(player: Player, payload: any)
	if type(payload) ~= "table"
		or not isValidSequence(payload.sequence)
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
	if not attackerCharacter
		or not attackerRoot
		or not targetCharacter
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
	if not authorization
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
	if (targetRoot.Position - attackerRoot.Position).Magnitude > maxDistance
		or (profile.requireLineOfSight == true and not hasLineOfSight(attackerCharacter, targetCharacter))
	then
		return
	end

	-- The accepted sequence is consumed exactly once before resolving Shield behavior.
	runtime.authorizedSwing = nil
	runtime.lastHitSequence = payload.sequence

	local directionDelta = targetRoot.Position - attackerRoot.Position
	local planar = Vector3.new(directionDelta.X, 0, directionDelta.Z)
	local attackerFacing = Vector3.new(attackerRoot.CFrame.LookVector.X, 0, attackerRoot.CFrame.LookVector.Z)
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
	local shieldDepleted = false
	local shieldProfile = getProfile(targetCharacter:GetAttribute("LeftEquipped"))
	if targetCharacter:GetAttribute("ShieldGuarding") == true
		and targetCharacter:FindFirstChild(SHIELD_BUBBLE_NAME) ~= nil
		and shieldProfile
		and shieldProfile.kind == "Shield"
		and withinGuardArc(attackerRoot, targetRoot, getNumber(shieldProfile.blockArcDegrees, 110, 0, 360))
	then
		blocked = true
		shieldDepleted = spendStaminaUpTo(
			target,
			getNumber(shieldProfile.impactStaminaCost, 30, 0, 1_000),
			now
		) <= 0.001
		reactionType = "ShieldSlide"
		launchVelocity = direction * getNumber(shieldProfile.slideKnockback, 28, 0, 100)
		controlSeconds = 0
		slideDurationSeconds = getNumber(shieldProfile.slideDurationSeconds, 0.32, 0.08, 0.75)
	else
		launchVelocity = direction * getNumber(profile.planarKnockback, 56, 0, 100)
			+ Vector3.yAxis * getNumber(profile.verticalKnockback, 58, 0, 100)
		local tumbleAxis = Vector3.yAxis:Cross(direction)
		if tumbleAxis.Magnitude > 0.001 then
			angularVelocity = tumbleAxis.Unit * getNumber(profile.tumbleAngularSpeed, 5.5, 0, 20)
		end
		controlSeconds = getNumber(profile.launchControlSeconds, 0.1, 0.05, 0.5)
		maximumReactionSeconds = getNumber(profile.maximumReactionSeconds, 3.5, 0.1, 10)
		landingRecoverySeconds = getNumber(profile.landingRecoverySeconds, 0.2, 0, 2)
		airTrailSeconds = getNumber(profile.airTrailSeconds, 3.5, 0, 10)
	end
	local immunity = getNumber(Equipment.Combat.knockbackImmunitySeconds, 0.65, 0, 5)
	targetRuntime.immunityUntil = now + immunity
	target:SetAttribute("KnockbackImmune", immunity > 0)
	sendImpact(
		player,
		target,
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
	if blocked and shieldDepleted then
		-- Let the final bubble spark finish, then lower the depleted guard automatically.
		task.delay(0.5, function()
			if target.Character == targetCharacter and targetCharacter:GetAttribute("ShieldGuarding") == true then
				setShieldGuard(target, false)
			end
		end)
	end
end

local function performAttack(player: Player, action: unknown, payload: unknown)
	if action == "MeleeSwing" then
		handleMeleeSwing(player, payload)
	elseif action == "HitReport" then
		handleHitReport(player, payload)
	end
end

local function disconnectCharacterConnections(player: Player)
	local connections = characterConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
end

local function onCharacterAdded(player: Player, character: Model)
	local priorRuntime = runtimes[player]
	if priorRuntime then
		restoreMovement(priorRuntime)
	end
	runtimes[player] = nil
	disconnectCharacterConnections(player)
	character:SetAttribute("CombatReady", false)
	character:SetAttribute("ShieldGuarding", false)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(`[EquipmentStateManager] {player.Name} must use an R15 character`)
		return
	end
	refreshRuntime(player, os.clock())
	applyResolvedLoadout(player, character)
	characterConnections[player] = {
		humanoid.Died:Connect(function()
			setShieldGuard(player, false)
			getRuntime(player).authorizedSwing = nil
			clearEquipment(character)
		end),
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				setShieldGuard(player, false)
				getRuntime(player).authorizedSwing = nil
			end
		end),
	}
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
	DataManager.MarkDirty(player)
	local character = player.Character
	if character then
		setShieldGuard(player, false)
		applyResolvedLoadout(player, character)
	end
	return true, nil
end

local function onPlayerAdded(player: Player)
	if playerConnections[player] then
		return
	end
	playerConnections[player] = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.defer(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local playerConnection = playerConnections[player]
	if playerConnection then
		playerConnection:Disconnect()
		playerConnections[player] = nil
	end
	disconnectCharacterConnections(player)
	nextLoadoutRequestAt[player] = nil
	local runtime = runtimes[player]
	if runtime then
		restoreMovement(runtime)
	end
	runtimes[player] = nil
end

function EquipmentStateService.Init(context: any)
	Equipment = context.Metadata.Equipment
	ArenaBounds = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("ArenaBounds"))
	DataManager = context.Services.DataManager
	EquipmentAssets = context.Instances.EquipmentAssets
	PerformAttack = context.Remotes.PerformAttack
	SetShieldGuard = context.Remotes.SetShieldGuard
	CombatImpact = context.Remotes.CombatImpact
	CombatLoadoutRequest = context.Remotes.CombatLoadoutRequest
	Arena = context.Instances.Arena
end

function EquipmentStateService.Start()
	for _, authoringName in { "R15WeaponPositioningRig", "WeaponPosePreview" } do
		local authoringInstance = workspace:FindFirstChild(authoringName)
		if authoringInstance then
			authoringInstance:Destroy()
		end
	end

	CombatLoadoutRequest.OnServerInvoke = function(player: Player, action: unknown, payload: unknown)
		if action == "Get" then
			resolveLoadout(player)
			return { ok = true, snapshot = snapshotLoadout(player) }
		elseif action == "Equip" then
			local now = os.clock()
			if now < (nextLoadoutRequestAt[player] or 0) then
				return { ok = false, reason = "RateLimited", snapshot = snapshotLoadout(player) }
			end
			nextLoadoutRequestAt[player] = now + 0.5
			local instanceId = type(payload) == "table" and payload.instanceId or nil
			local ok, reason = equipOwnedInstance(player, instanceId)
			return { ok = ok, reason = reason, snapshot = snapshotLoadout(player) }
		end
		return { ok = false, reason = "InvalidAction" }
	end

	table.insert(serviceConnections, SetShieldGuard.OnServerEvent:Connect(function(player: Player, enabled: unknown)
		if type(enabled) == "boolean" then
			setShieldGuard(player, enabled)
		end
	end))
	table.insert(serviceConnections, PerformAttack.OnServerEvent:Connect(performAttack))

	local stateAccumulator = 0
	table.insert(serviceConnections, RunService.Heartbeat:Connect(function(deltaTime: number)
		stateAccumulator += deltaTime
		if stateAccumulator < STATE_STEP_SECONDS then
			return
		end
		stateAccumulator %= STATE_STEP_SECONDS
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			updateArenaCombatState(player)
			local runtime = refreshRuntime(player, now)
			local movement = runtime.movement
			if movement then
				if player.Character ~= movement.character
					or not movement.character.Parent
					or movement.humanoid.Health <= 0
					or movement.character:GetAttribute("CombatReady") ~= true
					or movement.character:GetAttribute("ShieldGuarding") ~= true
				then
					setShieldGuard(player, false)
				else
					movement.humanoid.WalkSpeed = 0
					movement.humanoid.JumpPower = 0
					movement.humanoid.JumpHeight = 0
					movement.humanoid.AutoRotate = false
				end
			end
		end
	end))

	table.insert(serviceConnections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(serviceConnections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	for _, player in Players:GetPlayers() do
		task.defer(onPlayerAdded, player)
	end
end

function EquipmentStateService.Stop()
	CombatLoadoutRequest.OnServerInvoke = nil
	for _, connection in serviceConnections do
		connection:Disconnect()
	end
	table.clear(serviceConnections)
	for player in pairs(playerConnections) do
		onPlayerRemoving(player)
	end
end

return EquipmentStateService
