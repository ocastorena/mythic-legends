--!strict
-- ServerScriptService/Services/BaseService/WorldAccessUtil
-- Shared Base-feature world checks; only server-owned slots and explicit anchors grant access.

local BaseRuntime = require(script.Parent.BaseRuntime)

local WorldAccessUtil = {}

function WorldAccessUtil.FindUniqueChild(parent: Instance, name: string): Instance?
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

function WorldAccessUtil.GetOwnedBase(
	userId: number,
	slots: BaseRuntime.Slots,
	basesFolder: Folder
): Model?
	local base: Model? = nil
	for _, slot in slots do
		if slot.userId == userId then
			if base then
				return nil
			end
			base = slot.base
		end
	end
	if not base or base.Parent ~= basesFolder or not basesFolder:IsDescendantOf(workspace) then
		return nil
	end
	return base
end

function WorldAccessUtil.ResolveAnchor(root: Instance, path: { string }): Instance?
	local anchor: Instance? = root
	for _, name in path do
		anchor = if anchor then WorldAccessUtil.FindUniqueChild(anchor, name) else nil
	end
	return anchor
end

function WorldAccessUtil.CheckNearAnchor(
	character: Model?,
	anchor: Instance?,
	distanceLimit: number,
	unavailableCode: string
): string?
	if
		not (distanceLimit > 0 and distanceLimit < math.huge)
		or not anchor
		or not anchor:IsA("Attachment")
		or not anchor.Parent
		or not anchor.Parent:IsA("BasePart")
	then
		return unavailableCode
	end
	if not character or not character:IsDescendantOf(workspace) then
		return "CharacterUnavailable"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = WorldAccessUtil.FindUniqueChild(character, "HumanoidRootPart")
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

return table.freeze(WorldAccessUtil)
