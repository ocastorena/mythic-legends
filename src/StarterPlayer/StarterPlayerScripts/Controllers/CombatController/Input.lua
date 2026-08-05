-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/Input

local Input = {}
local stopImpl: (() -> ())?
local combatView: any

function Input.BindView(newView: any): () -> ()
	assert(combatView == nil or combatView == newView, "[CombatController] A combat action view is already bound")
	combatView = newView
	return function()
		if combatView == newView then
			combatView = nil
		end
	end
end

function Input.Init(_context: unknown)
end

function Input.Start()
-- Local R15 input, animation, blade contact, and target-owned launch presentation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Equipment = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configurations"):WaitForChild("Equipment"))
local EquipmentAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Equipment")
local Client = script:FindFirstAncestor("Controllers").Parent
local Knockback = require(script.Parent.Knockback)
local ShieldSlide = require(script.Parent.ShieldSlide)
local PresentationBus = require(script.Parent.PresentationBus)
local Ui = Client:WaitForChild("UI")
local ModalUtil = require(Ui:WaitForChild("ModalUtil"))
local EquipmentPreviewUtil = require(Ui:WaitForChild("EquipmentPreviewUtil"))
local CombatNetwork = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Combat")
local StartAttack = CombatNetwork:WaitForChild("StartAttack") :: RemoteEvent
local ReportHit = CombatNetwork:WaitForChild("ReportHit") :: RemoteEvent
local SetShieldGuard = CombatNetwork:WaitForChild("SetShieldGuard") :: RemoteEvent
local CombatReaction = CombatNetwork:WaitForChild("Reaction") :: RemoteEvent
local localPlayer = Players.LocalPlayer
local lifecycleConnections: { RBXScriptConnection } = {}

local NORMAL_BUTTON_COLOR = Color3.fromRGB(60, 60, 64)
local PRESSED_BUTTON_COLOR = Color3.fromRGB(48, 48, 52)
local BLADE_SWEEP_SAMPLES = 6
local MAX_OVERLAP_PARTS = 100
local HITBOX_PADDING = Vector3.new(0.1, 0.1, 0.1)

local TRANSITION_ANIMATIONS = {
	Sheath = "",
	Unsheath = "",
}

local animationCache: { [string]: Animation } = {}
local lastAttackAt = 0
local nextSwingSequence = 0
local activeTransitionTrack: AnimationTrack? = nil
local activeAttackTrack: AnimationTrack? = nil
local activeAttackConnections: { RBXScriptConnection } = {}
local attackToken = 0
local guardRequested = false
local guardToken = 0
local activeGuardRaiseTrack: AnimationTrack? = nil
local activeGuardHoldTrack: AnimationTrack? = nil
local activeGuardLowerTrack: AnimationTrack? = nil
local activeGuardConnections: { RBXScriptConnection } = {}
local combatReadyConnection: RBXScriptConnection? = nil
local shieldGuardingConnection: RBXScriptConnection? = nil
local disconnectModal: (() -> ())? = nil

local function getCharacter(): Model?
	return localPlayer.Character
end

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	return humanoid:FindFirstChildOfClass("Animator")
		or humanoid:WaitForChild("Animator", 2) :: Animator?
end

local function playAnimation(
	character: Model,
	animationId: string?,
	priority: Enum.AnimationPriority?
): AnimationTrack?
	if type(animationId) ~= "string" or animationId == "" then
		return nil
	end
	local animator = getAnimator(character)
	if not animator then
		return nil
	end
	local animation = animationCache[animationId]
	if not animation then
		animation = Instance.new("Animation")
		animation.AnimationId = animationId
		animationCache[animationId] = animation
	end
	local success, track = pcall(animator.LoadAnimation, animator, animation)
	if not success then
		warn(`[Input] Could not load animation {animationId}: {track}`)
		return nil
	end
	track.Priority = priority or Enum.AnimationPriority.Action
	track:Play(0.08)
	return track
end

local function getEquipped(character: Model, hand: string): string
	local value = character:GetAttribute(`{hand}Equipped`)
	return if type(value) == "string" then value else ""
