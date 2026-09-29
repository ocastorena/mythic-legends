--!strict
-- ServerScriptService/Shared/EquipmentCatalogUtil
-- Validates launch Equipment, recipes, and effect references without activating their runtime.

type Record = { [string]: unknown }
type ElementSpec = { element: string, effectId: string, kind: string }

local EquipmentCatalogUtil = {}
local MAX_SAFE_INTEGER = 9007199254740991
local ELEMENTS: { [string]: ElementSpec } = {
	fire = { element = "Fire", effectId = "fire_burn", kind = "Burn" },
	water = { element = "Water", effectId = "water_slow", kind = "Slow" },
	earth = { element = "Earth", effectId = "earth_root", kind = "Root" },
	air = { element = "Air", effectId = "air_knockback", kind = "Push" },
	light = { element = "Light", effectId = "light_weaken", kind = "Weaken" },
	dark = { element = "Dark", effectId = "dark_refund", kind = "Refund" },
}
local FINISH_FIELDS = {
	displayName = true,
	description = true,
	rarity = true,
	element = true,
	thumbnail = true,
	effectId = true,
}
local RECIPE_FIELDS = {
	craftingStationId = true,
	goldCost = true,
	materials = true,
	resultDefinitionId = true,
	resultFinishId = true,
	quantity = true,
	durationSeconds = true,
}
local EFFECT_FIELDS: { [string]: { string } } = {
	Burn = { "staminaPerSecond", "durationSeconds" },
	Slow = { "walkSpeedMultiplier", "durationSeconds" },
	Root = { "rootSeconds", "landingTimeoutSeconds", "recoverySeconds" },
	Push = { "horizontalMultiplier" },
	Weaken = { "horizontalMultiplier", "durationSeconds" },
	Refund = { "stamina" },
}
local SWORD_POSITIVE = {
	"staminaCost",
	"cooldownSeconds",
	"swingDurationSeconds",
	"contactWindowSeconds",
	"reachStuds",
	"planarKnockback",
	"verticalKnockback",
	"launchControlSeconds",
	"maximumReactionSeconds",
}
local SWORD_NONNEGATIVE = {
	"hitStartFallbackSeconds",
	"hitStopSeconds",
	"serverToleranceStuds",
	"tumbleAngularSpeed",
	"landingRecoverySeconds",
	"airTrailSeconds",
}
local SHIELD_POSITIVE = {
	"impactStaminaCost",
	"minimumGuardStamina",
	"raiseSeconds",
	"raiseTimeoutSeconds",
	"lowerSeconds",
	"lowerTimeoutSeconds",
	"blockArcDegrees",
	"slideKnockback",
	"slideDurationSeconds",
}
local PROFILE_METADATA = {
	"displayName",
	"description",
	"rarity",
	"kind",
	"modelName",
	"thumbnail",
	"equipmentType",
	"handsRequired",
	"stage",
	"animationId",
	"impactSoundId",
	"raiseAnimationId",
	"holdAnimationId",
	"lowerAnimationId",
}

local function record(value: unknown): Record?
	return if type(value) == "table" and getmetatable(value) == nil then value :: Record else nil
end

local function isId(value: unknown): boolean
	return type(value) == "string"
		and #value <= 128
		and string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
		and string.find(value, "__", 1, true) == nil
		and string.sub(value, -1) ~= "_"
end

local function text(value: unknown): boolean
	return type(value) == "string" and #value > 0
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function positive(value: unknown): boolean
	return finite(value) and (value :: number) > 0
end

local function whole(value: unknown): boolean
	return positive(value) and (value :: number) <= MAX_SAFE_INTEGER and (value :: number) % 1 == 0
end

local function closed(value: Record, fields: { [string]: boolean }): boolean
	for key in value do
		if type(key) ~= "string" or not fields[key] then
			return false
		end
	end
	return true
end

local function fieldsMatch(left: Record, right: Record, fields: { string }): boolean
	for _, field in fields do
		if left[field] ~= right[field] then
			return false
		end
	end
	return true
