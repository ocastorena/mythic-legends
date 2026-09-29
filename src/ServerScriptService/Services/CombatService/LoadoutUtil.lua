--!strict
-- ServerScriptService/Services/CombatService/LoadoutUtil
-- Read-only owned selections and exact model identity; never chooses or repairs saved slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local LoadoutRequests = require(script.Parent.LoadoutRequests)

export type Slot = "PrimaryWeapon" | "Shield"
export type Selection = { instanceId: string, item: Types.ResolvedEquipment }
export type Resolver = (unknown, unknown?) -> Types.ResolvedEquipment?

local LoadoutUtil = {}

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function validId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function selected(data: Types.PlayerDoc, slot: Slot, resolve: Resolver): Selection?
	if not plain(data.equipment) or not plain(data.combatLoadout) then
		return nil
	end
	local id = if slot == "PrimaryWeapon"
		then data.combatLoadout.primaryWeaponInstanceId
		else data.combatLoadout.shieldInstanceId
	if not validId(id) then
		return nil
	end
	local entry = data.equipment[id :: string]
	if not plain(entry) then
		return nil
	end
	local item = resolve(entry.definitionId, entry.finishId)
	if not item or item.profile.kind ~= slot then
		return nil
	end
	return { instanceId = id :: string, item = item }
end

function LoadoutUtil.Resolve(data: Types.PlayerDoc, slot: Slot, resolver: Resolver?): Selection?
	local resolve = resolver or EquipmentCatalog.Resolve
	local result = selected(data, slot, resolve)
	if result and slot == "Shield" and data.combatLoadout.primaryWeaponInstanceId ~= nil then
		local primary = selected(data, "PrimaryWeapon", resolve)
		if not primary or primary.item.profile.handsRequired ~= 1 then
			return nil
		end
	end
	return result
end

function LoadoutUtil.Same(left: Selection, right: Selection): boolean
	return left.instanceId == right.instanceId
		and left.item.definitionId == right.item.definitionId
		and left.item.finishId == right.item.finishId
end

function LoadoutUtil.WriteAttributes(character: Model, data: Types.PlayerDoc)
	for _, slot in { "PrimaryWeapon", "Shield" } do
		local selection = LoadoutUtil.Resolve(data, slot :: Slot)
		local hand = if slot == "PrimaryWeapon" then "Right" else "Left"
		character:SetAttribute(
			`{hand}Equipped`,
			if selection then selection.item.definitionId else ""
		)
		character:SetAttribute(
			`{hand}EquipmentInstanceId`,
			if selection then selection.instanceId else ""
		)
		character:SetAttribute(
			`{hand}EquipmentFinishId`,
			if selection then selection.item.finishId or "" else ""
		)
	end
end

function LoadoutUtil.GetMounted(data: Types.PlayerDoc, character: Model, slot: Slot): Selection?
	local selection = LoadoutUtil.Resolve(data, slot)
	if not selection then
		return nil
	end
	local hand = if slot == "PrimaryWeapon" then "Right" else "Left"
	local finish = selection.item.finishId or ""
	if
		character:GetAttribute(`{hand}Equipped`) ~= selection.item.definitionId
		or character:GetAttribute(`{hand}EquipmentInstanceId`) ~= selection.instanceId
		or character:GetAttribute(`{hand}EquipmentFinishId`) ~= finish
	then
		return nil
	end
	local folder = character:FindFirstChild("EquippedEquipment")
	local model = folder and folder:FindFirstChild(`{hand}Equipment`)
	local limb = character:FindFirstChild(`{hand}Hand`)
	local motor = limb and limb:FindFirstChild(`{hand}HandMotor`)
	if
		not model
		or not model:IsA("Model")
		or not model.PrimaryPart
		or model:GetAttribute("EquipmentId") ~= selection.item.definitionId
		or model:GetAttribute("EquipmentInstanceId") ~= selection.instanceId
		or model:GetAttribute("EquipmentFinishId") ~= finish
		or not limb
		or not limb:IsA("BasePart")
		or not motor
		or not motor:IsA("Motor6D")
		or motor.Part0 ~= limb
		or motor.Part1 ~= model.PrimaryPart
	then
		return nil
	end
	return selection
end

function LoadoutUtil.Snapshot(data: Types.PlayerDoc): LoadoutRequests.Snapshot
	local entries: { { instanceId: string, definitionId: string, finishId: string? } } = {}
	if plain(data.equipment) then
		for instanceId, entry in data.equipment do
			if validId(instanceId) and plain(entry) then
				local item = EquipmentCatalog.Resolve(entry.definitionId, entry.finishId)
				if item then
					table.insert(entries, {
						instanceId = instanceId,
						definitionId = item.definitionId,
						finishId = item.finishId,
					})
				end
			end
		end
	end
	table.sort(
		entries,
		function(left: { instanceId: string }, right: { instanceId: string }): boolean
			return left.instanceId < right.instanceId
		end
	)
	local loadout = data.combatLoadout
	return {
		equipment = entries,
		-- Preserve bounded dangling references for explicit removal, never substitute another item.
		primaryWeaponInstanceId = if plain(loadout)
				and validId(loadout.primaryWeaponInstanceId)
			then loadout.primaryWeaponInstanceId
			else nil,
		shieldInstanceId = if plain(loadout) and validId(loadout.shieldInstanceId)
			then loadout.shieldInstanceId
			else nil,
	}
end

return table.freeze(LoadoutUtil)
