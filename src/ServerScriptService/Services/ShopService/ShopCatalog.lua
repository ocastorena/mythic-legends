--!strict
-- ServerScriptService/Services/ShopService/ShopCatalog
-- Validated static offers and absolute shared periods; this module owns no personal stock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local Shop = require(ReplicatedStorage.Shared.Configurations.Shop)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local EquipmentRecipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)

export type Resolver = (unknown, unknown?) -> Types.ResolvedEquipment?
export type Options = {
	read config: unknown?,
	read materials: unknown?,
	read recipes: unknown?,
	read resolver: Resolver?,
}
export type ShopCatalog = {
	read Resolve: (number) -> (Types.ShopPeriod?, string?),
	read ValidateLaunch: () -> (boolean, string?),
}
type Record = { [string]: unknown }
type Rotation = { element: Types.Element, offers: { Types.ShopOffer } }
type Prepared = { epoch: number, interval: number, rotation: { Rotation } }

local ShopCatalog = {}
local MAX_SAFE_INTEGER = 9007199254740991
local ELEMENTS: { Types.Element } = { "Fire", "Water", "Earth", "Air", "Light", "Dark" }
local CONFIG_FIELDS =
	{ epochSeconds = true, refreshSeconds = true, materials = true, rotation = true }
local FEATURED_FIELDS =
	{ definitionId = true, finishId = true, recipeId = true, unitGold = true, stockLimit = true }
local RECIPE_FIELDS = {
	craftingStationId = true,
	goldCost = true,
	materials = true,
	resultDefinitionId = true,
	resultFinishId = true,
	quantity = true,
	durationSeconds = true,
}

local function record(value: unknown): Record?
	return if type(value) == "table" and getmetatable(value) == nil then value :: Record else nil
end

local function closed(value: Record, fields: { [string]: boolean }): boolean
	for key in value do
		if type(key) ~= "string" or not fields[key] then
			return false
		end
	end
	return true
end

local function array(value: unknown, length: number): { unknown }?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local count = 0
	for key in value :: { [unknown]: unknown } do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
			return nil
		end
		count += 1
	end
	return if count == length then value :: { unknown } else nil
end

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value % 1 == 0
end

local function positiveWhole(value: unknown): boolean
	return whole(value) and (value :: number) > 0
end

local function isId(value: unknown): boolean
	return type(value) == "string"
		and #value > 0
		and #value <= 128
		and string.match(value, "^[a-z][a-z0-9_]*$") ~= nil
end

local function product(left: number, right: number): number?
	if right <= 0 or left > math.floor(MAX_SAFE_INTEGER / right) then
		return nil
	end
	local result = left * right
	return if whole(result) then result else nil
end

local function encode(value: string): string
	return `{#value}:{value}`
end

local function makeOffer(
	key: string,
	kind: "Material" | "Equipment",
	firstId: string,
	finishId: string?,
	price: number,
	limit: number
): Types.ShopOffer?
	-- Length-prefix every string, and preserve all integer digits. No hashes or truncated quotes.
	local revision = table.concat({
		kind,
		encode(key),
		encode(firstId),
		if finishId then encode(finishId) else "-",
		string.format("%.0f", price),
		string.format("%.0f", limit),
	}, "|")
	if #revision > 128 then
		return nil
	end
	return {
		offerId = key,
		offerRevision = revision,
		stockKey = key,
		kind = kind,
		materialId = if kind == "Material" then firstId else nil,
		definitionId = if kind == "Equipment" then firstId else nil,
		finishId = finishId,
		unitGold = price,
		stockLimit = limit,
	}
end

