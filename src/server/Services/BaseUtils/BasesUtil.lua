-- ServerScriptService/Systems/BaseService/BasesUtil
local BasesUtil = {}

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

local function getSlotPosition(slotIndex: number, arena: BasePart, arenaPlate: BasePart, maxSlots: number): CFrame
	local center, arenaR = getArenaCenterAndRadius(arena)
	local ringOffset = 24
	local ringR = arenaR + ringOffset

	local angle = (2 * math.pi) * ((slotIndex - 1) / maxSlots)
	local pos = center + Vector3.new(math.cos(angle) * ringR, 0, math.sin(angle) * ringR)

	local y = arenaPlate.Position.Y + (arenaPlate.Size.X) -- sits on plate
	return CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(center.X, y, center.Z))
end


function BasesUtil.SpawnBaseFor(player: Player, slots: any, maxSlots: number, baseModel: Model, arena: BasePart, arenaPlate: BasePart, basesFolder: Folder)
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
	local position = getSlotPosition(slotIndex, arena, arenaPlate, maxSlots)
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

function BasesUtil.TeleportToBaseSpawn(player: Player, char: Model, base: Model)
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

function BasesUtil.RemoveBaseFor(player: Player, slots: any)
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

return BasesUtil
