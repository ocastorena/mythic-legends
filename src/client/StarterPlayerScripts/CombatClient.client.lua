-- StarterPlayer/StarterPlayerScripts/CombatClient
-- Local input and animation prediction; the server owns stance and hit resolution.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local WeaponConfigs = require(ReplicatedStorage:WaitForChild("WeaponConfigs"))
local ToggleCombatState = ReplicatedStorage:WaitForChild("ToggleCombatState") :: RemoteEvent
local PerformAttack = ReplicatedStorage:WaitForChild("PerformAttack") :: RemoteEvent
local localPlayer = Players.LocalPlayer

-- Replace or extend IDs per loadout without changing input/state code.
local ANIMATIONS = {
	Transitions = {
		-- Supply project-owned R15 animation IDs here. Empty IDs safely skip presentation.
		Sheath = "",
		Unsheath = "",
	},
	Loadouts = {
		["WoodenSword+"] = {
			Right = "rbxassetid://126682224103556",
		},
		["+WoodenSword"] = {
			Left = "rbxassetid://126682224103556",
		},
		["WoodenSword+WoodenShield"] = {
			Right = "rbxassetid://126682224103556",
			Left = "rbxassetid://126682224103556",
		},
	},
}

local animationCache: { [string]: Animation } = {}
local lastAttackAt = 0
local nextDualHand = "Right"
local requestedToggle = false
local activeTransitionTrack: AnimationTrack? = nil
local activeAttackTrack: AnimationTrack? = nil
local activeAttackConnections: { RBXScriptConnection } = {}
local attackToken = 0

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

local function playAnimation(character: Model, animationId: string?): AnimationTrack?
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
		warn(`[CombatClient] Could not load animation {animationId}: {track}`)
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.08)
	return track
end

local function getEquipped(character: Model, hand: string): string
	local value = character:GetAttribute(`{hand}Equipped`)
	return if type(value) == "string" then value else ""
end

local function getWeaponModel(character: Model, hand: string): Model?
	local folder = character:FindFirstChild("EquippedWeapons")
	local weapon = folder and folder:FindFirstChild(`{hand}Weapon`)
	return if weapon and weapon:IsA("Model") then weapon else nil
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

local function chooseAttack(character: Model): (string?, string?)
	local right = getEquipped(character, "Right")
	local left = getEquipped(character, "Left")
	local hasRight = right ~= "" and WeaponConfigs[right] ~= nil
	local hasLeft = left ~= "" and WeaponConfigs[left] ~= nil
	if not hasRight and not hasLeft then
		return nil, nil
	end

	local hand: string
	if hasRight and hasLeft then
		hand = nextDualHand
		nextDualHand = if nextDualHand == "Right" then "Left" else "Right"
	else
		hand = if hasRight then "Right" else "Left"
	end

	local loadoutAnimations = ANIMATIONS.Loadouts[`{right}+{left}`]
	local animationId = loadoutAnimations and loadoutAnimations[hand]
	return hand, animationId
end

local function toggleCombat(character: Model)
	if requestedToggle then
		return
	end
	requestedToggle = true
	clearActiveAttack()
	local becomingReady = character:GetAttribute("CombatReady") ~= true
	if activeTransitionTrack then
		activeTransitionTrack:Stop(0.05)
		activeTransitionTrack = nil
	end
	local track = playAnimation(
		character,
		if becomingReady then ANIMATIONS.Transitions.Unsheath else ANIMATIONS.Transitions.Sheath
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
	ToggleCombatState:FireServer()
	task.delay(0.25, function()
		requestedToggle = false
	end)
end

local function attack(character: Model)
	if character:GetAttribute("CombatReady") ~= true then
		return
	end
	local hand, animationId = chooseAttack(character)
	if not hand then
		return
	end
	local weaponName = getEquipped(character, hand)
	local config = WeaponConfigs[weaponName]
	if not config then
		return
	end
	local now = os.clock()
	if now - lastAttackAt < config.AttackCooldown then
		return
	end
	lastAttackAt = now
	clearActiveAttack()
	local currentToken = attackToken
	local weapon = getWeaponModel(character, hand)
	local hitReported = false
	local soundPlayed = false
	local trailEnded = false

	local function isCurrentAttack(): boolean
		return attackToken == currentToken
			and localPlayer.Character == character
			and character:GetAttribute("CombatReady") == true
	end

	local function reportHitStart()
		if hitReported or not isCurrentAttack() then
			return
		end
		hitReported = true
		PerformAttack:FireServer(hand)
	end

	local function playSwingSound()
		if soundPlayed or not isCurrentAttack() then
			return
		end
		soundPlayed = true
		playWeaponSound(weapon)
	end

	local function endTrail()
		if trailEnded then
			return
		end
		trailEnded = true
		setWeaponTrail(weapon, false)
	end

	local track = playAnimation(character, animationId)
	activeAttackTrack = track
	if track then
		track.Looped = false
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("SwingSound"):Connect(playSwingSound))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("TrailStart"):Connect(function()
			if isCurrentAttack() then
				setWeaponTrail(weapon, true)
			end
		end))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("HitStart"):Connect(reportHitStart))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("HitEnd"):Connect(endTrail))
		table.insert(activeAttackConnections, track:GetMarkerReachedSignal("TrailEnd"):Connect(endTrail))
		table.insert(activeAttackConnections, track.Stopped:Connect(function()
			if isCurrentAttack() then
				endTrail()
			end
		end))
	end

	-- Authored markers own normal timing; these fallbacks keep combat functional if an
	-- animation fails to load or is published without its marker data.
	task.delay(config.HitStartFallback, function()
		if isCurrentAttack() then
			playSwingSound()
			setWeaponTrail(weapon, true)
			reportHitStart()
		end
	end)
	task.delay(config.HitStartFallback + config.HitWindowDuration, function()
		if isCurrentAttack() then
			endTrail()
		end
	end)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end
	local character = getCharacter()
	if not character then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		toggleCombat(character)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		attack(character)
	end
end)

localPlayer.CharacterAdded:Connect(function()
	clearActiveAttack()
	if activeTransitionTrack then
		activeTransitionTrack:Stop(0)
		activeTransitionTrack = nil
	end
	lastAttackAt = 0
	nextDualHand = "Right"
	requestedToggle = false
end)
