-- Stable launch reaction for light weapons. The avatar stays one rigid assembly instead
-- of becoming a multi-body ragdoll, which avoids limb/floor solver bounce on landing.

local KnockdownUtil = {}

type KnockdownState = {
	token: number,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	rootAnchored: boolean,
	supportPart: BasePart?,
	supportCanCollide: boolean?,
	autoRotate: boolean,
	platformStand: boolean,
}

local activeStates: { [Model]: KnockdownState } = {}
local nextToken = 0

local POLL_SECONDS = 0.03
local TAKEOFF_SPEED = 2
local GROUND_DISTANCE = 1.4
local MAX_LANDING_VERTICAL_SPEED = 12

local function getSupportPart(character: Model): BasePart?
	for _, name in ipairs({ "LowerTorso", "Torso" }) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
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

local function hasGroundSupport(state: KnockdownState, params: RaycastParams): boolean
	local part = state.supportPart or state.root
	local bottom = part.Position - Vector3.yAxis * math.max(0, getVerticalHalfExtent(part) - 0.05)
	return workspace:Raycast(bottom, -Vector3.yAxis * GROUND_DISTANCE, params) ~= nil
end

local function settle(state: KnockdownState, uprightOnGround: boolean?)
	if not state.root.Parent then
		return
	end

	local velocity = state.root.AssemblyLinearVelocity
	state.root.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.35, 0, velocity.Z * 0.35)
	state.root.AssemblyAngularVelocity = Vector3.zero

	if uprightOnGround then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { state.character }
		params.IgnoreWater = true
		local floor = workspace:Raycast(state.root.Position + Vector3.yAxis * 2, -Vector3.yAxis * 10, params)
		if floor then
			local look = Vector3.new(state.root.CFrame.LookVector.X, 0, state.root.CFrame.LookVector.Z)
			if look.Magnitude <= 0.001 then
				look = Vector3.new(0, 0, -1)
			else
				look = look.Unit
			end
			local standingPosition = Vector3.new(
				state.root.Position.X,
				floor.Position.Y + state.humanoid.HipHeight + state.root.Size.Y * 0.5,
				state.root.Position.Z
			)
			state.root.CFrame = CFrame.lookAt(standingPosition, standingPosition + look)
			state.root.AssemblyLinearVelocity = Vector3.zero
			state.root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function restore(state: KnockdownState)
	if state.supportPart and state.supportPart.Parent and state.supportCanCollide ~= nil then
		state.supportPart.CanCollide = state.supportCanCollide
	end
	if state.root.Parent then
		state.root.Anchored = state.rootAnchored
	end

	local humanoid = state.humanoid
	if humanoid.Parent and humanoid.Health > 0 then
		humanoid.AutoRotate = state.autoRotate
		humanoid.PlatformStand = state.platformStand
	end
end

function KnockdownUtil.Stop(character: Model, expectedToken: number?, shouldSettle: boolean?): boolean
	local state = activeStates[character]
	if not state or (expectedToken and state.token ~= expectedToken) then
		return false
	end

	activeStates[character] = nil
	if shouldSettle then
		settle(state, true)
	end
	restore(state)
	return true
end

function KnockdownUtil.Start(character: Model, maximumDurationSeconds: number): (boolean, number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return false, nil
	end

	local existing = activeStates[character]
	if existing then
		nextToken += 1
		existing.token = nextToken
		return true, existing.token
	end

	nextToken += 1
	local supportPart = getSupportPart(character)
	local state: KnockdownState = {
		token = nextToken,
		character = character,
		humanoid = humanoid,
		root = root,
		rootAnchored = root.Anchored,
		supportPart = supportPart,
		supportCanCollide = if supportPart then supportPart.CanCollide else nil,
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
	}
	activeStates[character] = state

	if supportPart then
		supportPart.CanCollide = true
	end
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local token = state.token
	task.delay(math.max(0.1, maximumDurationSeconds), function()
		KnockdownUtil.Stop(character, token, true)
	end)
	return true, token
end

function KnockdownUtil.StopAfterLanding(
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
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	task.spawn(function()
		local observedTakeoff = false
		while activeStates[character] == state and state.token == token do
			local velocity = state.root.AssemblyLinearVelocity
			if velocity.Y >= TAKEOFF_SPEED or not hasGroundSupport(state, params) then
				observedTakeoff = true
			end

			if observedTakeoff
				and velocity.Y <= 0
				and math.abs(velocity.Y) <= MAX_LANDING_VERTICAL_SPEED
				and hasGroundSupport(state, params) then
				-- Hold the already-authorized character still during the short recovery.
				-- This prevents the contact solver from adding a second upward launch.
				settle(state, true)
				state.root.Anchored = true
				if onLanded then
					pcall(onLanded)
				end
				task.delay(math.max(0, recoverySeconds), function()
					if KnockdownUtil.Stop(character, token, true) and onRecovered then
						pcall(onRecovered)
					end
				end)
				return
			end
			task.wait(POLL_SECONDS)
		end
	end)

	return true
end

return KnockdownUtil
