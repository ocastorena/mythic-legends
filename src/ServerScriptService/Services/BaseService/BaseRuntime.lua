--!strict
-- ServerScriptService/Services/BaseService/BaseRuntime
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BaseState = require(ServerScriptService.Domain.Base.BaseState)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local Types = require(ReplicatedStorage.Shared.Types)

local BaseRuntime = {}
export type Slots = { [number]: { userId: number, base: Model } }

local function applyCapacity(model: Model, status: Types.BaseStatus)
	model:SetAttribute("UsedShrineSlots", status.usedShrineSlots)
	model:SetAttribute("UnlockedShrineSlots", status.unlockedShrineSlots)
	model:SetAttribute("MaxShrineSlots", status.maxShrineSlots)
end

-- Presentation only: purchases always validate the saved Base, never these attributes.
function BaseRuntime.RefreshCapacity(model: Model, baseRecord: Types.BaseRecord): boolean
	local status = BaseState.GetStatus(baseRecord)
	if not status then
		return false
	end
	applyCapacity(model, status)
	return true
end

local function getFreeSlot(slots: Slots, maxSlots: number): number?
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
	local authoredOffset = model:GetAttribute("PlacementBottomOffset")
	if type(authoredOffset) == "number" then
		return authoredOffset
	end

	local structuralPart: BasePart? = nil
	local largestFootprint = 0

	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
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

-- The buildable surface of an island is its flat Collision.Grass cap. Its centre is the island's
-- true centre, which the island model's own pivot is not (the pivots sit on a clean ring
-- at radius 400 while the geometry is centred further out).
local function getIslandSurface(island: Model): (Vector3, number)
	local collision = island:FindFirstChild("Collision")
	local grass = collision and collision:FindFirstChild("Grass")
	if grass and grass:IsA("BasePart") then
		return grass.Position, grass.Position.Y + grass.Size.Y * 0.5
	end

	-- fall back to overall bounds if the cap is ever renamed
	local cf, size = island:GetBoundingBox()
	return cf.Position, cf.Position.Y + size.Y * 0.5
end

-- Bases sit on the authored BaseIsland models -- one island per slot -- facing the arena.
-- Reading placement off the islands means moving one in Studio moves its base with it.
local function getSlotPlacement(
	slotIndex: number,
	model: Model,
	baseIslands: Folder,
	arena: BasePart
): (CFrame?, string?)
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

function BaseRuntime.SpawnBaseFor(
	player: Player,
	slots: Slots,
	maxSlots: number,
	baseModel: Model?,
	baseRecord: Types.BaseRecord,
	arena: BasePart,
	baseIslands: Folder,
	basesFolder: Folder
): (boolean, string?)
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

	local status = BaseState.GetStatus(baseRecord)
	if not status then
		return false, "Base state is invalid or not initialized"
	end
	local stationDefinition = CraftingStations[status.craftingStation.craftingStationId]
	if not stationDefinition then
		return false,
			`Unknown Crafting Station definition: {status.craftingStation.craftingStationId}`
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
	local sign = model:FindFirstChild("NameSign")
	local surface = sign and sign:FindFirstChild("SurfaceGui")
	local label = surface and surface:FindFirstChild("Name")
	local stands = model:FindFirstChild("Stands")
	local station = model:FindFirstChild(stationDefinition.modelName)
	if not label or not label:IsA("TextLabel") or not stands then
		model:Destroy()
		return false, "Base template is missing its name label or Stands"
	end
	if not station or not station:IsA("Model") then
		model:Destroy()
		return false,
			`Base template is missing Crafting Station model {stationDefinition.modelName}`
	end
	label.Text = player.DisplayName
	applyCapacity(model, status)
	station:SetAttribute("StationInstanceId", status.craftingStation.id)
	station:SetAttribute("StationDefinitionId", status.craftingStation.craftingStationId)
	station:SetAttribute("OwnerId", userId)

	for _, prompt in stands:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt:SetAttribute("OwnerId", userId)
		end
	end

	model:PivotTo(position)
	model.Parent = basesFolder
	-- update slots
	slots[slotIndex] = { userId = userId, base = model }
	return true, nil
end

function BaseRuntime.TeleportToBaseSpawn(
	_player: Player,
	char: Model,
	base: Model
): (boolean, string?)
	if not base then
		return false, "Base not found"
	end

	local spawnPart = base:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return false, "Base does not have a spawn part"
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return false, "HRP not found"
	end

	local pos = spawnPart.Position + Vector3.new(0, 3, 0)
	local look = spawnPart.CFrame.LookVector
	hrp.CFrame = CFrame.lookAt(pos, pos + look)
	return true, nil
end

function BaseRuntime.RemoveBaseFor(player: Player, slots: Slots): (boolean, string?)
	local userId = player.UserId
	for i, slot in pairs(slots) do
		if slot.userId == userId then
			slot.base:Destroy()
			slots[i] = nil
			return true, nil
		end
	end
	return false, "Base not found"
end

return BaseRuntime
