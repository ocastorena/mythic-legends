--!strict
-- ServerScriptService/Services/CombatService/EarthLanding
-- Observe server-visible support only; CombatState owns takeoff history and the fixed deadline.

export type Tuning = {
	supportAllowanceStuds: number,
	minimumGroundNormalY: number,
	takeoffVelocityStudsPerSecond: number,
}
export type GroundHit = { distance: number, normal: Vector3 }
export type Raycast = (Vector3, Vector3, RaycastParams) -> GroundHit?
export type Observation = { airborne: boolean, supported: boolean }

local EarthLanding = {}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function finiteVector(value: Vector3): boolean
	return finite(value.X) and finite(value.Y) and finite(value.Z)
end

local function verticalHalfExtent(part: BasePart): number
	local frame, size = part.CFrame, part.Size
	return (
		math.abs(frame.RightVector.Y) * size.X
		+ math.abs(frame.UpVector.Y) * size.Y
		+ math.abs(frame.LookVector.Y) * size.Z
	) / 2
end

local function cast(origin: Vector3, direction: Vector3, params: RaycastParams): GroundHit?
	local result = workspace:Raycast(origin, direction, params)
	return if result then { distance = result.Distance, normal = result.Normal } else nil
end

local function hasSupport(
	origin: Vector3,
	reach: number,
	minimumNormal: number,
	params: RaycastParams,
	raycast: Raycast
): boolean
	if not finiteVector(origin) or not finite(reach) or reach <= 0 then
		return false
	end
	local hit = raycast(origin, -Vector3.yAxis * reach, params)
	return hit ~= nil
		and finite(hit.distance)
		and hit.distance >= 0
		and hit.distance <= reach
		and finiteVector(hit.normal)
		and hit.normal.Y >= minimumNormal
end

function EarthLanding.Sample(
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	tuning: Tuning,
	raycast: Raycast?
): Observation
	if
		not humanoid:IsDescendantOf(character)
		or not root:IsDescendantOf(character)
		or humanoid.Health <= 0
		or not finite(humanoid.HipHeight)
		or humanoid.HipHeight < 0
		or not finite(tuning.supportAllowanceStuds)
		or tuning.supportAllowanceStuds < 0
		or not finite(tuning.minimumGroundNormalY)
		or tuning.minimumGroundNormalY <= 0
		or tuning.minimumGroundNormalY > 1
		or not finite(tuning.takeoffVelocityStudsPerSecond)
		or tuning.takeoffVelocityStudsPerSecond < 0
		or not finiteVector(root.AssemblyLinearVelocity)
	then
		return { airborne = false, supported = false }
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	params.RespectCanCollide = true
	params.CollisionGroup = root.CollisionGroup
	local ray = raycast or cast
	-- Upright: HipHeight + half root height. Tipping/inverting removes the unearned upright
	-- reach; a tumbling character must not count as landed while its body remains above ground.
	local reach = verticalHalfExtent(root)
		+ humanoid.HipHeight * math.max(0, root.CFrame.UpVector.Y)
		+ tuning.supportAllowanceStuds
	local supported = hasSupport(root.Position, reach, tuning.minimumGroundNormalY, params, ray)
	if not supported then
		local torso = character:FindFirstChild("LowerTorso")
		if torso and torso:IsA("BasePart") then
			-- A short geometric torso probe covers physical support while tipped. It never adds
			-- standing HipHeight and remains subject to the same normal/collision requirements.
			local torsoReach = verticalHalfExtent(torso) + tuning.supportAllowanceStuds
			supported =
				hasSupport(torso.Position, torsoReach, tuning.minimumGroundNormalY, params, ray)
		end
	end
	local verticalVelocity = root.AssemblyLinearVelocity.Y
	return {
		airborne = not supported or verticalVelocity > tuning.takeoffVelocityStudsPerSecond,
		-- Small ascending velocities below the takeoff threshold remain undecided, not landings.
		supported = supported and verticalVelocity <= 0,
	}
end

return table.freeze(EarthLanding)
