-- StarterPlayer/StarterPlayerScripts/PlayerCombatController
-- The attacking client owns sword presentation and blade contact. The server receives
-- one target report per visible swing and remains authoritative for the resulting effect.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterUtil = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Character"):WaitForChild("CharacterUtil"))
local combatPresentationBus = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("CombatPresentationBus"))
local weaponsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Weapons"))

local combatEvent: RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent")
local localPlayer = Players.LocalPlayer

type ToolBinding = {
	connections: { RBXScriptConnection },
	track: AnimationTrack?,
}

type SwingState = {
	tool: Tool,
	character: Model,
	profile: any,
	sequence: number,
	track: AnimationTrack,
	windowOpen: boolean,
	hitReported: boolean,
	finished: boolean,
	hitStopToken: number,
	connections: { RBXScriptConnection },
}

local bindings: { [Tool]: ToolBinding } = {}
local activeSwing: SwingState? = nil
local nextLocalSwingAt = 0
local nextSwingSequence = 0

local BLADE_SWEEP_SAMPLES = 6
local MAX_OVERLAP_PARTS = 100
local HITBOX_PADDING = Vector3.new(0.1, 0.1, 0.1)

local function getPlayerFromDescendant(instance: Instance): Player?
	local ancestor: Instance? = instance
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

local function getSwordHitboxParts(tool: Tool): { BasePart }
	local authoredBlade = tool:FindFirstChild("SwordBlade", true)
	if authoredBlade and authoredBlade:IsA("BasePart") then
		return { authoredBlade }
	end

	local bladeParts = {}
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("CombatHitbox") == true then
			table.insert(bladeParts, descendant)
		elseif descendant:IsA("BasePart") then
			local normalizedName = string.lower(descendant.Name)
			if string.find(normalizedName, "blade", 1, true)
				or string.find(normalizedName, "edge", 1, true) then
				table.insert(bladeParts, descendant)
			end
		end
	end
	return bladeParts
end

local function hasLocalLineOfSight(attackerCharacter: Model, targetCharacter: Model): boolean
	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not (attackerRoot and attackerRoot:IsA("BasePart") and targetRoot and targetRoot:IsA("BasePart")) then
		return false
	end

	local origin = attackerRoot.Position + Vector3.yAxis * 1.5
	local direction = targetRoot.Position + Vector3.yAxis * 1.5 - origin
	if direction.Magnitude <= 0.001 then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	params.IgnoreWater = true
	local obstruction = workspace:Raycast(origin, direction, params)
	return obstruction == nil or obstruction.Instance:IsDescendantOf(targetCharacter)
end

local function findBladeContact(
	state: SwingState,
	bladeParts: { BasePart },
	previousPartCFrames: { [BasePart]: CFrame }
): Player?
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { state.character, state.tool }
	overlapParams.MaxParts = MAX_OVERLAP_PARTS

	local candidateScores: { [Player]: number } = {}
	for _, bladePart in ipairs(bladeParts) do
		if not bladePart.Parent then
			continue
		end

		local currentCFrame = bladePart.CFrame
		local previousCFrame = previousPartCFrames[bladePart] or currentCFrame
		for sampleIndex = 1, BLADE_SWEEP_SAMPLES do
			local sampleCFrame = previousCFrame:Lerp(currentCFrame, sampleIndex / BLADE_SWEEP_SAMPLES)
			for _, touchedPart in ipairs(
				workspace:GetPartBoundsInBox(sampleCFrame, bladePart.Size + HITBOX_PADDING, overlapParams)
			) do
				local target = getPlayerFromDescendant(touchedPart)
				if target and target ~= localPlayer then
					local score = (touchedPart.Position - sampleCFrame.Position).Magnitude
					candidateScores[target] = math.min(candidateScores[target] or math.huge, score)
				end
			end
		end
		previousPartCFrames[bladePart] = currentCFrame
	end

	local bestTarget: Player? = nil
	local bestScore = math.huge
	for target, score in pairs(candidateScores) do
		local targetCharacter = target.Character
		local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid
			and humanoid.Health > 0
			and targetCharacter
			and score < bestScore
			and (not state.profile.target.requireLineOfSight
				or hasLocalLineOfSight(state.character, targetCharacter)) then
			bestTarget = target
			bestScore = score
		end
	end
	return bestTarget
end

local function getTrail(tool: Tool): Trail?
	local trail = tool:FindFirstChild("Trail", true)
	return if trail and trail:IsA("Trail") then trail else nil
end

local function getSlashSound(tool: Tool): Sound?
	local sound = tool:FindFirstChild("SwordSlash", true)
	return if sound and sound:IsA("Sound") then sound else nil
end

local function setTrailEnabled(tool: Tool, enabled: boolean)
	local trail = getTrail(tool)
	if trail then
		trail.Enabled = enabled
	end
end

local function playSlashSound(tool: Tool)
	local sound = getSlashSound(tool)
	if not sound then
		return
	end

	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

local function finishSwing(state: SwingState)
	if state.finished then
		return
	end

	state.finished = true
	state.windowOpen = false
	state.hitStopToken += 1
	setTrailEnabled(state.tool, false)
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	table.clear(state.connections)
	if activeSwing == state then
		activeSwing = nil
	end
end

