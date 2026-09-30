--!strict
-- ServerScriptService/Services/BaseService/ShrineAccess
-- Saved Shrine identity selects a permanent, anchored slot on the caller's server-owned Base.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ShrineInteractions = require(ReplicatedStorage.Shared.Configurations.ShrineInteractions)
local BaseState = require(ServerScriptService.Shared.BaseState)
local BaseRuntime = require(script.Parent.BaseRuntime)
local WorldAccessUtil = require(script.Parent.WorldAccessUtil)

local ShrineAccess = {}

function ShrineAccess.Check(
	userId: number,
	character: Model?,
	baseRecord: Types.BaseRecord,
	slots: BaseRuntime.Slots,
	basesFolder: Folder,
	shrineInstanceId: string
): string?
	if type(shrineInstanceId) ~= "string" or #shrineInstanceId == 0 or #shrineInstanceId > 128 then
		return "InvalidRequest"
	end
	if
		type(baseRecord) ~= "table"
		or getmetatable(baseRecord) ~= nil
		or not BaseState.GetStatus(baseRecord)
	then
		return "InvalidBaseState"
	end
	local shrines = baseRecord.shrines
	local shrine = if shrines then shrines[shrineInstanceId] else nil
	if not shrine then
		return "ShrineNotOwned"
	end
	local base = WorldAccessUtil.GetOwnedBase(userId, slots, basesFolder)
	if not base then
		return "ShrineUnavailable"
	end
	local shrineSlots = WorldAccessUtil.FindUniqueChild(base, ShrineInteractions.slotsFolderName)
	if not shrineSlots or not shrineSlots:IsA("Folder") then
		return "ShrineUnavailable"
	end
	local slot = WorldAccessUtil.FindUniqueChild(
		shrineSlots,
		ShrineInteractions.slotNamePrefix .. tostring(shrine.buildSlotId)
	)
	if not slot or not slot:IsA("BasePart") or not slot.Anchored then
		return "ShrineUnavailable"
	end
	local anchor = WorldAccessUtil.FindUniqueChild(slot, ShrineInteractions.promptAttachmentName)
	return WorldAccessUtil.CheckNearAnchor(
		character,
		anchor,
		ShrineInteractions.interactionDistanceStuds,
		"ShrineUnavailable"
	)
end

return table.freeze(ShrineAccess)
