-- Applies a server-relayed launch to the character owned by this client. The target
-- velocity is reached through a short force curve rather than a hard velocity snap.

local RunService = game:GetService("RunService")

local ClientKnockbackController = {}

local seenHitIds: { [number]: boolean } = {}
local activeTokens: { [Model]: number } = {}
local activeCleanups: { [Model]: () -> () } = {}
local nextToken = 0

local HIT_ID_MEMORY_SECONDS = 5
local MAX_LAUNCH_SPEED = 140
local MAX_VELOCITY_CORRECTION = 180
local MAX_ANGULAR_SPEED = 20

local function isFiniteVector(vector: Vector3): boolean
	return vector.X == vector.X
		and vector.Y == vector.Y
		and vector.Z == vector.Z
		and vector.Magnitude < math.huge
end

function ClientKnockbackController.Apply(
	character: Model,
	hitId: number,
	launchVelocity: Vector3,
	angularVelocity: Vector3,
	durationSeconds: number
): boolean
	if seenHitIds[hitId] then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return false
	end
	if hitId % 1 ~= 0
		or durationSeconds ~= durationSeconds
		or math.abs(durationSeconds) == math.huge
		or not (isFiniteVector(launchVelocity) and isFiniteVector(angularVelocity)) then
		return false
	end

	seenHitIds[hitId] = true
	task.delay(HIT_ID_MEMORY_SECONDS, function()
		seenHitIds[hitId] = nil
	end)

	local previousCleanup = activeCleanups[character]
	if previousCleanup then
		previousCleanup()
	end

	nextToken += 1
	local token = nextToken
	activeTokens[character] = token

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatLaunchAttachment"
	attachment.Parent = root

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "CombatLaunchForce"
	vectorForce.Attachment0 = attachment
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = root

	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		if vectorForce.Parent then
			vectorForce:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
		if activeTokens[character] == token then
			activeTokens[character] = nil
			activeCleanups[character] = nil
		end
	end
	activeCleanups[character] = cleanup

	local desiredVelocity = if launchVelocity.Magnitude > MAX_LAUNCH_SPEED
		then launchVelocity.Unit * MAX_LAUNCH_SPEED
		else launchVelocity
	local desiredAngularVelocity = if angularVelocity.Magnitude > MAX_ANGULAR_SPEED
		then angularVelocity.Unit * MAX_ANGULAR_SPEED
		else angularVelocity
	local forceDurationSeconds = math.clamp(durationSeconds, 0.08, 0.25)

	task.spawn(function()
		if activeTokens[character] ~= token or not (root.Parent and vectorForce.Parent) then
			cleanup()
			return
		end

		root.AssemblyAngularVelocity = desiredAngularVelocity
		local velocityDelta = desiredVelocity - root.AssemblyLinearVelocity
		if velocityDelta.Magnitude > MAX_VELOCITY_CORRECTION then
			velocityDelta = velocityDelta.Unit * MAX_VELOCITY_CORRECTION
		end

		local elapsed = 0
		while elapsed < forceDurationSeconds
			and activeTokens[character] == token
			and root.Parent
			and vectorForce.Parent do
			local simulationStep = RunService.PreSimulation:Wait()
			local activeStep = math.min(simulationStep, forceDurationSeconds - elapsed)
			local alpha = (elapsed + activeStep * 0.5) / forceDurationSeconds
			local easeRate = (math.pi * 0.5 / forceDurationSeconds) * math.sin(math.pi * alpha)
			local acceleration = velocityDelta * easeRate + Vector3.yAxis * workspace.Gravity
			vectorForce.Force = acceleration * root.AssemblyMass * (activeStep / simulationStep)
			RunService.PostSimulation:Wait()
			elapsed += activeStep
		end

		cleanup()
	end)

	return true
end

return ClientKnockbackController