local function applyHitStop(state: SwingState)
	local configuredSeconds = state.profile.swing.hitStopSeconds
	if type(configuredSeconds) ~= "number" or configuredSeconds <= 0 then
		return
	end

	state.hitStopToken += 1
	local token = state.hitStopToken
	state.track:AdjustSpeed(0)
	task.delay(math.clamp(configuredSeconds, 0, 0.08), function()
		if not state.finished and state.hitStopToken == token and state.track.IsPlaying then
			state.track:AdjustSpeed(state.profile.swing.animationSpeed)
		end
	end)
end

local function openContactWindow(state: SwingState)
	if state.finished or state.windowOpen or activeSwing ~= state then
		return
	end

	local bladeParts = getSwordHitboxParts(state.tool)
	if #bladeParts == 0 then
		finishSwing(state)
		return
	end

	state.windowOpen = true
	playSlashSound(state.tool)
	setTrailEnabled(state.tool, true)

	local previousPartCFrames: { [BasePart]: CFrame } = {}
	for _, bladePart in ipairs(bladeParts) do
		previousPartCFrames[bladePart] = bladePart.CFrame
	end

	task.spawn(function()
		local activeUntil = os.clock() + math.max(0.05, state.profile.swing.activeWindowSeconds)
		while state.windowOpen
			and not state.hitReported
			and not state.finished
			and activeSwing == state
			and state.tool.Parent == state.character
			and os.clock() <= activeUntil do
			RunService.RenderStepped:Wait()
			local target = findBladeContact(state, bladeParts, previousPartCFrames)
			if target and target.Character then
				state.hitReported = true
				applyHitStop(state)
				combatPresentationBus:Fire(
					"LocalImpact",
					target.Character,
					state.profile.vfx,
					state.sequence
				)
				combatEvent:FireServer("HitReport", {
					sequence = state.sequence,
					targetUserId = target.UserId,
				})
			end
		end
		state.windowOpen = false
	end)
end

local function getOrCreateSwingTrack(tool: Tool, binding: ToolBinding, profile: any): AnimationTrack?
	if binding.track then
		return binding.track
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animationId = profile.swing.animationId
	if not (animator and type(animationId) == "string" and animationId ~= "") then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local loaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not loaded or not track then
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action
	binding.track = track
	return track
end

local function startSwing(tool: Tool)
	local character = localPlayer.Character
	local binding = bindings[tool]
	local _, profile = weaponsData.GetProfile(tool)
	if not (character and binding and profile and tool.Parent == character) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid
		or humanoid.Health <= 0
		or humanoid.PlatformStand
		or humanoid:GetState() == Enum.HumanoidStateType.Physics then
		return
	end

	local now = os.clock()
	if now < nextLocalSwingAt then
		return
	end

	local track = getOrCreateSwingTrack(tool, binding, profile)
	if not track then
		return
	end

	if activeSwing then
		finishSwing(activeSwing)
	end

	nextLocalSwingAt = now + profile.swing.cooldownSeconds
	nextSwingSequence += 1
	local state: SwingState = {
		tool = tool,
		character = character,
		profile = profile,
		sequence = nextSwingSequence,
		track = track,
		windowOpen = false,
		hitReported = false,
		finished = false,
		hitStopToken = 0,
		connections = {},
	}
	activeSwing = state

	table.insert(state.connections, track:GetMarkerReachedSignal("Begin"):Connect(function()
		openContactWindow(state)
	end))
	table.insert(state.connections, track:GetMarkerReachedSignal("End"):Connect(function()
		finishSwing(state)
	end))
	table.insert(state.connections, track.Stopped:Connect(function()
		finishSwing(state)
	end))

	track:Play(0.05, 1, profile.swing.animationSpeed)

	-- Authored markers are preferred. This fallback keeps combat usable if an animation
	-- is replaced without markers, while still tying contact to a visible swing.
	task.delay(math.min(0.1, profile.swing.activeWindowSeconds * 0.4), function()
		openContactWindow(state)
	end)
	task.delay(profile.swing.activeWindowSeconds + 0.5, function()
		finishSwing(state)
	end)
end

local function unbindTool(tool: Tool)
	local binding = bindings[tool]
	if not binding then
		return
	end

	if activeSwing and activeSwing.tool == tool then
		finishSwing(activeSwing)
	end
	for _, connection in ipairs(binding.connections) do
		connection:Disconnect()
	end
	if binding.track then
		binding.track:Stop(0)
		binding.track:Destroy()
	end
	bindings[tool] = nil
end

local function bindMeleeTool(tool: Tool)
	if bindings[tool] or not weaponsData.IsMeleeTool(tool) then
		return
	end

	local binding: ToolBinding = {
		connections = {},
		track = nil,
	}
	bindings[tool] = binding
	setTrailEnabled(tool, false)

	table.insert(binding.connections, tool.Activated:Connect(function()
		startSwing(tool)
	end))
	table.insert(binding.connections, tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unbindTool(tool)
		end
	end))

	local sound = getSlashSound(tool)
	if sound then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ sound })
			end)
		end)
	end
end

CharacterUtil.OnCharacter(function(character)
	if localPlayer.Character ~= character then
		return
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindMeleeTool(child)
		end
	end)

	for _, existing in ipairs(character:GetChildren()) do
		if existing:IsA("Tool") then
			bindMeleeTool(existing)
		end
	end
end)
