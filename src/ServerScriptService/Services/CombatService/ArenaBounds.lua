--!strict
-- ServerScriptService/Services/CombatService/ArenaBounds
-- Shared geometric Arena membership check used by client presentation and server validation.

local ArenaBounds = {}

local function isInsideRegularPolygon(arena: BasePart, localPosition: Vector3): boolean
	local sideCount = arena:GetAttribute("BoundarySides")
	local apothem = arena:GetAttribute("BoundaryApothem")
	if
		type(sideCount) ~= "number"
		or type(apothem) ~= "number"
		or sideCount < 3
		or apothem <= 0
	then
		local radius = math.max(arena.Size.X, arena.Size.Z) * 0.5
		return Vector2.new(localPosition.X, localPosition.Z).Magnitude <= radius
	end

	local sides = math.floor(sideCount)
	for sideIndex = 0, sides - 1 do
		local angle = 2 * math.pi * sideIndex / sides
		local distanceToSide = localPosition.X * math.cos(angle) + localPosition.Z * math.sin(angle)
		if distanceToSide > apothem then
			return false
		end
	end
	return true
end

function ArenaBounds.Contains(
	arena: BasePart?,
	position: Vector3,
	heightAllowanceStuds: number?
): boolean
	if not arena then
		return false
	end

	local localPosition = arena.CFrame:PointToObjectSpace(position)
	local heightAllowance = if type(heightAllowanceStuds) == "number"
		then math.max(0, heightAllowanceStuds)
		else 0

	return isInsideRegularPolygon(arena, localPosition)
		and math.abs(localPosition.Y) <= arena.Size.Y * 0.5 + heightAllowance
end

return ArenaBounds
