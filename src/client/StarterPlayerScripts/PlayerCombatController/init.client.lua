-- StarterPlayer/StarterPlayerScripts/PlayerCombatController

-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- modules
local CharacterUtil = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Character"):WaitForChild("CharacterUtil"))
local combatPredictionBus = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("CombatPredictionBus"))

-- remotes
local combatEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent")
local weaponsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Weapons"))

local localPlayer = Players.LocalPlayer
local bindings: { [Tool]: { RBXScriptConnection } } = {}
local lastSwingRequestAt = 0
local nextLocalSwingAt = 0
local nextSwingSequence = 0

-- The custom hotbar owns equipping, so combat cannot depend exclusively on Roblox's
-- default Tool activation path. Keep the Tool signal as a compatibility path for touch
-- and tool-specific interactions, but also listen for an unconsumed primary input.
-- This local debounce only merges those two reports from one click; the server remains
-- authoritative for the real swing cooldown.
local REQUEST_DEDUP_SECONDS = 0.08
local EPSILON = 0.001

local function getPlanarDirection(vector: Vector3, fallback: Vector3): Vector3
	local planar = Vector3.new(vector.X, 0, vector.Z)
	return if planar.Magnitude > EPSILON then planar.Unit else fallback
end

local function isWithinSwordArc(attackerCFrame: CFrame, targetPosition: Vector3, profile: any): boolean
	local targetConfig = profile.target
	local forward = getPlanarDirection(attackerCFrame.LookVector, Vector3.new(0, 0, -1))
	local offset = targetPosition - attackerCFrame.Position
	if math.abs(offset.Y) > targetConfig.maxVerticalDifference then
		return false
	end

	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	if horizontal.Magnitude > targetConfig.reachStuds then
		return false
	end

	local direction = getPlanarDirection(horizontal, forward)
	return forward:Dot(direction) >= math.cos(math.rad(targetConfig.arcDegrees * 0.5))
end

local function hasLocalLineOfSight(attackerCharacter: Model, targetCharacter: Model, origin: Vector3, destination: Vector3): boolean
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

local function getSwordHitboxParts(tool: Tool): { BasePart }
	local namedBladeParts = {}
	local fallbackParts = {}
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(fallbackParts, descendant)
			local normalizedName = string.lower(descendant.Name)
			if string.find(normalizedName, "blade", 1, true)
				or string.find(normalizedName, "edge", 1, true)
				or string.find(normalizedName, "hitbox", 1, true) then
				table.insert(namedBladeParts, descendant)
			end
		end
	end

	return if #namedBladeParts > 0 then namedBladeParts else fallbackParts
end

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

local function findBladeSweepCandidates(
	tool: Tool,
	attackerCharacter: Model,
	bladeParts: { BasePart },
	previousPartCFrames: { [BasePart]: CFrame }
): { [Player]: boolean }
	local candidates: { [Player]: boolean } = {}
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { attackerCharacter, tool }
	overlapParams.MaxParts = 30

	for _, bladePart in ipairs(bladeParts) do
		if not bladePart.Parent then
			continue
		end
		local currentCFrame = bladePart.CFrame
		local previousCFrame = previousPartCFrames[bladePart] or currentCFrame
		-- Interpolated overlap boxes cover translation and rotation between rendered
		-- frames; this avoids tunnelling through a moving target at low frame rates.
		for sampleIndex = 1, 3 do
			local sampleCFrame = previousCFrame:Lerp(currentCFrame, sampleIndex / 3)
			local querySize = bladePart.Size + Vector3.new(0.15, 0.15, 0.15)
			for _, touchedPart in ipairs(workspace:GetPartBoundsInBox(sampleCFrame, querySize, overlapParams)) do
				local target = getPlayerFromDescendant(touchedPart)
				if target and target ~= localPlayer then
					candidates[target] = true
				end
			end
		end
		previousPartCFrames[bladePart] = currentCFrame
	end

	return candidates
end

