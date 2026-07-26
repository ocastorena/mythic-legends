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

local function getArenaCenterAndRadius(Arena: BasePart): (Vector3, number)
	local cf, size = Arena.CFrame, Arena.Size
	local radius = math.max(size.X, size.Z) * 0.5
	return cf.Position, radius
end

-- World Y the model's pivot must sit at for the model to rest on top of the plate.
-- Derived from the plate's thickness and the model's own bounds so that resizing the
-- arena or swapping in a taller base model can't leave bases floating.
local function getGroundedPivotY(model: Model, arenaPlate: BasePart): number
	local plateTopY = arenaPlate.Position.Y + arenaPlate.Size.Y * 0.5

	-- a model's pivot is rarely at its lowest point, so offset by that gap
	local boundsCF, boundsSize = model:GetBoundingBox()
	local modelBottomY = boundsCF.Position.Y - boundsSize.Y * 0.5
	local pivotAboveBottom = model:GetPivot().Position.Y - modelBottomY

	return plateTopY + pivotAboveBottom
end

local function getSlotPosition(slotIndex: number, arena: BasePart, maxSlots: number, y: number): CFrame
	local center, arenaR = getArenaCenterAndRadius(arena)
	local ringOffset = 24
	local ringR = arenaR + ringOffset

	local angle = (2 * math.pi) * ((slotIndex - 1) / maxSlots)
	local pos = center + Vector3.new(math.cos(angle) * ringR, 0, math.sin(angle) * ringR)

	return CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(center.X, y, center.Z))
end


function BaseUtil.SpawnBaseFor(player: Player, slots: any, maxSlots: number, baseModel: Model, arena: BasePart, arenaPlate: BasePart, basesFolder: Folder)
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
	local groundedY = getGroundedPivotY(model, arenaPlate)
	local position = getSlotPosition(slotIndex, arena, maxSlots, groundedY)
	if not position then
		return false, "Could not get position"
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
