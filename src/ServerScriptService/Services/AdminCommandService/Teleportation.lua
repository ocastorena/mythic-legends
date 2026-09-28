--!strict
-- ServerScriptService/Services/AdminCommandService/Teleportation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local Teleportation = {}

function Teleportation.ResolveMarker(
	destination: string,
	world: Instance?,
	baseSpawn: BasePart?,
	config: Types.AdminCommandsConfiguration
): (BasePart?, string)
	if destination == "base" then
		if not baseSpawn then
			return nil, "Your Base is not ready yet. Try again shortly."
		end
		return baseSpawn, "your Base"
	end

	local definition = config.destinations[destination]
	if not definition then
		return nil, "Unknown destination. Use fire, water, earth, air, light, dark, or base."
	end
	local islands = world and world:FindFirstChild("ElementalIslands")
	local island = islands and islands:FindFirstChild(definition.islandName)
	local markers = island and island:FindFirstChild("Markers")
	local marker = markers and markers:FindFirstChild(config.islandMarkerName)
	if not marker or not marker:IsA("BasePart") then
		return nil, `{definition.displayName} is not ready for teleporting yet.`
	end
	return marker, definition.displayName
end

function Teleportation.GetArrival(
	character: Model,
	marker: BasePart,
	world: WorldRoot,
	config: Types.AdminCommandsConfiguration
): (CFrame?, string?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, "Your character is not ready to teleport."
	end
	if humanoid.SeatPart or humanoid.Sit then
		return nil, "Stand up before teleporting."
	end
	if not marker.Anchored or marker.CFrame.UpVector.Y < 0.99 then
		return nil, "The destination landing point needs to be anchored and level."
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, marker }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	params.CollisionGroup = root.CollisionGroup
	local top = marker.Position + Vector3.yAxis * marker.Size.Y * 0.5
	local ground = world:Raycast(
		top + Vector3.yAxis * config.groundProbeAboveStuds,
		-Vector3.yAxis * (config.groundProbeAboveStuds + config.groundProbeBelowStuds),
		params
	)
	if not ground or ground.Normal.Y < config.minimumGroundNormalY then
		return nil, "There is no safe ground at that landing point."
	end
	if ground.Position.Y > top.Y + config.arrivalPaddingStuds then
		return nil, "The landing point is obstructed."
	end
	-- Another player is not a landing surface, even if their body can collide.
	local supportModel = ground.Instance:FindFirstAncestorOfClass("Model")
	if supportModel and supportModel:FindFirstChildOfClass("Humanoid") then
		return nil, "The landing point is occupied. Try again shortly."
	end

	local feetToRoot = humanoid.HipHeight + root.Size.Y * 0.5
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leg = character:FindFirstChild("Left Leg")
		if leg and leg:IsA("BasePart") then
			feetToRoot += leg.Size.Y
		end
	end
	local head = character:FindFirstChild("Head")
	local headHeight = if head and head:IsA("BasePart") then head.Size.Y else root.Size.Y
	local standingHeight = feetToRoot + root.Size.Y * 0.5 + headHeight
	local clearance = config.arrivalPaddingStuds
	local feetPosition = Vector3.new(top.X, math.max(top.Y, ground.Position.Y) + clearance, top.Z)
	if world:Raycast(feetPosition, Vector3.yAxis * standingHeight, params) then
		return nil, "There is not enough room above that landing point."
	end

	local look = marker.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z).Unit
	local position = feetPosition + Vector3.yAxis * feetToRoot
	local targetRoot = CFrame.lookAt(position, position + facing)
	-- Preserve a custom model pivot while placing the character's root at the destination.
	return targetRoot * root.CFrame:ToObjectSpace(character:GetPivot()), nil
end

function Teleportation.MoveCharacter(character: Model, arrival: CFrame)
	character:PivotTo(arrival)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

return Teleportation