end

local function getProfile(character: Model, hand: string): any?
	return Equipment.Profiles[getEquipped(character, hand)]
end

local function getEquipmentModel(character: Model, hand: string): Model?
	local folder = character:FindFirstChild("EquippedEquipment")
	local equipment = folder and folder:FindFirstChild(`{hand}Equipment`)
	return if equipment and equipment:IsA("Model") then equipment else nil
end

local function getWeaponHitbox(weapon: Model?): BasePart?
	local hitbox = weapon and weapon:FindFirstChild("Hitbox", true)
	return if hitbox and hitbox:IsA("BasePart") then hitbox else nil
end

local function setWeaponTrail(weapon: Model?, enabled: boolean)
	local trail = weapon and weapon:FindFirstChild("Trail", true)
	if trail and trail:IsA("Trail") then
		trail.Enabled = enabled
	end
end

local function playWeaponSound(weapon: Model?)
	local sound = weapon and weapon:FindFirstChild("SwordSlash", true)
	if sound and sound:IsA("Sound") then
		sound:Stop()
		sound.TimePosition = 0
		sound:Play()
	end
end

local function clearActiveAttack()
	attackToken += 1
	for _, connection in activeAttackConnections do
		connection:Disconnect()
	end
	table.clear(activeAttackConnections)
	if activeAttackTrack then
		activeAttackTrack:Stop(0.05)
		activeAttackTrack = nil
	end
end

local function disconnectGuardConnections()
	for _, connection in activeGuardConnections do
		connection:Disconnect()
	end
	table.clear(activeGuardConnections)
end

local function stopGuardTracks(fadeTime: number)
	disconnectGuardConnections()
	for _, track in { activeGuardRaiseTrack, activeGuardHoldTrack, activeGuardLowerTrack } do
		if track then
			track:Stop(fadeTime)
		end
	end
	activeGuardRaiseTrack = nil
	activeGuardHoldTrack = nil
	activeGuardLowerTrack = nil
end

local function getShieldProfile(character: Model): any?
	local profile = getProfile(character, "Left")
	return if profile and profile.kind == "Shield" then profile else nil
end

local function startGuardHold(character: Model, expectedToken: number)
	if not guardRequested
		or guardToken ~= expectedToken
		or localPlayer.Character ~= character
		or character:GetAttribute("CombatReady") ~= true
	then
		return
	end
	if activeGuardRaiseTrack then
		activeGuardRaiseTrack:Stop(0.06)
		activeGuardRaiseTrack = nil
	end
	local profile = getShieldProfile(character)
	local track = profile and playAnimation(character, profile.holdAnimationId, Enum.AnimationPriority.Action4)
	if track then
		track.Looped = true
		activeGuardHoldTrack = track
	end
end

local function beginGuard(character: Model)
	if guardRequested or character:GetAttribute("CombatReady") ~= true then
		return
	end
	local profile = getShieldProfile(character)
	if not profile or not getEquipmentModel(character, "Left") then
		return
	end

	clearActiveAttack()
	stopGuardTracks(0.04)
	guardRequested = true
	guardToken += 1
	local expectedToken = guardToken

	local transitioned = false
	local function transitionToHold()
		if transitioned then
			return
		end
		transitioned = true
		disconnectGuardConnections()
		-- Protection and the replicated bubble begin at the authored GuardRaised frame.
		SetShieldGuard:FireServer(true)
		startGuardHold(character, expectedToken)
	end

	local track = playAnimation(character, profile.raiseAnimationId, Enum.AnimationPriority.Action4)
	activeGuardRaiseTrack = track
	if not track then
		transitionToHold()
		return
	end
	track.Looped = false
	table.insert(activeGuardConnections, track:GetMarkerReachedSignal("GuardRaised"):Connect(transitionToHold))
	table.insert(activeGuardConnections, track.Stopped:Connect(transitionToHold))
end

