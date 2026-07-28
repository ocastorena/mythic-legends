-- ServerScriptService/Services/PlayerCombatService/RagdollUtil
-- Creates a server-owned character ragdoll that normally restores shortly after a
-- confirmed landing. Everything created here is tracked per character and destroyed
-- again, so one player's hit cannot corrupt another player's movement state or leave
-- physics attachments behind.

local RagdollUtil = {}

type MotorState = {
	motor: Motor6D,
	enabled: boolean,
}

type PartState = {
	part: BasePart,
	canCollide: boolean,
}

type AnimationConstraintState = {
	constraint: AnimationConstraint,
	isKinematic: boolean,
	angularStrength: number,
	linearStrength: number,
}

type RagdollState = {
	token: number,
	landingMonitorToken: number?,
	character: Model,
	humanoid: Humanoid,
	motors: { MotorState },
	animationConstraints: { AnimationConstraintState },
	parts: { PartState },
	attachments: { Attachment },
	sockets: { BallSocketConstraint },
	noCollisions: { NoCollisionConstraint },
	autoRotate: boolean,
	platformStand: boolean,
	requiresNeck: boolean,
	gettingUpEnabled: boolean,
}

local activeStates: { [Model]: RagdollState } = {}
local nextToken = 0

local LANDING_POLL_SECONDS = 0.05
local MIN_TAKEOFF_VERTICAL_SPEED = 3
local MAX_LANDING_VERTICAL_SPEED = 8
local TAKEOFF_FALLBACK_SECONDS = 0.35
local GROUND_CHECK_DISTANCE = 1.25
local CORE_BODY_PART_NAMES = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Torso" }

local function isAvatarBodyPart(part: BasePart, character: Model): boolean
	return part:IsDescendantOf(character)
		and part:FindFirstAncestorOfClass("Tool") == nil
		and part:FindFirstAncestorOfClass("Accessory") == nil
end

-- Only the root-connected torso needs to support a ragdolled player on the floor.
-- Letting every limb collide when an R15 rig is released can make solver overlap
-- corrections launch the whole character upward.
local function isRagdollSupportPart(part: BasePart): boolean
	return part.Name == "LowerTorso" or part.Name == "Torso"
end

-- The HumanoidRootPart is the object that receives the server impulse. Its connection
-- to the torso must remain intact while ragdolled so a collidable torso keeps the whole
-- assembly supported by the Arena floor instead of letting the root fall through it.
local function connectsHumanoidRootPart(part0: BasePart, part1: BasePart): boolean
	return part0.Name == "HumanoidRootPart" or part1.Name == "HumanoidRootPart"
end

local function isAvatarJoint(joint: Motor6D, character: Model): boolean
	local part0 = joint.Part0
	local part1 = joint.Part1
	return part0 ~= nil
		and part1 ~= nil
		and isAvatarBodyPart(part0, character)
		and isAvatarBodyPart(part1, character)
		and not connectsHumanoidRootPart(part0, part1)
end

local function getAttachmentPart(attachment: Attachment?): BasePart?
	local parent = attachment and attachment.Parent
	return if parent and parent:IsA("BasePart") then parent else nil
end

local function isAvatarAnimationConstraint(constraint: AnimationConstraint, character: Model): boolean
	local part0 = getAttachmentPart(constraint.Attachment0)
	local part1 = getAttachmentPart(constraint.Attachment1)
	return part0 ~= nil
		and part1 ~= nil
		and isAvatarBodyPart(part0, character)
		and isAvatarBodyPart(part1, character)
		and not connectsHumanoidRootPart(part0, part1)
end

local function getCoreBodyParts(character: Model): { BasePart }
	local parts = {}
	for _, name in ipairs(CORE_BODY_PART_NAMES) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") and isAvatarBodyPart(part, character) then
			table.insert(parts, part)
		end
	end
	return parts
end

local function getVerticalHalfExtent(part: BasePart): number
	local size = part.Size
	local cframe = part.CFrame
	return (
		math.abs(cframe.RightVector.Y) * size.X
		+ math.abs(cframe.UpVector.Y) * size.Y
		+ math.abs(cframe.LookVector.Y) * size.Z
	) * 0.5
end

local function hasGroundSupport(character: Model, params: RaycastParams): boolean
	for _, part in ipairs(getCoreBodyParts(character)) do
		local origin = part.Position - Vector3.yAxis * math.max(0, getVerticalHalfExtent(part) - 0.05)
		if workspace:Raycast(origin, -Vector3.yAxis * GROUND_CHECK_DISTANCE, params) then
			return true
		end
	end
	return false
