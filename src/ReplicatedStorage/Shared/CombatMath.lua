--!strict
-- ReplicatedStorage/Shared/CombatMath
-- Deterministic combat validation helpers shared by server runtime and tests.

local CombatMath = {}

function CombatMath.IsValidSequence(value: unknown, maximum: number): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= maximum
end

function CombatMath.IsWithinGuardArc(
	attackerPosition: Vector3,
	targetPosition: Vector3,
	targetLookVector: Vector3,
	degrees: number
): boolean
	local offset = attackerPosition - targetPosition
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local planarFacing = Vector3.new(targetLookVector.X, 0, targetLookVector.Z)
	if planarOffset.Magnitude <= 0.001 or planarFacing.Magnitude <= 0.001 then
		return false
	end

	local halfArcRadians = math.rad(math.clamp(degrees, 0, 360) * 0.5)
	return planarFacing.Unit:Dot(planarOffset.Unit) >= math.cos(halfArcRadians)
end

return table.freeze(CombatMath)
