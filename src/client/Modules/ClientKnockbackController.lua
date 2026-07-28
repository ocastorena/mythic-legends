-- Applies one server-approved launch to the character owned by this client. Hit IDs make
-- delivery idempotent, while a short LinearVelocity produces deterministic knockback.

local ClientKnockbackController = {}

local seenHitIds: { [number]: boolean } = {}
local activeTokens: { [Model]: number } = {}
local nextToken = 0

local HIT_ID_MEMORY_SECONDS = 5
local MAX_LAUNCH_SPEED = 140
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

	nextToken += 1
	local token = nextToken
	activeTokens[character] = token

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatLaunchAttachment"
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "CombatLaunchVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.VectorVelocity = if launchVelocity.Magnitude > MAX_LAUNCH_SPEED
		then launchVelocity.Unit * MAX_LAUNCH_SPEED
		else launchVelocity
	linearVelocity.ForceLimitsEnabled = false
	linearVelocity.Parent = root

	root.AssemblyAngularVelocity = if angularVelocity.Magnitude > MAX_ANGULAR_SPEED
		then angularVelocity.Unit * MAX_ANGULAR_SPEED
		else angularVelocity

	task.delay(math.clamp(durationSeconds, 0.04, 0.2), function()
		if linearVelocity.Parent then
			linearVelocity:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
		if activeTokens[character] == token then
			activeTokens[character] = nil
		end
	end)

	return true
end

return ClientKnockbackController
