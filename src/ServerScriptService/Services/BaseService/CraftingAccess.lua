--!strict
-- ServerScriptService/Services/BaseService/CraftingAccess
-- Resolve proximity from server-owned Base slots and an explicit authored Station anchor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local BaseState = require(ServerScriptService.Shared.BaseState)
local BaseRuntime = require(script.Parent.BaseRuntime)

local CraftingAccess = {}

local function uniqueChild(parent: Instance, name: string): Instance?
	local found: Instance? = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if found then
				return nil
			end
			found = child
		end
	end
	return found
end

function CraftingAccess.Check(
	userId: number,
	character: Model?,
	baseRecord: Types.BaseRecord,
	slots: BaseRuntime.Slots,
	basesFolder: Folder,
	stationInstanceId: string?
): string?
	if type(baseRecord) ~= "table" or getmetatable(baseRecord) ~= nil then
		return "InvalidBaseState"
	end
	local status = BaseState.GetStatus(baseRecord)
	if not status then
		return "InvalidBaseState"
	end
	local savedStation = status.craftingStation
	if stationInstanceId ~= nil and stationInstanceId ~= savedStation.id then
		return "StationChanged"
	end
	local definition = CraftingStations[savedStation.craftingStationId]
	local distanceLimit = definition.interactionDistanceStuds
	if not (distanceLimit > 0 and distanceLimit < math.huge) then
		return "StationUnavailable"
	end
	local base: Model? = nil
	for _, slot in slots do
		if slot.userId == userId then
			if base then
				return "StationUnavailable"
			end
			base = slot.base
		end
	end
	if not base or base.Parent ~= basesFolder or not basesFolder:IsDescendantOf(workspace) then
		return "StationUnavailable"
	end
	local station = uniqueChild(base, definition.modelName)
	if not station or not station:IsA("Model") then
		return "StationUnavailable"
	end
	local anchor: Instance? = station
	for _, name in definition.interactionAnchorPath do
		anchor = if anchor then uniqueChild(anchor, name) else nil
	end
	if
		not anchor
		or not anchor:IsA("Attachment")
		or not anchor.Parent
		or not anchor.Parent:IsA("BasePart")
	then
		return "StationUnavailable"
	end
	if not character or not character:IsDescendantOf(workspace) then
		return "CharacterUnavailable"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = uniqueChild(character, "HumanoidRootPart")
	if
		not humanoid
		or not (humanoid.Health > 0 and humanoid.Health < math.huge)
		or humanoid:GetState() == Enum.HumanoidStateType.Dead
		or not root
		or not root:IsA("BasePart")
	then
		return "CharacterUnavailable"
	end
	local distance = (root.Position - anchor.WorldPosition).Magnitude
	-- Positive bounds reject nonfinite positions instead of accidentally accepting NaN.
	if not (distance >= 0 and distance <= distanceLimit) then
		return "OutOfRange"
	end
	return nil
end

return table.freeze(CraftingAccess)