end

local function gameplay(definition: Record, isSword: boolean, maximum: number): boolean
	for _, field in if isSword then SHIELD_POSITIVE else SWORD_POSITIVE do
		if definition[field] ~= nil then
			return false
		end
	end
	for _, field in if isSword then SWORD_POSITIVE else SHIELD_POSITIVE do
		if not positive(definition[field]) then
			return false
		end
	end
	if isSword then
		for _, field in SWORD_NONNEGATIVE do
			if not finite(definition[field]) or (definition[field] :: number) < 0 then
				return false
			end
		end
		return type(definition.requireLineOfSight) == "boolean"
			and (definition.staminaCost :: number) <= maximum
			and (definition.hitStartFallbackSeconds :: number) + (definition.contactWindowSeconds :: number) <= (definition.swingDurationSeconds :: number)
			and (definition.launchControlSeconds :: number) <= (definition.maximumReactionSeconds :: number)
			and definition.landingRecoverySeconds :: number
				<= (definition.maximumReactionSeconds :: number)
	end
	for _, field in SWORD_NONNEGATIVE do
		if definition[field] ~= nil then
			return false
		end
	end
	if definition.requireLineOfSight ~= nil then
		return false
	end
	return (definition.impactStaminaCost :: number) <= (definition.minimumGuardStamina :: number)
		and (definition.minimumGuardStamina :: number) <= maximum
		and (definition.raiseSeconds :: number) <= (definition.raiseTimeoutSeconds :: number)
		and (definition.lowerSeconds :: number) <= (definition.lowerTimeoutSeconds :: number)
		and (definition.blockArcDegrees :: number) <= 360
end

local function validateEffects(effects: Record, sword: Record, combat: Record): string?
	local found: { [string]: boolean } = {}
	for _, spec in ELEMENTS do
		local effect = record(effects[spec.effectId])
		if
			not effect
			or effect.element ~= spec.element
			or effect.kind ~= spec.kind
			or not text(effect.description)
		then
			return `InvalidEffect:{spec.effectId}`
		end
		local fields = EFFECT_FIELDS[spec.kind]
		for key in effect do
			if
				key ~= "element"
				and key ~= "kind"
				and key ~= "description"
				and not table.find(fields, key)
			then
				return `InvalidEffect:{spec.effectId}`
			end
		end
		for _, field in fields do
			if not positive(effect[field]) then
				return `InvalidEffect:{spec.effectId}`
			end
		end
		if
			(spec.kind == "Slow" and (effect.walkSpeedMultiplier :: number) >= 1)
			or (spec.kind == "Weaken" and (effect.horizontalMultiplier :: number) >= 1)
			or (spec.kind == "Push" and (effect.horizontalMultiplier :: number) <= 1)
		then
			return `InvalidEffect:{spec.effectId}`
		end
		found[spec.effectId] = true
	end
	for id in effects do
		if not isId(id) or not found[id] then
			return "InvalidEffectCatalog"
		end
	end
	local refund = record(effects.dark_refund) :: Record
	local interval = math.max(sword.cooldownSeconds :: number, sword.swingDurationSeconds :: number)
	local recovered = (combat.staminaRegenPerSecond :: number) * interval
	local totalReturn = recovered + (refund.stamina :: number)
	if not finite(totalReturn) or totalReturn >= (sword.staminaCost :: number) then
		return "SustainableDarkRefund"
	end
	return nil
end

local function validateFinishes(definition: Record, id: string, isSword: boolean): string?
	local finishes = record(definition.finishes)
	if not finishes then
		return `InvalidEquipmentDefinition:{id}`
	end
	for finishId, spec in ELEMENTS do
		local finish = record(finishes[finishId])
		if
			not finish
			or not closed(finish, FINISH_FIELDS)
			or not text(finish.displayName)
			or not text(finish.description)
			or finish.rarity ~= "Rare"
			or finish.element ~= spec.element
			or (finish.thumbnail ~= nil and type(finish.thumbnail) ~= "string")
			or finish.effectId ~= (if isSword then spec.effectId else nil)
		then
			return `InvalidFinish:{id}:{finishId}`
		end
	end
	for finishId in finishes do
		if not isId(finishId) or not ELEMENTS[finishId] then
			return `InvalidFinishCatalog:{id}`
		end
	end
	return nil