end

local function hasTakenOff(character: Model, params: RaycastParams): boolean
	for _, part in ipairs(getCoreBodyParts(character)) do
		if part.AssemblyLinearVelocity.Y >= MIN_TAKEOFF_VERTICAL_SPEED then
			return true
		end
	end
	return not hasGroundSupport(character, params)
end

local function isSettlingOnGround(character: Model, params: RaycastParams): boolean
	if not hasGroundSupport(character, params) then
		return false
	end

	local coreParts = getCoreBodyParts(character)
	if #coreParts == 0 then
		return false
	end

	for _, part in ipairs(coreParts) do
		if math.abs(part.AssemblyLinearVelocity.Y) > MAX_LANDING_VERTICAL_SPEED then
			return false
		end
	end
	return true
end

-- Modern R15 ragdolls can contain several independent assemblies. Clear each one
-- immediately before restoring joints so leftover impact velocity cannot turn the
-- normal GettingUp state into a floor bounce.
local function settleRagdollAssemblies(character: Model)
	local roots: { [BasePart]: boolean } = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and isAvatarBodyPart(descendant, character) then
			local assemblyRoot = descendant.AssemblyRootPart
			if assemblyRoot and assemblyRoot.Parent then
				roots[assemblyRoot] = true
			end
		end
	end

	for root in pairs(roots) do
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function restore(state: RagdollState)
	for _, constraintState in ipairs(state.animationConstraints) do
		local constraint = constraintState.constraint
		if constraint.Parent and constraint:IsDescendantOf(state.character) then
			constraint.IsKinematic = constraintState.isKinematic
			constraint.AngularStrength = constraintState.angularStrength
			constraint.LinearStrength = constraintState.linearStrength
		end
	end

	for _, socket in ipairs(state.sockets) do
		if socket.Parent then
			socket:Destroy()
		end
	end

	for _, noCollision in ipairs(state.noCollisions) do
		if noCollision.Parent then
			noCollision:Destroy()
		end
	end

	for _, attachment in ipairs(state.attachments) do
		if attachment.Parent then
			attachment:Destroy()
		end
	end

	for _, motorState in ipairs(state.motors) do
		local motor = motorState.motor
		if motor.Parent and motor:IsDescendantOf(state.character) then
			motor.Enabled = motorState.enabled
		end
	end

	for _, partState in ipairs(state.parts) do
		local part = partState.part
		if part.Parent and part:IsDescendantOf(state.character) then
			part.CanCollide = partState.canCollide
		end
	end

	local humanoid = state.humanoid
	if humanoid.Parent and humanoid.Health > 0 then
		humanoid.RequiresNeck = state.requiresNeck
		humanoid.AutoRotate = state.autoRotate
		humanoid.PlatformStand = state.platformStand
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, state.gettingUpEnabled)

		if not state.platformStand then
			-- The first request restores the normal R15 get-up animation. Repeat it on
			-- the next physics step because constraint restoration can otherwise leave
			-- the Humanoid in FallingDown for one frame instead of transitioning cleanly.
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			task.delay(0.05, function()
				if activeStates[state.character] == nil and humanoid.Parent and humanoid.Health > 0 then
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)
		end
	end
end

function RagdollUtil.Stop(character: Model, expectedToken: number?, settleOnGround: boolean?): boolean
	local state = activeStates[character]
	if not state or (expectedToken and state.token ~= expectedToken) then
		return false
	end

	if settleOnGround then
		settleRagdollAssemblies(state.character)
	end
	activeStates[character] = nil
	restore(state)
	return true
end

