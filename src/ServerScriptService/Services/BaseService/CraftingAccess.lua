--!strict
-- ServerScriptService/Services/BaseService/CraftingAccess
-- Resolve proximity from server-owned Base slots and an explicit authored Station anchor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)
local BaseState = require(ServerScriptService.Shared.BaseState)
local BaseRuntime = require(script.Parent.BaseRuntime)
local WorldAccessUtil = require(script.Parent.WorldAccessUtil)

local CraftingAccess = {}

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
	local base = WorldAccessUtil.GetOwnedBase(userId, slots, basesFolder)
	if not base then
		return "StationUnavailable"
	end
	local station = WorldAccessUtil.FindUniqueChild(base, definition.modelName)
	if not station or not station:IsA("Model") then
		return "StationUnavailable"
	end
	local anchor = WorldAccessUtil.ResolveAnchor(station, definition.interactionAnchorPath)
	return WorldAccessUtil.CheckNearAnchor(character, anchor, distanceLimit, "StationUnavailable")
end

return table.freeze(CraftingAccess)
