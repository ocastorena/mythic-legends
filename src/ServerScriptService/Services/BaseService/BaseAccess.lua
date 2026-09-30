--!strict
-- ServerScriptService/Services/BaseService/BaseAccess
-- A Base management action belongs to the caller's live Base and its explicit authored anchor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local BaseState = require(ServerScriptService.Shared.BaseState)
local BaseRuntime = require(script.Parent.BaseRuntime)
local WorldAccessUtil = require(script.Parent.WorldAccessUtil)

local BaseAccess = {}

function BaseAccess.Check(
	userId: number,
	character: Model?,
	baseRecord: Types.BaseRecord,
	slots: BaseRuntime.Slots,
	basesFolder: Folder
): string?
	if
		type(baseRecord) ~= "table"
		or getmetatable(baseRecord) ~= nil
		or not BaseState.GetStatus(baseRecord)
	then
		return "InvalidBaseState"
	end
	local base = WorldAccessUtil.GetOwnedBase(userId, slots, basesFolder)
	if not base then
		return "BaseUnavailable"
	end
	local anchor = WorldAccessUtil.ResolveAnchor(base, Bases.interactionAnchorPath)
	return WorldAccessUtil.CheckNearAnchor(
		character,
		anchor,
		Bases.interactionDistanceStuds,
		"BaseUnavailable"
	)
end

return table.freeze(BaseAccess)