local function endGuard(character: Model?, playLower: boolean)
	if not guardRequested then
		return
	end
	guardRequested = false
	guardToken += 1
	stopGuardTracks(0.08)

	if not playLower or not character or localPlayer.Character ~= character then
		SetShieldGuard:FireServer(false)
		return
	end
	local profile = getShieldProfile(character)
	local track = profile and playAnimation(character, profile.lowerAnimationId, Enum.AnimationPriority.Action4)
	activeGuardLowerTrack = track
	if track then
		track.Looped = false
		local lowered = false
		local function finishLower()
			if lowered then
				return
			end
			lowered = true
			-- Keep protection active through the lowering motion, then remove the bubble.
			SetShieldGuard:FireServer(false)
			if activeGuardLowerTrack == track then
				activeGuardLowerTrack = nil
			end
		end
		table.insert(activeGuardConnections, track:GetMarkerReachedSignal("GuardLowered"):Connect(finishLower))
		table.insert(activeGuardConnections, track.Stopped:Connect(finishLower))
	else
		SetShieldGuard:FireServer(false)
	end
end

local function playCombatTransition(character: Model, becomingReady: boolean)
	if not becomingReady then
		endGuard(character, true)
	end
	clearActiveAttack()
	if activeTransitionTrack then
		activeTransitionTrack:Stop(0.05)
		activeTransitionTrack = nil
	end
	local track = playAnimation(
		character,
		if becomingReady then TRANSITION_ANIMATIONS.Unsheath else TRANSITION_ANIMATIONS.Sheath
	)
	if track then
		track.Looped = false
		activeTransitionTrack = track
		task.delay(1, function()
			if activeTransitionTrack == track then
				track:Stop(0.1)
				activeTransitionTrack = nil
			end
		end)
	end
end

local function getPlayerFromPart(part: BasePart): Player?
	local ancestor: Instance? = part
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(ancestor)
			if player then
				return player
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
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

local function chooseBladeTarget(
	character: Model,
	profile: any,
	hitbox: BasePart,
	previousCFrame: CFrame
): Player?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.MaxParts = MAX_OVERLAP_PARTS
	local attackerRoot = character:FindFirstChild("HumanoidRootPart")
	local candidates: { [Player]: { contact: number, rootDistance: number } } = {}

	for sampleIndex = 1, BLADE_SWEEP_SAMPLES do
		local sample = previousCFrame:Lerp(hitbox.CFrame, sampleIndex / BLADE_SWEEP_SAMPLES)
		for _, part in workspace:GetPartBoundsInBox(sample, hitbox.Size + HITBOX_PADDING, params) do
			local target = getPlayerFromPart(part)
			local targetCharacter = target and target.Character
			local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
			if target
				and target ~= localPlayer
				and targetCharacter
				and humanoid
				and humanoid.Health > 0
				and targetCharacter:GetAttribute("CombatReady") == true
				and targetRoot
				and targetRoot:IsA("BasePart")
				and (profile.requireLineOfSight ~= true or hasLineOfSight(character, targetCharacter))
			then
				local contact = (part.Position - sample.Position).Magnitude
				local rootDistance = if attackerRoot and attackerRoot:IsA("BasePart")
					then (targetRoot.Position - attackerRoot.Position).Magnitude
					else math.huge
				local existing = candidates[target]
				if not existing or contact < existing.contact then
					candidates[target] = { contact = contact, rootDistance = rootDistance }
				end
			end
		end
	end

	local bestTarget: Player? = nil
	local bestContact = math.huge
	local bestRootDistance = math.huge
	for target, score in candidates do
		if score.contact < bestContact
			or (score.contact == bestContact and score.rootDistance < bestRootDistance)
			or (score.contact == bestContact and score.rootDistance == bestRootDistance
				and (not bestTarget or target.UserId < bestTarget.UserId))
		then
			bestTarget = target
			bestContact = score.contact
			bestRootDistance = score.rootDistance
		end
	end
	return bestTarget
end

