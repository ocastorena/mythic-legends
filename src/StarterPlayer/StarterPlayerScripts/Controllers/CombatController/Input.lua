--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/Input

local Input = {}
local stopImpl: (() -> ())?
local Types = require(script.Parent.Parent.Parent.Types)
local SharedTypes = require(game:GetService("ReplicatedStorage").Shared.Types)
local combatView: Types.CombatActionView?
local isRunning = false
local generation = 0

function Input.BindView(newView: Types.CombatActionView): () -> ()
	assert(
		combatView == nil or combatView == newView,
		"[CombatController.Input] A combat action view is already bound"
	)
	combatView = newView
	return function()
		if combatView == newView then
			combatView = nil
		end
	end
end

function Input.Init(_context: unknown) end

function Input.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	-- Local R15 input, animation, blade contact, and target-owned launch presentation.

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")

	local Equipment = require(
		ReplicatedStorage:WaitForChild("Shared")
			:WaitForChild("Configurations")
			:WaitForChild("Equipment")
	)
	local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
	local equipmentAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Equipment")
	local client = script.Parent.Parent.Parent
	local Knockback = require(script.Parent.Knockback)
	local MeleeHitbox = require(script.Parent.MeleeHitbox)
	local ShieldSlide = require(script.Parent.ShieldSlide)
	local PresentationBus = require(script.Parent.PresentationBus)
	local ui = client:WaitForChild("UI")
	local ModalState = require(ui:WaitForChild("State"):WaitForChild("ModalState"))
	local EquipmentPreviewUtil = require(ui:WaitForChild("EquipmentPreviewUtil"))
	local combatNetwork = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Combat")
	local startAttack = combatNetwork:WaitForChild("StartAttack") :: RemoteEvent
	local reportHit = combatNetwork:WaitForChild("ReportHit") :: RemoteEvent
	local setShieldGuard = combatNetwork:WaitForChild("SetShieldGuard") :: RemoteEvent
	local combatReaction = combatNetwork:WaitForChild("Reaction") :: RemoteEvent
	local localPlayer = Players.LocalPlayer
	local lifecycleTrove = Trove.new()
	if not isRunning or generation ~= currentGeneration then
		return
	end
	local characterTrove = lifecycleTrove:Extend()
	local activeAttackTrove = lifecycleTrove:Extend()
	local activeGuardTrove = lifecycleTrove:Extend()

	local NORMAL_BUTTON_COLOR = Color3.fromRGB(60, 60, 64)
	local PRESSED_BUTTON_COLOR = Color3.fromRGB(48, 48, 52)
	local BLADE_SWEEP_SAMPLES = 6
	local MAX_OVERLAP_PARTS = 100
	local HITBOX_PADDING = Vector3.new(0.1, 0.1, 0.1)

	local TRANSITION_ANIMATIONS = table.freeze({ sheath = "", unsheath = "" })

	local animationCache: { [string]: Animation } = {}
	local lastAttackAt = 0
	local nextSwingSequence = 0
	local activeTransitionTrack: AnimationTrack? = nil
	local activeAttackTrack: AnimationTrack? = nil
	local attackToken = 0
	local isGuardRequested = false
	local guardToken = 0
	local activeGuardRaiseTrack: AnimationTrack? = nil
	local activeGuardHoldTrack: AnimationTrack? = nil
	local activeGuardLowerTrack: AnimationTrack? = nil

	local function getCharacter(): Model?
		return localPlayer.Character
	end

	local function getAnimator(character: Model): Animator?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
			return nil
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
			or humanoid:WaitForChild("Animator", 2)
		return if animator and animator:IsA("Animator") then animator else nil
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
		if
			not animator
			or not isRunning
			or generation ~= currentGeneration
			or localPlayer.Character ~= character
		then
			return nil
		end
		local animation = animationCache[animationId]
		if not animation then
			local created = Instance.new("Animation")
			created.AnimationId = animationId
			animationCache[animationId] = created
			animation = created
			lifecycleTrove:Add(created)
		end
		local success, track = pcall(animator.LoadAnimation, animator, animation)
		if not success then
			warn(`[CombatController.Input] Could not load animation {animationId}: {track}`)
			return nil
		end
		track.Priority = priority or Enum.AnimationPriority.Action
		local trackLifetime = lifecycleTrove:Extend()
		trackLifetime:Add(track)
		trackLifetime:Connect(track.Ended, function()
			if activeTransitionTrack == track then
				activeTransitionTrack = nil
			end
			if activeAttackTrack == track then
				activeAttackTrack = nil
			end
			if activeGuardRaiseTrack == track then
				activeGuardRaiseTrack = nil
			end
			if activeGuardHoldTrack == track then
				activeGuardHoldTrack = nil
			end
			if activeGuardLowerTrack == track then
				activeGuardLowerTrack = nil
			end
			lifecycleTrove:Remove(trackLifetime)
		end)
		track:Play(0.08)
		return track
	end

	local function getEquipped(character: Model, hand: string): string
		local value = character:GetAttribute(`{hand}Equipped`)
		return if type(value) == "string" then value else ""
	end

	local function getProfile(character: Model, hand: string): SharedTypes.EquipmentProfile?
		return Equipment.profiles[getEquipped(character, hand)]
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

	local function setWeaponTrail(weapon: Model?, isEnabled: boolean)
		local trail = weapon and weapon:FindFirstChild("Trail", true)
		if trail and trail:IsA("Trail") then
			trail.Enabled = isEnabled
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
		activeAttackTrove:Clean()
		if activeAttackTrack then
			activeAttackTrack:Stop(0.05)
			activeAttackTrack = nil
		end
	end

	local function disconnectGuardConnections()
		activeGuardTrove:Clean()
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

	local function getShieldProfile(character: Model): SharedTypes.EquipmentProfile?
		local profile = getProfile(character, "Left")
		return if profile and profile.kind == "Shield" then profile else nil
	end

	local function startGuardHold(character: Model, expectedToken: number)
		if
			not isGuardRequested
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
		local track = profile
			and playAnimation(character, profile.holdAnimationId, Enum.AnimationPriority.Action4)
		if track then
			if not isGuardRequested or guardToken ~= expectedToken then
				track:Stop(0)
				return
			end
			track.Looped = true
			activeGuardHoldTrack = track
		end
	end

	local function beginGuard(character: Model)
		if isGuardRequested or character:GetAttribute("CombatReady") ~= true then
			return
		end
		local profile = getShieldProfile(character)
		if not profile or not getEquipmentModel(character, "Left") then
			return
		end

		clearActiveAttack()
		stopGuardTracks(0.04)
		isGuardRequested = true
		guardToken += 1
		local expectedToken = guardToken

		local hasTransitioned = false
		local function transitionToHold()
			if hasTransitioned or not isRunning or generation ~= currentGeneration then
				return
			end
			hasTransitioned = true
			disconnectGuardConnections()
			-- Protection and the replicated bubble begin at the authored GuardRaised frame.
			setShieldGuard:FireServer(true)
			startGuardHold(character, expectedToken)
		end

		local track =
			playAnimation(character, profile.raiseAnimationId, Enum.AnimationPriority.Action4)
		if not isGuardRequested or guardToken ~= expectedToken or not isRunning then
			if track then
				track:Stop(0)
			end
			return
		end
		activeGuardRaiseTrack = track
		if not track then
			transitionToHold()
			return
		end
		track.Looped = false
		activeGuardTrove:Connect(track:GetMarkerReachedSignal("GuardRaised"), transitionToHold)
		activeGuardTrove:Connect(track.Stopped, transitionToHold)
	end

	local function endGuard(character: Model?, shouldPlayLower: boolean)
		if not isGuardRequested then
			return
		end
		isGuardRequested = false
		guardToken += 1
		stopGuardTracks(0.08)

		if not shouldPlayLower or not character or localPlayer.Character ~= character then
			setShieldGuard:FireServer(false)
			return
		end
		local profile = getShieldProfile(character)
		local track = profile
			and playAnimation(character, profile.lowerAnimationId, Enum.AnimationPriority.Action4)
		activeGuardLowerTrack = track
		if track then
			track.Looped = false
			local hasLowered = false
			local function finishLower()
				if hasLowered then
					return
				end
				hasLowered = true
				-- Keep protection active through the lowering motion, then remove the bubble.
				setShieldGuard:FireServer(false)
				if activeGuardLowerTrack == track then
					activeGuardLowerTrack = nil
				end
			end
			activeGuardTrove:Connect(track:GetMarkerReachedSignal("GuardLowered"), finishLower)
			activeGuardTrove:Connect(track.Stopped, finishLower)
		else
			setShieldGuard:FireServer(false)
		end
	end

	local function playCombatTransition(character: Model, isBecomingReady: boolean)
		if not isBecomingReady then
			endGuard(character, true)
		end
		clearActiveAttack()
		if activeTransitionTrack then
			activeTransitionTrack:Stop(0.05)
			activeTransitionTrack = nil
		end
		local track = playAnimation(
			character,
			if isBecomingReady then TRANSITION_ANIMATIONS.unsheath else TRANSITION_ANIMATIONS.sheath
		)
		if track then
			track.Looped = false
			activeTransitionTrack = track
			lifecycleTrove:Add(task.delay(1, function()
				if activeTransitionTrack == track then
					track:Stop(0.1)
					activeTransitionTrack = nil
				end
			end))
		end
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
		if
			character:GetAttribute("CombatReady") ~= true
			or character:GetAttribute("ShieldGuarding") == true
			or isGuardRequested
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
		if
			now - lastAttackAt
			< (profile.cooldownSeconds or Equipment.presentationDefaults.cooldownSeconds)
		then
			return
		end
		lastAttackAt = now
		clearActiveAttack()
		activeAttackTrove:Add(function()
			setWeaponTrail(weapon, false)
		end)
		local currentToken = attackToken
		nextSwingSequence += 1
		local sequence = nextSwingSequence
		local hasReportedHit = false
		local hasOpenedWindow = false
		local isWindowClosed = false
		local hasPlayedSound = false

		local function isCurrentAttack(): boolean
			return isRunning
				and generation == currentGeneration
				and attackToken == currentToken
				and localPlayer.Character == character
				and character:GetAttribute("CombatReady") == true
		end

		local function closeContactWindow()
			isWindowClosed = true
			setWeaponTrail(weapon, false)
		end

		local function playSwingSound()
			if not hasPlayedSound and isCurrentAttack() then
				hasPlayedSound = true
				playWeaponSound(weapon)
			end
		end

		local function openContactWindow()
			if hasOpenedWindow or isWindowClosed or not isCurrentAttack() then
				return
			end
			hasOpenedWindow = true
			playSwingSound()
			setWeaponTrail(weapon, true)
			activeAttackTrove:Add(task.defer(function()
				local previousCFrame = hitbox.CFrame
				local activeUntil = os.clock()
					+ math.max(
						0.05,
						profile.contactWindowSeconds
							or Equipment.presentationDefaults.contactWindowSeconds
					)
				while
					isCurrentAttack()
					and not isWindowClosed
					and not hasReportedHit
					and os.clock() <= activeUntil
				do
					RunService.RenderStepped:Wait()
					if not isCurrentAttack() or isWindowClosed then
						break
					end
					local target = MeleeHitbox.FindClosestTarget({
						attacker = localPlayer,
						character = character,
						hitbox = hitbox,
						previousCFrame = previousCFrame,
						samples = BLADE_SWEEP_SAMPLES,
						padding = HITBOX_PADDING,
						maxParts = MAX_OVERLAP_PARTS,
						requireLineOfSight = profile.requireLineOfSight == true,
					})
					previousCFrame = hitbox.CFrame
					if target and target.Character then
						hasReportedHit = true
						local blockingShield = getPredictedBlockingShield(target)
						if blockingShield then
							PresentationBus.Fire(
								"LocalShieldImpact",
								target.Character,
								blockingShield,
								sequence
							)
						else
							PresentationBus.Fire(
								"LocalImpact",
								target.Character,
								profile.impactSoundId,
								sequence
							)
						end
						local track = activeAttackTrack
						if track and (profile.hitStopSeconds or 0) > 0 then
							track:AdjustSpeed(0)
							activeAttackTrove:Add(
								task.delay(
									math.clamp(profile.hitStopSeconds or 0, 0, 0.08),
									function()
										if activeAttackTrack == track and track.IsPlaying then
											track:AdjustSpeed(1)
										end
									end
								)
							)
						end
						reportHit:FireServer({
							sequence = sequence,
							targetUserId = target.UserId,
						})
					end
				end
				closeContactWindow()
			end))
		end

		-- Activation is charged by the server immediately, including a swing that misses.
		startAttack:FireServer({ sequence = sequence })
		local track = playAnimation(character, profile.animationId, Enum.AnimationPriority.Action)
		if not isCurrentAttack() then
			if track then
				track:Stop(0)
			end
			return
		end
		activeAttackTrack = track
		if track then
			track.Looped = false
			activeAttackTrove:Connect(track:GetMarkerReachedSignal("SwingSound"), playSwingSound)
			activeAttackTrove:Connect(track:GetMarkerReachedSignal("TrailStart"), function()
				if isCurrentAttack() then
					setWeaponTrail(weapon, true)
				end
			end)
			activeAttackTrove:Connect(track:GetMarkerReachedSignal("HitStart"), openContactWindow)
			activeAttackTrove:Connect(track:GetMarkerReachedSignal("HitEnd"), closeContactWindow)
			activeAttackTrove:Connect(track:GetMarkerReachedSignal("TrailEnd"), closeContactWindow)
			activeAttackTrove:Connect(track.Stopped, closeContactWindow)
		end
		activeAttackTrove:Add(
			task.delay(
				profile.hitStartFallbackSeconds
					or Equipment.presentationDefaults.hitStartFallbackSeconds,
				function()
					if isCurrentAttack() then
						openContactWindow()
					end
				end
			)
		)
		activeAttackTrove:Add(
			task.delay(
				(
					profile.hitStartFallbackSeconds
					or Equipment.presentationDefaults.hitStartFallbackSeconds
				)
					+ (
						profile.contactWindowSeconds
						or Equipment.presentationDefaults.contactWindowSeconds
					),
				function()
					if isCurrentAttack() then
						closeContactWindow()
					end
				end
			)
		)
	end

	local function numberOr(value: unknown, fallback: number): number
		return if type(value) == "number" or type(value) == "string"
			then tonumber(value) or fallback
			else fallback
	end

	local function applyLaunch(rawPayload: unknown)
		if type(rawPayload) ~= "table" then
			return
		end
		local payload = rawPayload :: { [string]: unknown }
		if type(payload.hitId) ~= "number" or typeof(payload.launchVelocity) ~= "Vector3" then
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
				numberOr(
					payload.slideDurationSeconds,
					Equipment.presentationDefaults.slideDurationSeconds
				)
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
			if typeof(payload.angularVelocity) == "Vector3"
				then payload.angularVelocity
				else Vector3.zero,
			numberOr(payload.controlSeconds, Equipment.presentationDefaults.launchControlSeconds),
			numberOr(
				payload.maximumReactionSeconds,
				Equipment.presentationDefaults.maximumReactionSeconds
			),
			numberOr(
				payload.landingRecoverySeconds,
				Equipment.presentationDefaults.landingRecoverySeconds
			),
			function()
				PresentationBus.Fire("Landed", character, nil, payload.hitId)
			end
		)
	end

	lifecycleTrove:Connect(combatReaction.OnClientEvent, function(payload: unknown)
		applyLaunch(payload)
	end)

	local function createCombatButtons()
		if not UserInputService.TouchEnabled then
			return
		end
		local view = combatView
		assert(view, "[CombatController.Input] Combat action view must be bound before Start")
		local root = view.root :: Frame
		local attackButton = view.attackButton :: ImageButton
		local attackIcon = view.attackIcon :: Frame
		local shieldButton = view.shieldButton :: ImageButton
		local shieldIcon = view.shieldIcon :: Frame
		local renderedRightEquipment = ""
		local renderedLeftEquipment = ""
		local function renderEquipment(icon: Frame, definitionId: string)
			EquipmentPreviewUtil.Clear(icon)
			local profile = Equipment.profiles[definitionId]
			local asset = profile and equipmentAssets:FindFirstChild(profile.modelName)
			if asset then
				EquipmentPreviewUtil.Render(icon, asset)
			end
		end
		local function getButtonAvailability(): (boolean, boolean, boolean)
			local character = getCharacter()
			local isReady = character ~= nil and character:GetAttribute("CombatReady") == true
			local rightProfile = character and getProfile(character, "Right")
			local leftProfile = character and getProfile(character, "Left")
			local canAttack = isReady
				and rightProfile
				and rightProfile.kind == "PrimaryWeapon"
				and getEquipmentModel(character :: Model, "Right") ~= nil
			local canGuard = isReady
				and leftProfile
				and leftProfile.kind == "Shield"
				and getEquipmentModel(character :: Model, "Left") ~= nil
			return isReady, canAttack == true, canGuard == true
		end

		lifecycleTrove:Connect(attackButton.Activated, function()
			if not ModalState.AnyOpen() then
				local character = getCharacter()
				local _, canAttack = getButtonAvailability()
				if character and canAttack then
					attack(character)
				end
			end
		end)
		local isShieldButtonHeld = false
		local function lowerShieldButton()
			if not isShieldButtonHeld then
				return
			end
			isShieldButtonHeld = false
			if isGuardRequested then
				endGuard(getCharacter(), true)
			end
		end
		lifecycleTrove:Connect(shieldButton.MouseButton1Down, function()
			if isShieldButtonHeld or ModalState.AnyOpen() then
				return
			end
			local character = getCharacter()
			local _, _, canGuard = getButtonAvailability()
			if character and canGuard then
				isShieldButtonHeld = true
				beginGuard(character)
			end
		end)
		lifecycleTrove:Connect(shieldButton.MouseButton1Up, lowerShieldButton)
		lifecycleTrove:Connect(UserInputService.InputEnded, function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				lowerShieldButton()
			end
		end)
		local isModalOpen = ModalState.AnyOpen()
		local disconnectModal = ModalState.OnChanged(function(isOpen: boolean)
			isModalOpen = isOpen
			if isOpen then
				lowerShieldButton()
			end
		end)
		lifecycleTrove:Add(function()
			disconnectModal()
		end)
		local elapsed = 0
		lifecycleTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
			elapsed += deltaTime
			if elapsed < 0.1 then
				return
			end
			elapsed = 0
			local isReady, canAttack, canGuard = getButtonAvailability()
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
			root.Visible = isReady and not isModalOpen
			attackButton.Interactable = canAttack and not isModalOpen
			shieldButton.Interactable = canGuard and not isModalOpen
			attackButton.BackgroundTransparency = if canAttack then 0.12 else 0.5
			shieldButton.BackgroundTransparency = if canGuard then 0.12 else 0.5
			shieldButton.BackgroundColor3 = if isGuardRequested
				then PRESSED_BUTTON_COLOR
				else NORMAL_BUTTON_COLOR
			view.relayout()
		end)
		view.relayout()
	end

	lifecycleTrove:Connect(
		UserInputService.InputBegan,
		function(input: InputObject, wasGameProcessed: boolean)
			if wasGameProcessed or UserInputService:GetFocusedTextBox() or ModalState.AnyOpen() then
				return
			end
			local character = getCharacter()
			if not character then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				attack(character)
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				if not isGuardRequested then
					beginGuard(character)
				end
			end
		end
	)

	lifecycleTrove:Connect(UserInputService.InputEnded, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and isGuardRequested then
			endGuard(getCharacter(), true)
		end
	end)

	local function bindCharacter(character: Model)
		characterTrove:Clean()
		if isGuardRequested then
			setShieldGuard:FireServer(false)
		end
		isGuardRequested = false
		guardToken += 1
		stopGuardTracks(0)
		clearActiveAttack()
		if activeTransitionTrack then
			activeTransitionTrack:Stop(0)
		end
		activeTransitionTrack = nil
		lastAttackAt = 0
		local wasCombatReady = character:GetAttribute("CombatReady") == true
		characterTrove:Connect(character:GetAttributeChangedSignal("CombatReady"), function()
			local isCombatReady = character:GetAttribute("CombatReady") == true
			if isCombatReady ~= wasCombatReady then
				wasCombatReady = isCombatReady
				playCombatTransition(character, isCombatReady)
			end
		end)
		local wasShieldGuarding = character:GetAttribute("ShieldGuarding") == true
		characterTrove:Connect(character:GetAttributeChangedSignal("ShieldGuarding"), function()
			local isShieldGuarding = character:GetAttribute("ShieldGuarding") == true
			if wasShieldGuarding and not isShieldGuarding and isGuardRequested then
				endGuard(character, true)
			end
			wasShieldGuarding = isShieldGuarding
		end)
	end

	lifecycleTrove:Connect(localPlayer.CharacterAdded, bindCharacter)
	if localPlayer.Character then
		lifecycleTrove:Add(task.defer(bindCharacter, localPlayer.Character))
	end
	lifecycleTrove:Add(task.defer(createCombatButtons))

	stopImpl = function()
		if isGuardRequested then
			setShieldGuard:FireServer(false)
		end
		isGuardRequested = false
		guardToken += 1
		Knockback.ClearAll()
		ShieldSlide.ClearAll()
		if activeTransitionTrack then
			activeTransitionTrack:Stop(0)
			activeTransitionTrack:Destroy()
			activeTransitionTrack = nil
		end
		clearActiveAttack()
		stopGuardTracks(0)
		lifecycleTrove:Destroy()
	end
end

function Input.Stop()
	isRunning = false
	generation += 1
	if stopImpl then
		stopImpl()
		stopImpl = nil
	end
end

return Input