function RagdollUtil.StopAfterLanding(
	character: Model,
	expectedToken: number?,
	recoverySeconds: number,
	onLanded: (() -> ())?,
	onRecovered: (() -> ())?
): boolean
	local state = activeStates[character]
	if not state or (expectedToken and state.token ~= expectedToken) then
		return false
	end

	local token = state.token
	if state.landingMonitorToken == token then
		return true
	end
	state.landingMonitorToken = token

	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { character }
	groundParams.IgnoreWater = true
	local recoveryDelay = math.max(0, recoverySeconds)

	task.spawn(function()
		local startedAt = os.clock()
		local observedTakeoff = false

		while activeStates[character] == state and state.token == token do
			local elapsed = os.clock() - startedAt
			if hasTakenOff(character, groundParams) then
				observedTakeoff = true
			end

			-- A blocked launch can remain grounded. Treat it as landed shortly after
			-- the impact instead of forcing the player to wait for the max failsafe.
			if observedTakeoff or elapsed >= TAKEOFF_FALLBACK_SECONDS then
				if isSettlingOnGround(character, groundParams) then
					if onLanded then
						pcall(onLanded)
					end

					task.delay(recoveryDelay, function()
						if RagdollUtil.Stop(character, token, true) and onRecovered then
							pcall(onRecovered)
						end
					end)
					return
				end
			end

			task.wait(LANDING_POLL_SECONDS)
		end
	end)

	return true
end

function RagdollUtil.Start(character: Model, maximumDurationSeconds: number): (boolean, number?)
	local duration = math.max(0, maximumDurationSeconds)
	if duration <= 0 then
		return false, nil
	end

	local existing = activeStates[character]
	if existing then
		nextToken += 1
		existing.token = nextToken
		existing.landingMonitorToken = nil
		local token = existing.token
		task.delay(duration, function()
			RagdollUtil.Stop(character, token)
		end)
		return true, token
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, nil
	end

	nextToken += 1
	local state: RagdollState = {
		token = nextToken,
		landingMonitorToken = nil,
		character = character,
		humanoid = humanoid,
		motors = {},
		animationConstraints = {},
		parts = {},
		attachments = {},
		sockets = {},
		noCollisions = {},
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
		requiresNeck = humanoid.RequiresNeck,
		gettingUpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
	}

	activeStates[character] = state

	local succeeded = pcall(function()
		-- Set this before disabling Neck so a normal hit cannot accidentally kill a player.
		humanoid.RequiresNeck = false
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

		local hasAnimationConstraints = false
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("AnimationConstraint") and isAvatarAnimationConstraint(descendant, character) then
				hasAnimationConstraints = true
				break
			end
		end

		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and isAvatarBodyPart(descendant, character) then
				table.insert(state.parts, {
					part = descendant,
					canCollide = descendant.CanCollide,
				})
				descendant.CanCollide = isRagdollSupportPart(descendant)
			elseif hasAnimationConstraints
				and descendant:IsA("AnimationConstraint")
				and isAvatarAnimationConstraint(descendant, character) then
				table.insert(state.animationConstraints, {
					constraint = descendant,
					isKinematic = descendant.IsKinematic,
					angularStrength = descendant.AngularStrength,
					linearStrength = descendant.LinearStrength,
				})
				descendant.IsKinematic = false
				descendant.AngularStrength = 0
				descendant.LinearStrength = 0
			elseif not hasAnimationConstraints and descendant:IsA("Motor6D") and isAvatarJoint(descendant, character) then
				local attachment0 = Instance.new("Attachment")
				attachment0.Name = "CombatRagdollAttachment0"
				attachment0.CFrame = descendant.C0
				attachment0.Parent = descendant.Part0

				local attachment1 = Instance.new("Attachment")
				attachment1.Name = "CombatRagdollAttachment1"
				attachment1.CFrame = descendant.C1
				attachment1.Parent = descendant.Part1

				local socket = Instance.new("BallSocketConstraint")
				socket.Name = "CombatRagdollSocket"
				socket.Attachment0 = attachment0
				socket.Attachment1 = attachment1
				socket.LimitsEnabled = true
				socket.UpperAngle = 45
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -35
				socket.TwistUpperAngle = 35
				socket.Restitution = 0
				socket.Parent = descendant.Part0

				local noCollision = Instance.new("NoCollisionConstraint")
				noCollision.Name = "CombatRagdollNoCollision"
				noCollision.Part0 = descendant.Part0
				noCollision.Part1 = descendant.Part1
				noCollision.Parent = descendant.Part0

				table.insert(state.attachments, attachment0)
				table.insert(state.attachments, attachment1)
				table.insert(state.sockets, socket)
				table.insert(state.noCollisions, noCollision)
				table.insert(state.motors, {
					motor = descendant,
					enabled = descendant.Enabled,
				})
				descendant.Enabled = false
			end
		end

		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	if not succeeded then
		activeStates[character] = nil
		restore(state)
		return false, nil
	end

	local token = state.token
	task.delay(duration, function()
		RagdollUtil.Stop(character, token)
	end)
	return true, token
end

return RagdollUtil