local function getPredictedBlockingShield(target: Player): Model?
	local targetCharacter = target.Character
	if not targetCharacter or targetCharacter:GetAttribute("ShieldGuarding") ~= true then
		return nil
	end
	local shield = getEquipmentModel(targetCharacter, "Left")
	local bubble = targetCharacter:FindFirstChild("ShieldBubble")
	return if shield and bubble and bubble:IsA("BasePart") then shield else nil
end

local function attack(character: Model)
	if character:GetAttribute("CombatReady") ~= true
		or character:GetAttribute("ShieldGuarding") == true
		or guardRequested
	then
		return
	end
	local profile = getProfile(character, "Right")
	local weapon = getEquipmentModel(character, "Right")
	local hitbox = getWeaponHitbox(weapon)
	if not profile or profile.kind ~= "PrimaryWeapon" or not weapon or not hitbox then
		return
	end
	local stamina = localPlayer:GetAttribute("CombatStamina")
	if type(stamina) == "number" and stamina + 0.001 < (profile.staminaCost or 0) then
		return
	end
	local now = os.clock()
	if now - lastAttackAt < (profile.cooldownSeconds or 0.72) then
		return
	end
	lastAttackAt = now
	clearActiveAttack()
	local currentToken = attackToken
	nextSwingSequence += 1
	local sequence = nextSwingSequence
	local hitReported = false
	local windowOpened = false
	local windowClosed = false
	local soundPlayed = false

	local function isCurrentAttack(): boolean
		return attackToken == currentToken
			and localPlayer.Character == character
			and character:GetAttribute("CombatReady") == true
	end

	local function closeContactWindow()
		windowClosed = true
		setWeaponTrail(weapon, false)
	end

	local function playSwingSound()
		if not soundPlayed and isCurrentAttack() then
			soundPlayed = true
			playWeaponSound(weapon)
		end
	end

	local function openContactWindow()
		if windowOpened or windowClosed or not isCurrentAttack() then
			return
		end
		windowOpened = true
		playSwingSound()
		setWeaponTrail(weapon, true)
		task.spawn(function()
			local previousCFrame = hitbox.CFrame
			local activeUntil = os.clock() + math.max(0.05, profile.contactWindowSeconds or 0.22)
			while isCurrentAttack() and not windowClosed and not hitReported and os.clock() <= activeUntil do
				RunService.RenderStepped:Wait()
				local target = chooseBladeTarget(character, profile, hitbox, previousCFrame)
				previousCFrame = hitbox.CFrame
				if target and target.Character then
					hitReported = true
					local blockingShield = getPredictedBlockingShield(target)
					if blockingShield then
						PresentationBus.Fire("LocalShieldImpact", target.Character, blockingShield, sequence)
					else
						PresentationBus.Fire("LocalImpact", target.Character, profile.impactSoundId, sequence)
					end
					if activeAttackTrack and (profile.hitStopSeconds or 0) > 0 then
						local track = activeAttackTrack
						track:AdjustSpeed(0)
						task.delay(math.clamp(profile.hitStopSeconds, 0, 0.08), function()
							if activeAttackTrack == track and track.IsPlaying then
								track:AdjustSpeed(1)
							end
						end)
					end
					ReportHit:FireServer({
						sequence = sequence,
						targetUserId = target.UserId,
					})
				end
			end
			closeContactWindow()
		end)
	end

	-- Activation is charged by the server immediately, including a swing that misses.
	StartAttack:FireServer({ sequence = sequence })
	local track = playAnimation(character, profile.animationId, Enum.AnimationPriority.Action)
	activeAttackTrack = track
	if track then
		track.Looped = false
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("SwingSound"):Connect(playSwingSound))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("TrailStart"):Connect(function()
			if isCurrentAttack() then
				setWeaponTrail(weapon, true)
			end
		end))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("HitStart"):Connect(openContactWindow))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("HitEnd"):Connect(closeContactWindow))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("TrailEnd"):Connect(closeContactWindow))
		table.insert(activeAttackConnections, track.Stopped:Connect(closeContactWindow))
	end
	task.delay(profile.hitStartFallbackSeconds or 0.22, function()
		if isCurrentAttack() then
			openContactWindow()
		end
	end)
	task.delay((profile.hitStartFallbackSeconds or 0.22) + (profile.contactWindowSeconds or 0.22), function()
		if isCurrentAttack() then
			closeContactWindow()
		end
	end)