end

local function safeProduct(left: number, right: number): number?
	if left > math.floor(MAX_SAFE_INTEGER / right) then
		return nil
	end
	local result = left * right
	return if whole(result) then result else nil
end

local function validateRecipes(
	recipes: Record,
	definitions: Record,
	materials: Record,
	stations: Record
): string?
	local station = record(stations.basic_crafting_station)
	if not station or not text(station.displayName) or type(station.modelName) ~= "string" then
		return "InvalidCraftingStation"
	end
	local covered: { [string]: boolean } = {}
	for id, rawRecipe in recipes do
		if not isId(id) then
			return "InvalidRecipeId"
		end
		local recipe = record(rawRecipe)
		if
			not recipe
			or not closed(recipe, RECIPE_FIELDS)
			or not whole(recipe.goldCost)
			or not whole(recipe.quantity)
			or not positive(recipe.durationSeconds)
			or (recipe.resultDefinitionId ~= "elemental_sword" and recipe.resultDefinitionId ~= "elemental_shield")
			or not isId(recipe.resultFinishId)
			or not ELEMENTS[recipe.resultFinishId :: string]
			or recipe.craftingStationId ~= "basic_crafting_station"
		then
			return `InvalidRecipe:{id}`
		end
		local definitionId = recipe.resultDefinitionId :: string
		local finishId = recipe.resultFinishId :: string
		local resultId = `{definitionId}:{finishId}`
		if covered[resultId] then
			return `DuplicateRecipeResult:{resultId}`
		end
		local inputs = record(recipe.materials)
		if not inputs then
			return `InvalidRecipe:{id}`
		end
		local count, purchasedCost = 0, recipe.goldCost :: number
		for materialId, quantity in inputs do
			local material = if isId(materialId) then record(materials[materialId]) else nil
			if
				not material
				or not whole(quantity)
				or material.launchEnabled ~= true
				or material.category ~= "material"
				or material.element ~= ELEMENTS[finishId].element
				or not whole(material.stackLimit)
				or not whole(material.buyGold)
				or not whole(material.sellGold)
				or (material.buyGold :: number) <= (material.sellGold :: number)
			then
				return `InvalidRecipe:{id}`
			end
			count += 1
			local inputCost = safeProduct(quantity :: number, material.buyGold :: number)
			if not inputCost or inputCost > MAX_SAFE_INTEGER - purchasedCost then
				return `InvalidResalePrice:{id}`
			end
			purchasedCost += inputCost
		end
		local definition = record(definitions[definitionId]) :: Record
		local sale = record(definition.sale) :: Record
		local resale = safeProduct(recipe.quantity :: number, sale.gold :: number)
		if count ~= 1 then
			return `InvalidRecipe:{id}`
		elseif not resale or resale >= purchasedCost then
			return `InvalidResalePrice:{id}`
		end
		covered[resultId] = true
	end
	for _, definitionId in { "elemental_sword", "elemental_shield" } do
		for finishId in ELEMENTS do
			if not covered[`{definitionId}:{finishId}`] then
				return `MissingRecipe:{definitionId}:{finishId}`
			end
		end
	end
	return nil
end

