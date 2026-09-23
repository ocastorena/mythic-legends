--!strict
-- ServerScriptService/Services/MythlingSpawnService/SpawnPlacement
-- Pure horizontal placement, shared by random attempts and deterministic recovery.

local SpawnPlacement = {}

export type Bounds = { radius: number, sides: number?, apothem: number? }
export type Ring = { x: number, z: number, radius: number }

function SpawnPlacement.IsValid(
	x: number,
	z: number,
	radius: number,
	bounds: Bounds,
	occupied: { Ring },
	padding: number,
	boundaryClearance: number
): boolean
	local margin = radius + boundaryClearance
	local sides, apothem = bounds.sides, bounds.apothem
	if sides and apothem then
		for side = 0, sides - 1 do
			local angle = 2 * math.pi * side / sides
			if x * math.cos(angle) + z * math.sin(angle) + margin > apothem then
				return false
			end
		end
	elseif margin > bounds.radius or x * x + z * z > (bounds.radius - margin) ^ 2 then
		return false
	end
	for _, ring in occupied do
		local dx, dz = x - ring.x, z - ring.z
		if dx * dx + dz * dz < (radius + ring.radius + padding) ^ 2 then
			return false
		end
	end
	return true
end

function SpawnPlacement.FindFallback(
	radius: number,
	bounds: Bounds,
	occupied: { Ring },
	padding: number,
	boundaryClearance: number,
	stepStuds: number
): (number?, number?)
	-- The circumscribed square also covers the corners of an attributed polygon.
	local extent = bounds.radius
	if bounds.sides and bounds.apothem then
		extent = bounds.apothem / math.cos(math.pi / bounds.sides)
	end
	local steps = math.ceil(extent / stepStuds)
	-- Check central positions first; every candidate passes the same clearance rules.
	for shell = 0, steps do
		for ix = -shell, shell do
			local stride = if math.abs(ix) == shell then 1 else math.max(1, shell * 2)
			for iz = -shell, shell, stride do
				local x, z = ix * stepStuds, iz * stepStuds
				if
					SpawnPlacement.IsValid(
						x,
						z,
						radius,
						bounds,
						occupied,
						padding,
						boundaryClearance
					)
				then
					return x, z
				end
			end
		end
	end
	return nil, nil
end

return table.freeze(SpawnPlacement)
