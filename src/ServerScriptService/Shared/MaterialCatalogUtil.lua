--!strict
-- ServerScriptService/Shared/MaterialCatalogUtil
-- Validates the launch Material boundary and Shrine outputs without changing either catalogue.

local MaterialCatalogUtil = {}

local ELEMENTS: { [string]: boolean } = {
	Fire = true,
	Water = true,
	Earth = true,
	Air = true,
	Light = true,
	Dark = true,
}
table.freeze(ELEMENTS)

local function record(value: unknown): { [unknown]: unknown }?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	return value :: { [unknown]: unknown }
end

local function isId(value: unknown): boolean
	return type(value) == "string"
		and #value <= 128
		and string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
		and string.find(value, "__", 1, true) == nil
		and string.sub(value, -1) ~= "_"
end

local function isElement(value: unknown): boolean
	return type(value) == "string" and ELEMENTS[value] == true
end

local function isPositiveWhole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value > 0
		and value < 2 ^ 53
		and value % 1 == 0
end

-- The shared Inventory limit remains authoritative, including for retained/unknown Material IDs.
-- Optional launch fields on legacy metadata are deliberately ignored, not defaulted or promoted.
function MaterialCatalogUtil.Validate(
	rawMaterials: unknown,
	rawShrines: unknown,
	stackLimit: unknown
): (boolean, string?)
	local materials = record(rawMaterials)
	local shrines = record(rawShrines)
	if not materials or not shrines or not isPositiveWhole(stackLimit) then
		return false, "InvalidCatalog"
	end

	local materialByElement: { [string]: string } = {}
	for id, rawDefinition in materials do
		if not isId(id) then
			return false, "InvalidMaterialId"
		end
		local materialId = id :: string
		local definition = record(rawDefinition)
		if not definition or type(definition.launchEnabled) ~= "boolean" then
			return false, `InvalidMaterialDefinition:{materialId}`
		end
		if not definition.launchEnabled then
			continue
		end
		if definition.category ~= "material" or not isElement(definition.element) then
			return false, `InvalidLaunchMaterial:{materialId}`
		end
		local element = definition.element :: string
		if materialByElement[element] then
			return false, `DuplicateMaterialElement:{element}`
		end
		if not isPositiveWhole(definition.stackLimit) or definition.stackLimit ~= stackLimit then
			return false, `InvalidMaterialStackLimit:{materialId}`
		end
		if
			not isPositiveWhole(definition.buyGold)
			or not isPositiveWhole(definition.sellGold)
			or (definition.buyGold :: number) <= (definition.sellGold :: number)
		then
			return false, `InvalidMaterialPrices:{materialId}`
		end
		materialByElement[element] = materialId
	end
	for element in ELEMENTS do
		if not materialByElement[element] then
			return false, `MissingMaterialElement:{element}`
		end
	end

	local shrineByElement: { [string]: string } = {}
	for id, rawDefinition in shrines do
		if not isId(id) then
			return false, "InvalidShrineId"
		end
		local shrineId = id :: string
		local definition = record(rawDefinition)
		if not definition or not isElement(definition.element) then
			return false, `InvalidShrineElement:{shrineId}`
		end
		local element = definition.element :: string
		if shrineByElement[element] then
			return false, `DuplicateShrineElement:{element}`
		end
		if
			not isId(definition.materialId)
			or definition.materialId ~= materialByElement[element]
		then
			return false, `InvalidShrineOutput:{shrineId}`
		end
		shrineByElement[element] = shrineId
	end
	for element in ELEMENTS do
		if not shrineByElement[element] then
			return false, `MissingShrineElement:{element}`
		end
	end
	return true, nil
end

return table.freeze(MaterialCatalogUtil)