local function findPredictedTarget(
	tool: Tool,
	attackerCharacter: Model,
	previousAttackerCFrame: CFrame,
	currentAttackerCFrame: CFrame,
	previousTargetPositions: { [Player]: Vector3 },
	bladeParts: { BasePart },
	previousPartCFrames: { [BasePart]: CFrame },
	profile: any
): Player?
	local bestTarget = nil
	local bestDistance = math.huge
	local bladeSweepCandidates = findBladeSweepCandidates(tool, attackerCharacter, bladeParts, previousPartCFrames)

	for _, target in ipairs(Players:GetPlayers()) do
		if target ~= localPlayer and bladeSweepCandidates[target] then
			local targetCharacter = target.Character
			local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and targetRoot and targetRoot:IsA("BasePart") then
				local previousTargetPosition = previousTargetPositions[target] or targetRoot.Position
				local travelDistance = math.max(
					(currentAttackerCFrame.Position - previousAttackerCFrame.Position).Magnitude,
					(targetRoot.Position - previousTargetPosition).Magnitude
				)
				local sampleCount = math.clamp(math.ceil(travelDistance / 0.75), 1, 5)
				local intersectsSwing = false
				for sampleIndex = 1, sampleCount do
					local alpha = sampleIndex / sampleCount
					local attackerCFrame = previousAttackerCFrame:Lerp(currentAttackerCFrame, alpha)
					local targetPosition = previousTargetPosition:Lerp(targetRoot.Position, alpha)
					if isWithinSwordArc(attackerCFrame, targetPosition, profile) then
						intersectsSwing = true
						break
					end
				end

				local distance = (targetRoot.Position - currentAttackerCFrame.Position).Magnitude
				if intersectsSwing
					and distance < bestDistance
					and (not profile.target.requireLineOfSight
						or hasLocalLineOfSight(
							attackerCharacter,
							targetCharacter,
							currentAttackerCFrame.Position + Vector3.yAxis * 1.5,
							targetRoot.Position + Vector3.yAxis * 1.5
						)) then
					bestTarget = target
					bestDistance = distance
				end
				previousTargetPositions[target] = targetRoot.Position
			end
		end
	end

	return bestTarget
end

local function getEquippedMeleeTool(): Tool?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and weaponsData.IsMeleeTool(child) then
			return child
		end
	end

	return nil
end

local function requestSwing(tool: Tool?)
	if not tool or tool.Parent ~= localPlayer.Character or not weaponsData.IsMeleeTool(tool) then
		return
	end

	local now = os.clock()
	if now - lastSwingRequestAt < REQUEST_DEDUP_SECONDS then
		return
	end
	lastSwingRequestAt = now

	local _, profile = weaponsData.GetProfile(tool)
	if not profile or now < nextLocalSwingAt then
		return
	end
	nextLocalSwingAt = now + profile.swing.cooldownSeconds
	nextSwingSequence += 1
	local sequence = nextSwingSequence
	combatEvent:FireServer("SwingRequest", {
		sequence = sequence,
		clientTime = workspace:GetServerTimeNow(),
	})

	-- Cosmetic prediction follows the same configured arc during the visible active
	-- window. The server receives only the candidate and still validates the rewind.
	task.spawn(function()
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (character and root and root:IsA("BasePart") and tool.Parent == character) then
			return
		end

		local activeUntil = os.clock() + profile.swing.activeWindowSeconds
		local previousAttackerCFrame = root.CFrame
		local previousTargetPositions: { [Player]: Vector3 } = {}
		local bladeParts = getSwordHitboxParts(tool)
		local previousPartCFrames: { [BasePart]: CFrame } = {}
		for _, bladePart in ipairs(bladeParts) do
			previousPartCFrames[bladePart] = bladePart.CFrame
		end
		while os.clock() <= activeUntil and tool.Parent == character do
			RunService.RenderStepped:Wait()
			local target = findPredictedTarget(
				tool,
				character,
				previousAttackerCFrame,
				root.CFrame,
				previousTargetPositions,
				bladeParts,
				previousPartCFrames,
				profile
			)
			if target and target.Character then
				local predictedAt = workspace:GetServerTimeNow()
				combatPredictionBus:Fire(
					"PredictedImpact",
					target.Character,
					profile.vfx,
					sequence
				)
				combatEvent:FireServer("SwingPrediction", {
					sequence = sequence,
					clientTime = predictedAt,
					targetUserId = target.UserId,
				})
				return
			end

			previousAttackerCFrame = root.CFrame
		end
	end)
end

local function unbindTool(tool: Tool)
	local connections = bindings[tool]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	bindings[tool] = nil
end

-- Tool animations remain local presentation. The client may report one predicted target,
-- but the server independently validates its history and remains the only impact authority.
local function bindMeleeTool(tool: Tool)
	if bindings[tool] or not weaponsData.IsMeleeTool(tool) then
		return
	end

	local connections = {}
	connections[1] = tool.Activated:Connect(function()
		requestSwing(tool)
	end)
	connections[2] = tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unbindTool(tool)
		end
	end)
	bindings[tool] = connections
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		requestSwing(getEquippedMeleeTool())
	end
end)

-- Rebind on every spawn. Only recognised melee tools get an input listener, so future
-- shields, consumables, and utility tools cannot hijack this controller or error because
-- they lack a Handle, Animation, or Hitbox.
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
