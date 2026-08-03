-- ReplicatedStorage/SharedModules/ArenaBounds
-- Shared geometric Arena membership check used by client presentation and server validation.

local ArenaBounds = {}

function ArenaBounds.Contains(arena: BasePart?, position: Vector3, heightAllowanceStuds: number?): boolean
	if not arena then
		return false
	end

	local localPosition = arena.CFrame:PointToObjectSpace(position)
	local radius = math.max(arena.Size.X, arena.Size.Z) * 0.5
	local horizontalDistance = Vector2.new(localPosition.X, localPosition.Z).Magnitude
	local heightAllowance = if type(heightAllowanceStuds) == "number"
		then math.max(0, heightAllowanceStuds)
		else 0

	return horizontalDistance <= radius
		and math.abs(localPosition.Y) <= arena.Size.Y * 0.5 + heightAllowance
end

return ArenaBounds
