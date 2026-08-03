-- StarterPlayer/StarterPlayerScripts/ClientModules/ShieldSlideController
-- airborne knockback/tumble state. Only horizontal velocity is constrained.

local RunService = game:GetService("RunService")

local ShieldSlideController = {}

type SlideState = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	attachment: Attachment?,
	linearVelocity: LinearVelocity?,
	cleaned: boolean,
}

local seenHitIds: { [number]: boolean } = {}
local activeStates: { [Model]: SlideState } = {}

local HIT_ID_MEMORY_SECONDS = 5
local MAX_PLANAR_SPEED = 100
local MIN_SLIDE_SECONDS = 0.08
local MAX_SLIDE_SECONDS = 0.75
local FULL_SPEED_FRACTION = 0.55

local function isFiniteVector(vector: Vector3): boolean
	return vector.X == vector.X
		and vector.Y == vector.Y
		and vector.Z == vector.Z
		and vector.Magnitude < math.huge
end

local function cleanup(state: SlideState)
	if state.cleaned then
		return
	end
	state.cleaned = true
	if state.linearVelocity and state.linearVelocity.Parent then
		state.linearVelocity:Destroy()
	end
	if state.attachment and state.attachment.Parent then
		state.attachment:Destroy()
	end
	state.linearVelocity = nil
	state.attachment = nil
	if activeStates[state.character] == state then
		activeStates[state.character] = nil
	end
end

function ShieldSlideController.Apply(
	character: Model,
	hitId: number,
	launchVelocity: Vector3,
	durationSeconds: number
): boolean
	if seenHitIds[hitId] then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	if hitId % 1 ~= 0
		or durationSeconds ~= durationSeconds
		or not isFiniteVector(launchVelocity)
	then
		return false
	end

	local planarVelocity = Vector3.new(launchVelocity.X, 0, launchVelocity.Z)
	if planarVelocity.Magnitude <= 0.001 then
		return false
	end
	if planarVelocity.Magnitude > MAX_PLANAR_SPEED then
		planarVelocity = planarVelocity.Unit * MAX_PLANAR_SPEED
	end
	local duration = math.clamp(durationSeconds, MIN_SLIDE_SECONDS, MAX_SLIDE_SECONDS)

	seenHitIds[hitId] = true
	task.delay(HIT_ID_MEMORY_SECONDS, function()
		seenHitIds[hitId] = nil
	end)

	local previous = activeStates[character]
	if previous then
		cleanup(previous)
	end

	local state: SlideState = {
		character = character,
		humanoid = humanoid,
		root = root,
		attachment = nil,
		linearVelocity = nil,
		cleaned = false,
	}
	activeStates[character] = state

	local attachment = Instance.new("Attachment")
	attachment.Name = "ShieldSlideAttachment"
	attachment.Parent = root

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "ShieldGroundSlide"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVelocity.PrimaryTangentAxis = Vector3.xAxis
	linearVelocity.SecondaryTangentAxis = Vector3.zAxis
	linearVelocity.PlaneVelocity = Vector2.new(planarVelocity.X, planarVelocity.Z)
	-- A Humanoid's locomotion forces can be strong; this short-lived constraint must
	-- win while active so the configured server-authorized slide is deterministic.
	linearVelocity.ForceLimitsEnabled = false
	linearVelocity.Parent = root
	state.attachment = attachment
	state.linearVelocity = linearVelocity

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration
			and activeStates[character] == state
			and not state.cleaned
			and humanoid.Health > 0
			and root.Parent
			and linearVelocity.Parent
		do
			local step = RunService.PreSimulation:Wait()
			elapsed += step
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local speedScale = 1
			if alpha > FULL_SPEED_FRACTION then
				local releaseAlpha = (alpha - FULL_SPEED_FRACTION) / (1 - FULL_SPEED_FRACTION)
				-- Smoothly brake the planar slide without touching vertical velocity.
				speedScale = 1 - (releaseAlpha * releaseAlpha * (3 - 2 * releaseAlpha))
			end
			linearVelocity.PlaneVelocity = Vector2.new(
				planarVelocity.X * speedScale,
				planarVelocity.Z * speedScale
			)
		end
		cleanup(state)
	end)

	return true
end

function ShieldSlideController.Clear(character: Model)
	local state = activeStates[character]
	if state then
		cleanup(state)
	end
end

return ShieldSlideController
