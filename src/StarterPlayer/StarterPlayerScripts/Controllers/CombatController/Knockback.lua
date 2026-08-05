-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/Knockback
-- eased force curve. The avatar remains one rigid assembly; this is not a limb ragdoll.

local RunService = game:GetService("RunService")

local Knockback = {}

type ReactionState = {
	token: number,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	supportPart: BasePart?,
	autoRotate: boolean,
	platformStand: boolean,
	cleaned: boolean,
	attachment: Attachment?,
	force: VectorForce?,
}

local seenHitIds: { [number]: boolean } = {}
local activeStates: { [Model]: ReactionState } = {}
local nextToken = 0

local HIT_ID_MEMORY_SECONDS = 5
local MAX_LAUNCH_SPEED = 140
local MAX_VELOCITY_CORRECTION = 180
local MAX_ANGULAR_SPEED = 20
local TAKEOFF_SPEED = 2
local GROUND_DISTANCE = 1.4
local MAX_LANDING_VERTICAL_SPEED = 12

local function getVerticalHalfExtent(part: BasePart): number
	local size = part.Size
	local cframe = part.CFrame
	return (
		math.abs(cframe.RightVector.Y) * size.X
		+ math.abs(cframe.UpVector.Y) * size.Y
		+ math.abs(cframe.LookVector.Y) * size.Z
	) * 0.5
end

local function isFiniteVector(vector: Vector3): boolean
	return vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z and vector.Magnitude < math.huge
end

local function hasGroundSupport(state: ReactionState): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.character }
	params.IgnoreWater = true
	local part = state.supportPart or state.root
	local bottom = part.Position - Vector3.yAxis * math.max(0, getVerticalHalfExtent(part) - 0.05)
	return workspace:Raycast(bottom, -Vector3.yAxis * GROUND_DISTANCE, params) ~= nil
end

local function cleanupActuator(state: ReactionState)
	if state.force and state.force.Parent then
		state.force:Destroy()
	end
	if state.attachment and state.attachment.Parent then
		state.attachment:Destroy()
	end
	state.force = nil
	state.attachment = nil
end

local function recover(state: ReactionState, settle: boolean)
	if state.cleaned then
		return
	end
	state.cleaned = true
	cleanupActuator(state)
	if activeStates[state.character] == state then
		activeStates[state.character] = nil
	end
	if not (state.root.Parent and state.humanoid.Parent and state.humanoid.Health > 0) then
		return
	end
	state.root.AssemblyAngularVelocity = Vector3.zero
	if settle then
		local velocity = state.root.AssemblyLinearVelocity
		state.root.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.35, 0, velocity.Z * 0.35)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.character }
		params.IgnoreWater = true
		local floor = workspace:Raycast(state.root.Position + Vector3.yAxis * 2, -Vector3.yAxis * 10, params)
		if floor then
			local look = Vector3.new(state.root.CFrame.LookVector.X, 0, state.root.CFrame.LookVector.Z)
			look = if look.Magnitude > 0.001 then look.Unit else Vector3.new(0, 0, -1)
			local position = Vector3.new(
				state.root.Position.X,
				floor.Position.Y + state.humanoid.HipHeight + state.root.Size.Y * 0.5,
				state.root.Position.Z
			)
			state.root.CFrame = CFrame.lookAt(position, position + look)
			state.root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	state.humanoid.AutoRotate = state.autoRotate
	state.humanoid.PlatformStand = state.platformStand
	if not state.platformStand then
		state.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

function Knockback.Apply(
	character: Model,
	hitId: number,
	launchVelocity: Vector3,
	angularVelocity: Vector3,
	durationSeconds: number,
	maximumReactionSeconds: number,
	landingRecoverySeconds: number,
	onLanded: (() -> ())?
): boolean
	if seenHitIds[hitId] then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	if
		hitId % 1 ~= 0
		or durationSeconds ~= durationSeconds
		or not isFiniteVector(launchVelocity)
		or not isFiniteVector(angularVelocity)
	then
		return false
	end
	seenHitIds[hitId] = true
	task.delay(HIT_ID_MEMORY_SECONDS, function()
		seenHitIds[hitId] = nil
	end)

	local previous = activeStates[character]
	if previous then
		recover(previous, false)
	end
	nextToken += 1
	local state: ReactionState = {
		token = nextToken,
		character = character,
		humanoid = humanoid,
		root = root,
		supportPart = character:FindFirstChild("LowerTorso") :: BasePart?,
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
		cleaned = false,
		attachment = nil,
		force = nil,
	}
	activeStates[character] = state

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
	state.attachment = attachment
	state.force = vectorForce

	local desiredVelocity = if launchVelocity.Magnitude > MAX_LAUNCH_SPEED
		then launchVelocity.Unit * MAX_LAUNCH_SPEED
		else launchVelocity
	local desiredAngular = if angularVelocity.Magnitude > MAX_ANGULAR_SPEED
		then angularVelocity.Unit * MAX_ANGULAR_SPEED
		else angularVelocity
	local forceDuration = math.clamp(durationSeconds, 0.08, 0.25)

	task.spawn(function()
		if activeStates[character] ~= state or state.cleaned then
			return
		end
		root.AssemblyAngularVelocity = desiredAngular
		local velocityDelta = desiredVelocity - root.AssemblyLinearVelocity
		if velocityDelta.Magnitude > MAX_VELOCITY_CORRECTION then
			velocityDelta = velocityDelta.Unit * MAX_VELOCITY_CORRECTION
		end
		local elapsed = 0
		while elapsed < forceDuration and activeStates[character] == state and root.Parent and vectorForce.Parent do
			local simulationStep = RunService.PreSimulation:Wait()
			local activeStep = math.min(simulationStep, forceDuration - elapsed)
			local alpha = (elapsed + activeStep * 0.5) / forceDuration
			local easeRate = (math.pi * 0.5 / forceDuration) * math.sin(math.pi * alpha)
			local acceleration = velocityDelta * easeRate + Vector3.yAxis * workspace.Gravity
			vectorForce.Force = acceleration * root.AssemblyMass * (activeStep / simulationStep)
			RunService.PostSimulation:Wait()
			elapsed += activeStep
		end
		cleanupActuator(state)
	end)

	task.spawn(function()
		local startedAt = os.clock()
		local observedTakeoff = false
		while activeStates[character] == state and not state.cleaned do
			local velocity = root.AssemblyLinearVelocity
			if velocity.Y >= TAKEOFF_SPEED or not hasGroundSupport(state) then
				observedTakeoff = true
			end
			if
				observedTakeoff
				and velocity.Y <= 0
				and math.abs(velocity.Y) <= MAX_LANDING_VERTICAL_SPEED
				and hasGroundSupport(state)
			then
				if onLanded then
					task.defer(onLanded)
				end
				task.wait(math.max(0, landingRecoverySeconds))
				recover(state, true)
				return
			end
			if os.clock() - startedAt >= math.max(0.1, maximumReactionSeconds) then
				recover(state, true)
				return
			end
			task.wait(0.03)
		end
	end)
	return true
end

function Knockback.Clear(character: Model)
	local state = activeStates[character]
	if state then
		recover(state, false)
	end
end

return Knockback