end

local function applyLaunch(payload: any)
	if type(payload) ~= "table"
		or type(payload.hitId) ~= "number"
		or typeof(payload.launchVelocity) ~= "Vector3"
	then
		return
	end
	local character = getCharacter()
	if not character then
		return
	end
	if payload.reactionType == "ShieldSlide" then
		Knockback.Clear(character)
		ShieldSlide.Apply(
			character,
			payload.hitId,
			payload.launchVelocity,
			tonumber(payload.slideDurationSeconds) or 0.32
		)
		return
	end
	if payload.reactionType ~= "Launch" then
		return
	end
	ShieldSlide.Clear(character)
	Knockback.Apply(
		character,
		payload.hitId,
		payload.launchVelocity,
		if typeof(payload.angularVelocity) == "Vector3" then payload.angularVelocity else Vector3.zero,
		tonumber(payload.controlSeconds) or 0.1,
		tonumber(payload.maximumReactionSeconds) or 3.5,
		tonumber(payload.landingRecoverySeconds) or 0.2,
		function()
			PresentationBus.Fire("Landed", character, nil, payload.hitId)
		end
	)
end

table.insert(lifecycleConnections, CombatReaction.OnClientEvent:Connect(function(payload: any)
	applyLaunch(payload)
end))

local function createCombatButtons()
	if not UserInputService.TouchEnabled then
		return
	end
	local view = combatView
	assert(view, "[CombatController] Combat action view must be bound before Start")
	local root = view.root :: Frame
	local attackButton = view.attackButton :: ImageButton
	local attackIcon = view.attackIcon :: Frame
	local shieldButton = view.shieldButton :: ImageButton
	local shieldIcon = view.shieldIcon :: Frame
	local renderedRightEquipment = ""
	local renderedLeftEquipment = ""
	local function renderEquipment(icon: Frame, definitionId: string)
		EquipmentPreviewUtil.Clear(icon)
		local profile = Equipment.Profiles[definitionId]
		local asset = profile and EquipmentAssets:FindFirstChild(profile.modelName)
		if asset then
			EquipmentPreviewUtil.Render(icon, asset)
		end
	end
	local function getButtonAvailability(): (boolean, boolean, boolean)
		local character = getCharacter()
		local ready = character ~= nil and character:GetAttribute("CombatReady") == true
		local rightProfile = character and getProfile(character, "Right")
		local leftProfile = character and getProfile(character, "Left")
		local canAttack = ready and rightProfile and rightProfile.kind == "PrimaryWeapon"
			and getEquipmentModel(character :: Model, "Right") ~= nil
		local canGuard = ready and leftProfile and leftProfile.kind == "Shield"
			and getEquipmentModel(character :: Model, "Left") ~= nil
		return ready, canAttack == true, canGuard == true
	end

	table.insert(lifecycleConnections, attackButton.Activated:Connect(function()
		if not ModalUtil.AnyOpen() then
			local character = getCharacter()
			local _, canAttack = getButtonAvailability()
			if character and canAttack then
				attack(character)
			end
		end
	end))
	local shieldButtonHeld = false
	local function lowerShieldButton()
		if not shieldButtonHeld then
			return
		end
		shieldButtonHeld = false
		if guardRequested then
			endGuard(getCharacter(), true)
		end
	end
	table.insert(lifecycleConnections, shieldButton.MouseButton1Down:Connect(function()
		if shieldButtonHeld or ModalUtil.AnyOpen() then return end
		local character = getCharacter()
		local _, _, canGuard = getButtonAvailability()
		if character and canGuard then
			shieldButtonHeld = true
			beginGuard(character)
		end
	end))
	table.insert(lifecycleConnections, shieldButton.MouseButton1Up:Connect(lowerShieldButton))
	table.insert(lifecycleConnections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			lowerShieldButton()
		end
	end))
	local modalOpen = ModalUtil.AnyOpen()
	disconnectModal = ModalUtil.OnChanged(function(isOpen: boolean)
		modalOpen = isOpen
		if isOpen then
			lowerShieldButton()
		end
	end)
	local elapsed = 0
	table.insert(lifecycleConnections, RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed < 0.1 then return end
		elapsed = 0
		local ready, canAttack, canGuard = getButtonAvailability()
		local character = getCharacter()
		local rightEquipment = if character then getEquipped(character, "Right") else ""
		local leftEquipment = if character then getEquipped(character, "Left") else ""
		if rightEquipment ~= renderedRightEquipment then
			renderedRightEquipment = rightEquipment
			renderEquipment(attackIcon, rightEquipment)
		end
		if leftEquipment ~= renderedLeftEquipment then
			renderedLeftEquipment = leftEquipment
			renderEquipment(shieldIcon, leftEquipment)
		end
		root.Visible = ready and not modalOpen
		attackButton.Interactable = canAttack and not modalOpen
		shieldButton.Interactable = canGuard and not modalOpen
		attackButton.BackgroundTransparency = if canAttack then 0.12 else 0.5
		shieldButton.BackgroundTransparency = if canGuard then 0.12 else 0.5
		shieldButton.BackgroundColor3 = if guardRequested then PRESSED_BUTTON_COLOR else NORMAL_BUTTON_COLOR
		view.relayout()
	end))
	view.relayout()
