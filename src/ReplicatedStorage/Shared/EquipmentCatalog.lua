--!strict
-- ReplicatedStorage/Shared/EquipmentCatalog
-- Resolve named Equipment from stable definition/finish IDs without copied owned metadata.

local Equipment = require(script.Parent.Configurations.Equipment)
local Types = require(script.Parent.Types)

local EquipmentCatalog = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

function EquipmentCatalog.Resolve(
	definitionId: unknown,
	finishId: unknown?
): Types.ResolvedEquipment?
	if not isId(definitionId) or (finishId ~= nil and not isId(finishId)) then
		return nil
	end
	local id = definitionId :: string
	local definition = Equipment.definitions[id]
	if not definition then
		return nil
	end
	local finish: Types.EquipmentFinishDef? = nil
	local finishes = definition.finishes
	if finishes then
		if finishId == nil then
			return nil
		end
		finish = finishes[finishId :: string]
		if not finish then
			return nil
		end
	elseif finishId ~= nil then
		return nil
	end
	local resolved: Types.ResolvedEquipment = {
		definitionId = id,
		finishId = finishId :: string?,
		displayName = if finish then finish.displayName else definition.displayName,
		description = if finish then finish.description else definition.description,
		rarity = if finish then finish.rarity else definition.rarity,
		element = if finish then finish.element else nil,
		thumbnail = if finish and finish.thumbnail ~= nil
			then finish.thumbnail
			else definition.thumbnail,
		profile = definition,
		effectId = if finish then finish.effectId else nil,
		sellGold = if definition.sale then definition.sale.gold else nil,
	}
	-- The referenced definition is recursively frozen by its configuration owner. Empty
	-- crafted model names remain explicitly unbound; resolving never chooses a fallback asset.
	table.freeze(resolved)
	return resolved :: Types.ResolvedEquipment?
end

return table.freeze(EquipmentCatalog)