local function featured(
	raw: unknown,
	role: string,
	element: Types.Element,
	materialId: string,
	material: Record,
	recipes: Record,
	Resolve: Resolver
): (Types.ShopOffer?, number?, string?)
	local offer = record(raw)
	if
		not offer
		or not closed(offer, FEATURED_FIELDS)
		or not isId(offer.definitionId)
		or not isId(offer.finishId)
		or not isId(offer.recipeId)
		or not positiveWhole(offer.unitGold)
		or offer.stockLimit ~= 1
	then
		return nil, nil, "InvalidFeaturedOffer"
	end
	local definitionId, finishId = offer.definitionId :: string, offer.finishId :: string
	local resolvedOk, resolved = pcall(Resolve, definitionId, finishId)
	local item = if resolvedOk then record(resolved) else nil
	local profile = if item then record(item.profile) else nil
	local isSword = role == "sword"
	if
		not item
		or not profile
		or item.definitionId ~= definitionId
		or item.finishId ~= finishId
		or item.element ~= element
		or item.rarity ~= "Rare"
		or profile.stage ~= 1
		or profile.equipmentType ~= (if isSword then "Sword" else "Shield")
		or profile.kind ~= (if isSword then "PrimaryWeapon" else "Shield")
		or profile.handsRequired ~= (if isSword then 1 else nil)
		or not positiveWhole(item.sellGold)
	then
		return nil, nil, "InvalidFeaturedEquipment"
	end
	local recipe = record(recipes[offer.recipeId :: string])
	if
		not recipe
		or not closed(recipe, RECIPE_FIELDS)
		or recipe.craftingStationId ~= "basic_crafting_station"
		or recipe.resultDefinitionId ~= definitionId
		or recipe.resultFinishId ~= finishId
		or not positiveWhole(recipe.goldCost)
		or recipe.quantity ~= 1
		or type(recipe.durationSeconds) ~= "number"
		or recipe.durationSeconds ~= recipe.durationSeconds
		or recipe.durationSeconds <= 0
		or recipe.durationSeconds >= math.huge
	then
		return nil, nil, "InvalidFeaturedRecipe"
	end
	local inputs = record(recipe.materials)
	if not inputs or not positiveWhole(inputs[materialId]) then
		return nil, nil, "InvalidFeaturedRecipe"
	end
	for id in inputs do
		if id ~= materialId then
			return nil, nil, "InvalidFeaturedRecipe"
		end
	end
	local quantity = recipe.quantity :: number
	local inputCost = product(inputs[materialId] :: number, material.buyGold :: number)
	local resale = product(item.sellGold :: number, quantity)
	local featuredPrice = product(offer.unitGold :: number, quantity)
	local recipeGold = recipe.goldCost :: number
	if
		not inputCost
		or inputCost > MAX_SAFE_INTEGER - recipeGold
		or not resale
		or not featuredPrice
	then
		return nil, nil, "InvalidShopEconomy"
	end
	local craftingCost = inputCost + recipeGold
	if
		resale >= craftingCost
		or featuredPrice <= craftingCost
		or (item.sellGold :: number) >= (offer.unitGold :: number)
	then
		return nil, nil, "InvalidShopEconomy"
	end
	local result = makeOffer(
		`featured_{role}`,
		"Equipment",
		definitionId,
		finishId,
		offer.unitGold :: number,
		1
	)
	return result, inputs[materialId] :: number, if result then nil else "OfferRevisionTooLong"
end