function EquipmentCatalogUtil.ValidateLaunch(
	rawEquipment: unknown,
	rawRecipes: unknown,
	rawEffects: unknown,
	rawMaterials: unknown,
	rawStations: unknown
): (boolean, string?)
	local equipment, recipes, effects = record(rawEquipment), record(rawRecipes), record(rawEffects)
	local materials, stations = record(rawMaterials), record(rawStations)
	if not equipment or not recipes or not effects or not materials or not stations then
		return false, "InvalidCatalog"
	end
	local definitions, profiles, combat =
		record(equipment.definitions), record(equipment.profiles), record(equipment.combat)
	if
		not definitions
		or not profiles
		or not combat
		or not positive(combat.staminaMaximum)
		or not finite(combat.staminaSpawn)
		or (combat.staminaSpawn :: number) < 0
		or (combat.staminaSpawn :: number) > (combat.staminaMaximum :: number)
		or not finite(combat.staminaRegenPerSecond)
		or (combat.staminaRegenPerSecond :: number) < 0
		or not positive(combat.knockbackImmunitySeconds)
		or not positive(combat.arenaHeightAllowanceStuds)
	then
		return false, "InvalidCatalog"
	end
	local known: { [string]: boolean } = {}
	for _, id in { "wooden_sword", "wooden_shield", "elemental_sword", "elemental_shield" } do
		local definition = record(definitions[id])
		local isSword = id == "wooden_sword" or id == "elemental_sword"
		local isCrafted = id == "elemental_sword" or id == "elemental_shield"
		if
			not definition
			or not text(definition.displayName)
			or not text(definition.description)
			or type(definition.modelName) ~= "string"
			or type(definition.thumbnail) ~= "string"
			or definition.kind ~= (if isSword then "PrimaryWeapon" else "Shield")
			or definition.equipmentType ~= (if isSword then "Sword" else "Shield")
			or definition.handsRequired ~= (if isSword then 1 else nil)
			or definition.stage ~= (if isCrafted then 1 else nil)
			or definition.rarity ~= (if isCrafted then "Rare" else "Common")
			or definition.effectId ~= nil
			or definition.element ~= nil
		then
			return false, `InvalidEquipmentDefinition:{id}`
		end
		if not gameplay(definition, isSword, combat.staminaMaximum :: number) then
			return false, `InvalidGameplay:{id}`
		end
		if isCrafted then
			local sale = record(definition.sale)
			if not sale or not whole(sale.gold) then
				return false, `InvalidEquipmentDefinition:{id}`
			end
			local problem = validateFinishes(definition, id, isSword)
			if problem then
				return false, problem
			end
		else
			local profile = record(profiles[id])
			if
				definition.finishes ~= nil
				or definition.sale ~= nil
				or not profile
				or profile.finishes ~= nil
				or profile.sale ~= nil
				or profile.effectId ~= nil
				or profile.element ~= nil
				or not gameplay(profile, isSword, combat.staminaMaximum :: number)
				or not fieldsMatch(profile, definition, PROFILE_METADATA)
				or not fieldsMatch(
					profile,
					definition,
					if isSword then SWORD_POSITIVE else SHIELD_POSITIVE
				)
				or (
					isSword
					and (
						not fieldsMatch(profile, definition, SWORD_NONNEGATIVE)
						or profile.requireLineOfSight ~= definition.requireLineOfSight
					)
				)
			then
				return false, `InvalidEquipmentDefinition:{id}`
			end
		end
		known[id] = true
	end
	for id in definitions do
		if not isId(id) or not known[id] then
			return false, "InvalidEquipmentCatalog"
		end
	end
	for id in profiles do
		if id ~= "wooden_sword" and id ~= "wooden_shield" then
			return false, "InvalidProfileCatalog"
		end
	end
	local sword = record(definitions.elemental_sword) :: Record
	local wooden = record(definitions.wooden_sword) :: Record
	if
		not fieldsMatch(sword, wooden, SWORD_POSITIVE)
		or not fieldsMatch(sword, wooden, SWORD_NONNEGATIVE)
		or sword.requireLineOfSight ~= wooden.requireLineOfSight
	then
		return false, "MismatchedSwordGameplay"
	end
	local problem = validateEffects(effects, sword, combat)
		or validateRecipes(recipes, definitions, materials, stations)
	return problem == nil, problem
end

return table.freeze(EquipmentCatalogUtil)
