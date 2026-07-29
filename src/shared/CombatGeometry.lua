-- Shared directional combat tests used by client prediction and server validation.

local CombatGeometry = {}

local EPSILON = 0.001

local function getPlanarUnit(vector: Vector3): Vector3?
	local planar = Vector3.new(vector.X, 0, vector.Z)
	return if planar.Magnitude > EPSILON then planar.Unit else nil
end

function CombatGeometry.IsPositionInsideFacingArc(
	origin: Vector3,
	forward: Vector3,
	position: Vector3,
	totalArcDegrees: number
): boolean
	local direction = getPlanarUnit(position - origin)
	if not direction then
		return true
	end

	local planarForward = getPlanarUnit(forward)
	if not planarForward then
		return false
	end

	local clampedArc = math.clamp(totalArcDegrees, 0, 360)
	local minimumDot = math.cos(math.rad(clampedArc * 0.5))
	return planarForward:Dot(direction) >= minimumDot
end

return CombatGeometry
