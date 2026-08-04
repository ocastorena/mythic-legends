-- ServerScriptService/Services/BaseService/BaseUtil
local BaseUtil = {}

local function getFreeSlot(slots: any, maxSlots: number): number?
	for i = 1, maxSlots do
		if not slots[i] then
			return i
		end
	end
	return nil
end

local function getPartBottomY(part: BasePart): number
	local cf = part.CFrame
	local size = part.Size
	local halfHeight = math.abs(cf.XVector.Y) * size.X * 0.5
		+ math.abs(cf.YVector.Y) * size.Y * 0.5
		+ math.abs(cf.ZVector.Y) * size.Z * 0.5
	return cf.Position.Y - halfHeight
end

-- Utility markers can extend below the visible base and make the platform appear to float.
-- Use the largest visible footprint as the structural placement surface instead.
local function getPivotAboveStructuralBottom(model: Model): number
	local structuralPart: BasePart? = nil
	local largestFootprint = 0

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart")
			and descendant.Transparency < 1
			and descendant.Name ~= "Front"
			and descendant.Name ~= "Spawn"
		then
			local footprint = descendant.Size.X * descendant.Size.Z
			if footprint > largestFootprint then
				structuralPart = descendant
				largestFootprint = footprint
			end
		end
	end

	if structuralPart then
		return model:GetPivot().Position.Y - getPartBottomY(structuralPart)
	end

	local boundsCF, boundsSize = model:GetBoundingBox()
	local modelBottomY = boundsCF.Position.Y - boundsSize.Y * 0.5
	return model:GetPivot().Position.Y - modelBottomY
end

-- The buildable surface of an island is its flat "Grass" cap. Its centre is the island's
-- true centre, which the island model's own pivot is not (the pivots sit on a clean ring
-- at radius 400 while the geometry is centred further out).
local function getIslandSurface(island: Model): (Vector3, number)
	local grass = island:FindFirstChild("Grass")
	if grass and grass:IsA("BasePart") then
		return grass.Position, grass.Position.Y + grass.Size.Y * 0.5
	end

	-- fall back to overall bounds if the cap is ever renamed
	local cf, size = island:GetBoundingBox()
	return cf.Position, cf.Position.Y + size.Y * 0.5
end

-- Bases sit on the authored BaseIsland models -- one island per slot -- facing the arena.
-- Reading placement off the islands means moving one in Studio moves its base with it.
local function getSlotPlacement(slotIndex: number, model: Model, baseIslands: Folder, arena: BasePart): (CFrame?, string?)
	local islandName = "BaseIsland" .. (slotIndex - 1)
	local island = baseIslands:FindFirstChild(islandName)
	if not (island and island:IsA("Model")) then
		return nil, `Missing island {islandName} for slot {slotIndex}`
	end

	local surfaceCenter, surfaceTopY = getIslandSurface(island)
	local y = surfaceTopY + getPivotAboveStructuralBottom(model)

	local pos = Vector3.new(surfaceCenter.X, y, surfaceCenter.Z)
	local facing = Vector3.new(arena.Position.X, y, arena.Position.Z)
	return CFrame.lookAt(pos, facing), nil
end


function BaseUtil.SpawnBaseFor(player: Player, slots: any, maxSlots: number, baseModel: Model, arena: BasePart, baseIslands: Folder, basesFolder: Folder)
	-- check if player already has a base
	local userId = player.UserId
	for _, slot in pairs(slots) do
		if slot.userId == userId then
			return false, "Player already has a base"
		end
	end
	-- check if there is a free slot
	local slotIndex = getFreeSlot(slots, maxSlots)
	if not slotIndex then
		return false, "No free base slots"
	end
	-- spawn base
	local model = baseModel and baseModel:Clone()
	if not model then
		return false, "Base model not found"
	end
	-- base position
	local position, placementError = getSlotPlacement(slotIndex, model, baseIslands, arena)
	if not position then
		model:Destroy()
		return false, placementError or "Could not get position"
	end
	
	model.Name = tostring(userId)
	model:WaitForChild("NameSign"):WaitForChild("SurfaceGui"):WaitForChild("Name").Text = player.DisplayName
	
	for _, prompt in model.Stands:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt:SetAttribute("OwnerId", userId)
		end
	end
	
	model.Parent = basesFolder
	model:PivotTo(position)
	-- update slots
	slots[slotIndex] = { userId = userId, base = model }
	return true
end

function BaseUtil.TeleportToBaseSpawn(player: Player, char: Model, base: Model)
	if not base then 
		return false, "Base not found"
	end

	local spawnPart = base:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then 
		return false, "Base does not have a spawn part"
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "HRP not found"
	end

	local pos = spawnPart.Position + Vector3.new(0, 3, 0)
	local look = spawnPart.CFrame.LookVector
	hrp.CFrame = CFrame.lookAt(pos, pos + look)
	return true
end

function BaseUtil.RemoveBaseFor(player: Player, slots: any)
	local userId = player.UserId
	for i, slot in pairs(slots) do
		if slot.userId == userId then
			slot.base:Destroy()
			slots[i] = nil
			return true
		end
	end
	return false, "Base not found"
end

return BaseUtil
