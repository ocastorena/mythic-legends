--!strict
-- ServerScriptService/Shared/MythlingCatalogUtil
-- Validates the six-chain launch catalogue, not generic evolution rules or asset readiness.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local MythlingCatalogUtil = {}
local ELEMENTS: { [string]: boolean } = {
	Fire = true,
	Water = true,
	Earth = true,
	Air = true,
	Light = true,
	Dark = true,
}
local LAUNCH_RARITIES = { "Common", "Rare", "Epic" }
table.freeze(ELEMENTS)
table.freeze(LAUNCH_RARITIES)

local function record(value: unknown): { [unknown]: unknown }?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	return value :: { [unknown]: unknown }
end

local function isFormId(value: unknown): boolean
	if type(value) ~= "string" or #value > 128 then
		return false
	end
	-- Only syntax is inspected. The ordinal conveys no element, rarity, stage, or relationship.
	local ordinal = string.match(value, "^mythling_(%d+)$")
	return ordinal ~= nil
		and #ordinal >= 4
		and string.find(ordinal, "[1-9]") ~= nil
		and (#ordinal == 4 or string.sub(ordinal, 1, 1) ~= "0")
end

local function isPositive(value: unknown): boolean
	return type(value) == "number" and value == value and value > 0 and value < 2 ^ 53
end

local function isPositiveWhole(value: unknown): boolean
	return isPositive(value) and (value :: number) % 1 == 0
end

-- Tuning stays in definitions. This launch-only boundary enforces coverage and relationships,
-- without turning the current rarity/stage mapping into a rule of the shared gameplay reducers.
function MythlingCatalogUtil.ValidateLaunch(
	rawForms: unknown,
	levelCap: unknown
): (boolean, string?)
	local forms = record(rawForms)
	if not forms or not isPositiveWhole(levelCap) then
		return false, "InvalidCatalog"
	end

	local byElement: { [string]: { [number]: string } } = {}
	local prices: { [number]: number } = {}
	for id, rawDefinition in forms do
		if not isFormId(id) then
			return false, "InvalidFormId"
		end
		local formId = id :: string
		local definition = record(rawDefinition)
		if not definition then
			return false, `InvalidFormDefinition:{formId}`
		end
		local element = definition.element
		local stage = definition.evolutionStage
		if type(element) ~= "string" or not ELEMENTS[element] then
			return false, `InvalidFormElement:{formId}`
		end
		if not isPositiveWhole(stage) or (stage :: number) > #LAUNCH_RARITIES then
			return false, `InvalidFormStage:{formId}`
		end
		local stageNumber = stage :: number
		if definition.rarity ~= LAUNCH_RARITIES[stageNumber] then
			return false, `InvalidLaunchRarity:{formId}`
		end
		local chain = byElement[element] or {}
		if chain[stageNumber] then
			return false, `DuplicateChainStage:{formId}`
		end
		chain[stageNumber] = formId
		byElement[element] = chain
		if not isPositive(definition.baseYieldPerHour) then
			return false, `InvalidFormYield:{formId}`
		end
		local sale = record(definition.sale)
		if not sale or not isPositiveWhole(sale.gold) then
			return false, `InvalidFormSale:{formId}`
		end
		local gold = sale.gold :: number
		if prices[stageNumber] and prices[stageNumber] ~= gold then
			return false, `UnequalLaunchPrices:{formId}`
		end
		prices[stageNumber] = gold
		local rate = definition.captureProgressPerSecond
		if not isPositive(rate) or definition.captureDecayPerSecond ~= rate then
			return false, `InvalidCaptureRates:{formId}`
		end
		if stageNumber == #LAUNCH_RARITIES then
			if definition.evolution ~= nil then
				return false, `NonterminalFinalForm:{formId}`
			end
		else
			local evolution = record(definition.evolution)
			if
				not evolution
				or not isFormId(evolution.targetFormId)
				or not isPositiveWhole(evolution.requiredLevel)
				or (evolution.requiredLevel :: number) > (levelCap :: number)
			then
				return false, `InvalidEvolution:{formId}`
			end
		end
	end

	-- Every record's fields were validated above; relationship checks can use their typed shape.
	local definitions = forms :: { [string]: Types.MythlingFormDef }
	for element in ELEMENTS do
		local chain = byElement[element]
		if not chain or not chain[1] or not chain[2] or not chain[3] then
			return false, `IncompleteLaunchChain:{element}`
		end
		local previousRequiredLevel = 0
		for stage = 1, 2 do
			local formId = chain[stage]
			local definition = definitions[formId]
			local evolution = definition.evolution
			local target = definitions[chain[stage + 1]]
			if not evolution or evolution.targetFormId ~= chain[stage + 1] then
				return false, `InvalidChainTarget:{formId}`
			end
			if evolution.requiredLevel <= previousRequiredLevel then
				return false, `InvalidEvolutionOrder:{formId}`
			end
			previousRequiredLevel = evolution.requiredLevel
			if target.baseYieldPerHour <= definition.baseYieldPerHour then
				return false, `NonIncreasingYield:{formId}`
			end
		end
	end
	if prices[1] >= prices[2] or prices[2] >= prices[3] then
		return false, "NonIncreasingLaunchPrices"
	end
	return true, nil
end

return table.freeze(MythlingCatalogUtil)
