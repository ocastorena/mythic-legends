--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/EquipmentSelection
-- Read-only mounted-item prediction. The server still owns ownership and action authorization.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)

export type Hand = "Right" | "Left"
export type Resolver = (unknown, unknown?) -> Types.ResolvedEquipment?
export type Selection = {
	character: Model,
	hand: Hand,
	instanceId: string,
	item: Types.ResolvedEquipment,
	model: Model,
	hitbox: BasePart,
	motor: Motor6D,
	limb: BasePart,
	primaryPart: BasePart,
}

local EquipmentSelection = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

function EquipmentSelection.Resolve(character: Model, hand: Hand, resolver: Resolver?): Selection?
	if hand ~= "Right" and hand ~= "Left" then
		return nil
	end
	local definitionId = character:GetAttribute(`{hand}Equipped`)
	local instanceId = character:GetAttribute(`{hand}EquipmentInstanceId`)
	local finish = character:GetAttribute(`{hand}EquipmentFinishId`)
	if
		not isId(definitionId)
		or not isId(instanceId)
		or type(finish) ~= "string"
		or (finish ~= "" and not isId(finish))
	then
		return nil
	end
	local finishId = if finish == "" then nil else finish
	local resolve = resolver or EquipmentCatalog.Resolve
	local item = resolve(definitionId, finishId)
	local kind = if hand == "Right" then "PrimaryWeapon" else "Shield"
	if
		not item
		or item.definitionId ~= definitionId
		or item.finishId ~= finishId
		or item.profile.kind ~= kind
		or type(item.profile.modelName) ~= "string"
		or item.profile.modelName == ""
	then
		return nil
	end
	local folder = character:FindFirstChild("EquippedEquipment")
	local model = folder and folder:FindFirstChild(`{hand}Equipment`)
	if
		not folder
		or not folder:IsA("Folder")
		or not model
		or not model:IsA("Model")
		or model:GetAttribute("EquipmentId") ~= definitionId
		or model:GetAttribute("EquipmentInstanceId") ~= instanceId
		or model:GetAttribute("EquipmentFinishId") ~= finish
		or model:GetAttribute("EquipmentSlot") ~= hand
	then
		return nil
	end
	local primary = model.PrimaryPart
	local hitbox = model:FindFirstChild("Hitbox", true)
	local limb = character:FindFirstChild(`{hand}Hand`)
	local motor = limb and limb:FindFirstChild(`{hand}HandMotor`)
	if
		not primary
		or not primary:IsDescendantOf(model)
		or not hitbox
		or not hitbox:IsA("BasePart")
		or not limb
		or not limb:IsA("BasePart")
		or not motor
		or not motor:IsA("Motor6D")
		or motor.Part0 ~= limb
		or motor.Part1 ~= primary
	then
		return nil
	end
	return {
		character = character,
		hand = hand,
		instanceId = instanceId :: string,
		item = item,
		model = model,
		hitbox = hitbox,
		motor = motor,
		limb = limb,
		primaryPart = primary,
	}
end

function EquipmentSelection.Same(left: Selection, right: Selection): boolean
	return left.character == right.character
		and left.hand == right.hand
		and left.instanceId == right.instanceId
		and left.item.definitionId == right.item.definitionId
		and left.item.finishId == right.item.finishId
		and left.model == right.model
		and left.hitbox == right.hitbox
		and left.motor == right.motor
		and left.limb == right.limb
		and left.primaryPart == right.primaryPart
end

function EquipmentSelection.IsCurrent(
	character: Model,
	selection: Selection,
	resolver: Resolver?
): boolean
	if character ~= selection.character then
		return false
	end
	local current = EquipmentSelection.Resolve(character, selection.hand, resolver)
	return current ~= nil and EquipmentSelection.Same(current, selection)
end

return table.freeze(EquipmentSelection)