end

table.insert(lifecycleConnections, UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() or ModalUtil.AnyOpen() then
		return
	end
	local character = getCharacter()
	if not character then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attack(character)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not guardRequested then
			beginGuard(character)
		end
	end
end))

table.insert(lifecycleConnections, UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and guardRequested then
		endGuard(getCharacter(), true)
	end
end))

local function bindCharacter(character: Model)
	if combatReadyConnection then
		combatReadyConnection:Disconnect()
	end
	if shieldGuardingConnection then
		shieldGuardingConnection:Disconnect()
	end
	if guardRequested then
		SetShieldGuard:FireServer(false)
	end
	guardRequested = false
	guardToken += 1
	stopGuardTracks(0)
	clearActiveAttack()
	if activeTransitionTrack then
		activeTransitionTrack:Stop(0)
	end
	activeTransitionTrack = nil
	lastAttackAt = 0
	local wasCombatReady = character:GetAttribute("CombatReady") == true
	combatReadyConnection = character:GetAttributeChangedSignal("CombatReady"):Connect(function()
		local isCombatReady = character:GetAttribute("CombatReady") == true
		if isCombatReady ~= wasCombatReady then
			wasCombatReady = isCombatReady
			playCombatTransition(character, isCombatReady)
		end
	end)
	local wasShieldGuarding = character:GetAttribute("ShieldGuarding") == true
	shieldGuardingConnection = character:GetAttributeChangedSignal("ShieldGuarding"):Connect(function()
		local isShieldGuarding = character:GetAttribute("ShieldGuarding") == true
		if wasShieldGuarding and not isShieldGuarding and guardRequested then
			endGuard(character, true)
		end
		wasShieldGuarding = isShieldGuarding
	end)
end

table.insert(lifecycleConnections, localPlayer.CharacterAdded:Connect(bindCharacter))
if localPlayer.Character then
	task.defer(bindCharacter, localPlayer.Character)
end
task.defer(createCombatButtons)

stopImpl = function()
	for _, connection in lifecycleConnections do
		connection:Disconnect()
	end
	table.clear(lifecycleConnections)
	if combatReadyConnection then
		combatReadyConnection:Disconnect()
	end
	if shieldGuardingConnection then
		shieldGuardingConnection:Disconnect()
	end
	if disconnectModal then
		disconnectModal()
		disconnectModal = nil
	end
	clearActiveAttack()
	stopGuardTracks(0)
end
end

function Input.Stop()
	if stopImpl then
		stopImpl()
		stopImpl = nil
	end
end

return Input
