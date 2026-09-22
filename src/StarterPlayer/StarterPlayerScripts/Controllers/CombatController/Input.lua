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
	local lastAttackAt = -math.huge
	local attackLockedUntil = 0
	local nextSwingSequence = 0
	local activeTransitionTrack: AnimationTrack? = nil
	local activeAttackTrack: AnimationTrack? = nil
	local attackToken = 0
	local isGuardRequested = false
	local guardPhase = "Lowered"
	local nextGuardSequence = 0
	local activeGuardSequence: number? = nil
	local hasGuardAcknowledgement = false
	local isKeyboardGuardHeld = false
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

	local function isSwingLocked(character: Model): boolean
		return os.clock() < attackLockedUntil
			or (activeAttackTrack ~= nil and activeAttackTrack.IsPlaying)
			or character:GetAttribute("SwingLocked") == true
	end

	local function isFullyLowered(character: Model): boolean
		local serverPhase = character:GetAttribute("GuardPhase")
		return guardPhase == "Lowered"
			and (serverPhase == nil or serverPhase == "Lowered")
			and character:GetAttribute("ShieldGuarding") ~= true
	end

	local function hasGuardStamina(profile: SharedTypes.EquipmentProfile): boolean
		local stamina = localPlayer:GetAttribute("CombatStamina")
		local minimum = profile.minimumGuardStamina or profile.impactStaminaCost
		return type(stamina) == "number"
			and type(minimum) == "number"
			and minimum > 0
			and stamina >= minimum
	end

	local function delayGuard(seconds: number, callback: () -> ())
		local pending = task.delay(seconds, callback)
		-- A transition may clean its own phase from inside this callback.
		activeGuardTrove:Add(function()
			if coroutine.status(pending) == "suspended" then
				task.cancel(pending)
			end
		end)
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

	local function endGuard(character: Model?, shouldPlayLower: boolean)
		if guardPhase == "Lowered" or guardPhase == "Lowering" then
			return
		end
		local sequence = activeGuardSequence
		isGuardRequested = false
		guardPhase = "Lowering"
		guardToken += 1
		local expectedToken = guardToken
		stopGuardTracks(0.08)
		if sequence and character then
			-- Release ends held intent immediately, independently of the later visual marker.
			local request: SharedTypes.CombatGuardRequest = {
				action = "Release",
				sequence = sequence,
				character = character,
			}
			setShieldGuard:FireServer(request)
		end

		if not shouldPlayLower or not character or localPlayer.Character ~= character then
			guardPhase = "Lowered"
			return
		end
		local profile = getShieldProfile(character)
		local minimumSeconds = if profile then profile.lowerSeconds else nil
		local timeoutSeconds = if profile then profile.lowerTimeoutSeconds else nil
		local lowerSeconds = minimumSeconds or Equipment.presentationDefaults.lowerSeconds
		local lowerTimeout = timeoutSeconds or Equipment.presentationDefaults.lowerTimeoutSeconds
		local lowerStartedAt = os.clock()
		local hasLowered = false
		local isFinishScheduled = false
		local function finishLower()
			if
				hasLowered
				or guardToken ~= expectedToken
				or localPlayer.Character ~= character
				or not isRunning
			then
				return
			end
			local remaining = lowerSeconds - (os.clock() - lowerStartedAt)
			if remaining > 0 then
				if not isFinishScheduled then
					isFinishScheduled = true
					delayGuard(remaining, function()
						isFinishScheduled = false
						finishLower()
					end)
				end
				return
			end
			hasLowered = true
			if sequence then
				local request: SharedTypes.CombatGuardRequest = {
					action = "Lowered",
					sequence = sequence,
					character = character,
				}
				setShieldGuard:FireServer(request)
			end
			guardPhase = "Lowered"
			stopGuardTracks(0.05)
		end
		delayGuard(lowerTimeout, finishLower)
		local track = profile
			and playAnimation(character, profile.lowerAnimationId, Enum.AnimationPriority.Action4)
		if
			guardToken ~= expectedToken
			or hasLowered
			or localPlayer.Character ~= character
			or not isRunning
		then
			if track then
				track:Stop(0)
			end
			return
		end
		activeGuardLowerTrack = track
		if track then
			track.Looped = false
			activeGuardTrove:Connect(track:GetMarkerReachedSignal("GuardLowered"), finishLower)
			activeGuardTrove:Connect(track.Stopped, finishLower)
		else
			delayGuard(math.max(lowerSeconds - (os.clock() - lowerStartedAt), 0), finishLower)
		end
	end

	local function beginGuard(character: Model)
		if
			isGuardRequested
			or character:GetAttribute("CombatReady") ~= true
			or not isFullyLowered(character)
			or isSwingLocked(character)
		then
			return
		end
		local profile = getShieldProfile(character)
		if
			not profile
			or not getEquipmentModel(character, "Left")
			or not hasGuardStamina(profile)
		then
			return
		end

		stopGuardTracks(0.04)
		isGuardRequested = true
		guardPhase = "Raising"
		hasGuardAcknowledgement = false
		guardToken += 1
		local expectedToken = guardToken
		local latestRequest = character:GetAttribute("GuardRequestSequence")
		if type(latestRequest) == "number" then
			nextGuardSequence = math.max(nextGuardSequence, latestRequest)
		end
		nextGuardSequence += 1
		local sequence = nextGuardSequence
		activeGuardSequence = sequence
		-- Raising stops server recovery immediately, before animation loading can yield.
		local request: SharedTypes.CombatGuardRequest = {
			action = "Begin",
			sequence = sequence,
			character = character,
		}
		setShieldGuard:FireServer(request)

		local hasTransitioned = false
		local function transitionToHold()
			if
				hasTransitioned
				or not isRunning
				or generation ~= currentGeneration
				or guardToken ~= expectedToken
				or not isGuardRequested
				or localPlayer.Character ~= character
			then
				return
			end
			hasTransitioned = true
			local raisedRequest: SharedTypes.CombatGuardRequest = {
				action = "Raised",
				sequence = sequence,
				character = character,
			}
			setShieldGuard:FireServer(raisedRequest)
			startGuardHold(character, expectedToken)
		end
		local raiseSeconds = profile.raiseSeconds or Equipment.presentationDefaults.raiseSeconds
		local raiseTimeout = profile.raiseTimeoutSeconds
			or Equipment.presentationDefaults.raiseTimeoutSeconds
		delayGuard(raiseTimeout, function()
			if guardToken == expectedToken and guardPhase == "Raising" then
				endGuard(character, true)
			end
		end)
		local track =
			playAnimation(character, profile.raiseAnimationId, Enum.AnimationPriority.Action4)
		if not isGuardRequested or guardToken ~= expectedToken or not isRunning then
			if track then
				track:Stop(0)
			end
			return
		end
		activeGuardRaiseTrack = track
		if track then
			track.Looped = false
			activeGuardTrove:Connect(track:GetMarkerReachedSignal("GuardRaised"), transitionToHold)
			activeGuardTrove:Connect(track.Stopped, transitionToHold)
		else
			delayGuard(raiseSeconds, transitionToHold)
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
			or not isFullyLowered(character)
			or isSwingLocked(character)
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
		attackLockedUntil = now
			+ (profile.swingDurationSeconds or Equipment.presentationDefaults.swingDurationSeconds)
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
					local targetCharacter = target and target.Character
					if target and targetCharacter then
						hasReportedHit = true
						local blockingShield = getPredictedBlockingShield(target)
						if blockingShield then
							PresentationBus.Fire(
								"LocalShieldImpact",
								targetCharacter,
								blockingShield,
								sequence
							)
						else
							PresentationBus.Fire(
								"LocalImpact",
								targetCharacter,
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
						local hitReport: SharedTypes.CombatHitReport = {
							sequence = sequence,
							character = character,
							targetUserId = target.UserId,
							targetCharacter = targetCharacter,
						}
						reportHit:FireServer(hitReport)
					end
				end
				closeContactWindow()
			end))
		end

		-- Activation is charged by the server immediately, including a swing that misses.
		local attackRequest: SharedTypes.CombatAttackRequest = {
			sequence = sequence,
			character = character,
		}
		startAttack:FireServer(attackRequest)
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
		if not character or payload.character ~= character then
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
		local isShieldButtonHeld = false
		local shieldPress: InputObject? = nil
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
				and isFullyLowered(character :: Model)
				and not isSwingLocked(character :: Model)
				and os.clock() - lastAttackAt
					>= (rightProfile.cooldownSeconds or Equipment.presentationDefaults.cooldownSeconds)
			local stamina = localPlayer:GetAttribute("CombatStamina")
			if canAttack and rightProfile then
				canAttack = type(stamina) == "number" and stamina >= (rightProfile.staminaCost or 0)
			end
			local canGuard = isReady
				and leftProfile
				and leftProfile.kind == "Shield"
				and getEquipmentModel(character :: Model, "Left") ~= nil
				and isFullyLowered(character :: Model)
				and not isSwingLocked(character :: Model)
				and hasGuardStamina(leftProfile)
				and not isShieldButtonHeld
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
		local function lowerShieldButton()
			if not isShieldButtonHeld then
				return
			end
			isShieldButtonHeld = false
			shieldPress = nil
			endGuard(getCharacter(), true)
		end
		lifecycleTrove:Connect(shieldButton.InputBegan, function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1
			then
				return
			end
			if isShieldButtonHeld or ModalState.AnyOpen() then
				return
			end
			local character = getCharacter()
			local _, _, canGuard = getButtonAvailability()
			if character and canGuard then
				isShieldButtonHeld = true
				shieldPress = input
				beginGuard(character)
			end
		end)
		lifecycleTrove:Connect(UserInputService.InputEnded, function(input: InputObject)
			if input == shieldPress then
				lowerShieldButton()
			end
		end)
		lifecycleTrove:Connect(UserInputService.WindowFocusReleased, lowerShieldButton)
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
			shieldButton.Interactable = (canGuard or isShieldButtonHeld) and not isModalOpen
			attackButton.BackgroundTransparency = if canAttack then 0.12 else 0.5
			shieldButton.BackgroundTransparency = if canGuard or isGuardRequested then 0.12 else 0.5
			shieldButton.BackgroundColor3 = if isGuardRequested
				then PRESSED_BUTTON_COLOR
				else NORMAL_BUTTON_COLOR
			local shieldProfile = character and getShieldProfile(character)
			view.shieldStatus.Text = if not shieldProfile
				then ""
				elseif not hasGuardStamina(shieldProfile) then "Low Stamina"
				elseif guardPhase ~= "Lowered" then guardPhase
				elseif isShieldButtonHeld then "Release to retry"
				elseif character and isSwingLocked(character) then "Swing in progress"
				else "Hold to guard"
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
			elseif input.KeyCode == Enum.KeyCode.F then
				if not isKeyboardGuardHeld then
					isKeyboardGuardHeld = true
					beginGuard(character)
				end
			end
		end
	)

	lifecycleTrove:Connect(UserInputService.InputEnded, function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.F then
			isKeyboardGuardHeld = false
			endGuard(getCharacter(), true)
		end
	end)
	lifecycleTrove:Connect(UserInputService.WindowFocusReleased, function()
		endGuard(getCharacter(), true)
	end)
	lifecycleTrove:Connect(UserInputService.WindowFocused, function()
		isKeyboardGuardHeld = UserInputService:IsKeyDown(Enum.KeyCode.F)
	end)
	local disconnectGuardModal = ModalState.OnChanged(function(isOpen: boolean)
		if isOpen then
			endGuard(getCharacter(), true)
		end
	end)
	lifecycleTrove:Add(function()
		disconnectGuardModal()
	end)

	local function bindCharacter(character: Model)
		characterTrove:Clean()
		isGuardRequested = false
		guardPhase = "Lowered"
		activeGuardSequence = nil
		hasGuardAcknowledgement = false
		isKeyboardGuardHeld = UserInputService:IsKeyDown(Enum.KeyCode.F)
		guardToken += 1
		stopGuardTracks(0)
		clearActiveAttack()
		if activeTransitionTrack then
			activeTransitionTrack:Stop(0)
		end
		activeTransitionTrack = nil
		lastAttackAt = -math.huge
		attackLockedUntil = 0
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
		local function synchronizeGuard()
			local sequence = activeGuardSequence
			if not sequence or localPlayer.Character ~= character then
				return
			end
			if character:GetAttribute("GuardRejectedSequence") == sequence then
				endGuard(character, true)
				return
			end
			if character:GetAttribute("GuardSequence") ~= sequence then
				return
			end
			local serverPhase = character:GetAttribute("GuardPhase")
			if serverPhase == "Raising" or serverPhase == "Guarding" then
				hasGuardAcknowledgement = true
				if serverPhase == "Guarding" and isGuardRequested then
					guardPhase = "Guarding"
				end
			elseif serverPhase == "Lowering" then
				hasGuardAcknowledgement = true
				endGuard(character, true)
			elseif serverPhase == "Lowered" and hasGuardAcknowledgement then
				isGuardRequested = false
				guardPhase = "Lowered"
				guardToken += 1
				stopGuardTracks(0.05)
				hasGuardAcknowledgement = false
			end
		end
		for _, attribute in { "GuardPhase", "GuardSequence", "GuardRejectedSequence" } do
			characterTrove:Connect(character:GetAttributeChangedSignal(attribute), synchronizeGuard)
		end
		for _, attribute in { "LeftEquipped", "RightEquipped" } do
			characterTrove:Connect(character:GetAttributeChangedSignal(attribute), function()
				endGuard(character, true)
			end)
		end
	end

	lifecycleTrove:Connect(localPlayer.CharacterAdded, bindCharacter)
	if localPlayer.Character then
		lifecycleTrove:Add(task.defer(bindCharacter, localPlayer.Character))
	end
	lifecycleTrove:Add(task.defer(createCombatButtons))

	stopImpl = function()
		endGuard(getCharacter(), false)
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