local function compile(options: Options?): (Prepared?, string?)
	local config = record(if options and options.config ~= nil then options.config else Shop)
	local materials =
		record(if options and options.materials ~= nil then options.materials else Materials)
	local recipes =
		record(if options and options.recipes ~= nil then options.recipes else EquipmentRecipes)
	local Resolve = if options and options.resolver
		then options.resolver
		else EquipmentCatalog.Resolve
	if
		not config
		or not materials
		or not recipes
		or not closed(config, CONFIG_FIELDS)
		or not whole(config.epochSeconds)
		or not positiveWhole(config.refreshSeconds)
	then
		return nil, "InvalidShopConfiguration"
	end
	if (config.refreshSeconds :: number) > MAX_SAFE_INTEGER - (config.epochSeconds :: number) then
		return nil, "InvalidShopConfiguration"
	end
	local materialRefs, rotation = array(config.materials, 6), array(config.rotation, 6)
	if not materialRefs or not rotation then
		return nil, "InvalidShopConfiguration"
	end
	local materialOffers: { Types.ShopOffer } = {}
	local materialDefinitions: { Record } = {}
	local knownMaterials: { [string]: boolean } = {}
	for index, raw in materialRefs do
		local reference = record(raw)
		if
			not reference
			or not closed(reference, { materialId = true, stockLimit = true })
			or not isId(reference.materialId)
			or not positiveWhole(reference.stockLimit)
		then
			return nil, "InvalidMaterialOffer"
		end
		local id = reference.materialId :: string
		local material = record(materials[id])
		if
			knownMaterials[id]
			or not material
			or material.launchEnabled ~= true
			or material.category ~= "material"
			or material.element ~= ELEMENTS[index]
			or material.stackLimit ~= Inventory.materialStackLimit
			or not positiveWhole(material.buyGold)
			or not positiveWhole(material.sellGold)
		then
			return nil, "InvalidShopMaterial"
		end
		if (material.buyGold :: number) <= (material.sellGold :: number) then
			return nil, "InvalidShopEconomy"
		end
		local offer = makeOffer(
			id,
			"Material",
			id,
			nil,
			material.buyGold :: number,
			reference.stockLimit :: number
		)
		if not offer then
			return nil, "OfferRevisionTooLong"
		end
		knownMaterials[id] = true
		table.insert(materialOffers, offer)
		table.insert(materialDefinitions, material)
	end
	for id, raw in materials do
		local material = record(raw)
		if material and material.launchEnabled == true and not knownMaterials[id] then
			return nil, "InvalidShopMaterial"
		end
	end
	local prepared: Prepared = {
		epoch = config.epochSeconds :: number,
		interval = config.refreshSeconds :: number,
		rotation = {},
	}
	local knownRecipes: { [string]: boolean } = {}
	local knownResults: { [string]: boolean } = {}
	for index, raw in rotation do
		local entry = record(raw)
		if
			not entry
			or not closed(entry, { element = true, sword = true, shield = true })
			or entry.element ~= ELEMENTS[index]
		then
			return nil, "InvalidShopRotation"
		end
		local offers = table.clone(materialOffers)
		local required = 0
		for _, role in { "sword", "shield" } do
			local offer, inputs, code = featured(
				entry[role],
				role,
				ELEMENTS[index],
				materialOffers[index].materialId :: string,
				materialDefinitions[index],
				recipes,
				Resolve
			)
			if not offer or not inputs then
				return nil, code
			end
			local reference = entry[role] :: Record
			local recipeId = reference.recipeId :: string
			local resultId =
				`{encode(offer.definitionId :: string)}|{encode(offer.finishId :: string)}`
			if
				knownRecipes[recipeId]
				or knownResults[resultId]
				or inputs > MAX_SAFE_INTEGER - required
			then
				return nil, "InvalidFeaturedRecipe"
			end
			knownRecipes[recipeId], knownResults[resultId] = true, true
			required += inputs
			table.insert(offers, offer)
		end
		if required > materialOffers[index].stockLimit then
			return nil, "InsufficientMaterialAllowance"
		end
		table.insert(prepared.rotation, { element = ELEMENTS[index], offers = offers })
	end
	for id in recipes do
		if not knownRecipes[id] then
			return nil, "InvalidFeaturedRecipe"
		end
	end
	return FreezeUtil.DeepFreeze(prepared), nil
end

function ShopCatalog.new(options: Options?): ShopCatalog
	-- Snapshot static owners once. A returned view cannot mutate source metadata or later offers.
	local prepared, problem = compile(options)
	local api = {}
	function api.ValidateLaunch(): (boolean, string?)
		return prepared ~= nil, problem
	end
	function api.Resolve(now: number): (Types.ShopPeriod?, string?)
		if not prepared then
			return nil, problem
		end
		if
			type(now) ~= "number"
			or now ~= now
			or now < prepared.epoch
			or now > MAX_SAFE_INTEGER
		then
			return nil, "InvalidTimestamp"
		end
		local periodId = math.floor((now - prepared.epoch) / prepared.interval)
		local offset = product(periodId, prepared.interval)
		if not whole(periodId) or not offset or offset > MAX_SAFE_INTEGER - prepared.epoch then
			return nil, "InvalidTimestamp"
		end
		local startsAt = prepared.epoch + offset
		if prepared.interval > MAX_SAFE_INTEGER - startsAt then
			return nil, "InvalidTimestamp"
		end
		local refreshAt = startsAt + prepared.interval
		-- A rounded quotient must never choose a different absolute period near extreme boundaries.
		if startsAt > now or refreshAt <= now or refreshAt - startsAt ~= prepared.interval then
			return nil, "InvalidTimestamp"
		end
		local current = prepared.rotation[periodId % #prepared.rotation + 1]
		local period: Types.ShopPeriod = {
			periodId = periodId,
			startsAt = startsAt,
			refreshAt = refreshAt,
			featuredElement = current.element,
			offers = current.offers,
		}
		return FreezeUtil.DeepFreeze(period), nil
	end
	return table.freeze(api)
end

local default = ShopCatalog.new()
ShopCatalog.Resolve = default.Resolve
ShopCatalog.ValidateLaunch = default.ValidateLaunch

return table.freeze(ShopCatalog)
