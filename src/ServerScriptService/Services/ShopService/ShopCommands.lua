--!strict
-- ServerScriptService/Services/ShopService/ShopCommands
-- Resolve personal views without writes; buy the exact quoted offer with one profile transaction.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local ServerTypes = require(ServerScriptService.Shared.Types)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local GoldCreditUtil = require(ServerScriptService.Shared.GoldCreditUtil)
local ShopCatalog = require(script.Parent.ShopCatalog)
local ShopStock = require(script.Parent.ShopStock)
local ShopUpgrades = require(script.Parent.ShopUpgrades)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type Options = { clock: (() -> number)?, createId: (() -> string)? }
export type ShopCommands = {
	Get: (Player) -> Types.ShopViewResult,
	Buy: (Player, Types.BuyShopOfferRequest) -> Types.TransactionResult,
}

local ShopCommands = {}
local MAX_SAFE_INTEGER = 9007199254740991
local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	periodId = true,
	offerId = true,
	offerRevision = true,
	quantity = true,
}

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value % 1 == 0
end

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function currentRevision(data: Types.PlayerDoc): number
	local raw: unknown = data.transactions
	if raw == nil then
		return 0
	end
	if plain(raw) then
		local revision = (raw :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function parseRequest(raw: unknown): Types.BuyShopOfferRequest?
	if not plain(raw) then
		return nil
	end
	local fields = raw :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not whole(fields.periodId)
		or not isId(fields.offerId)
		or not isId(fields.offerRevision)
		or not whole(fields.quantity)
		or (fields.quantity :: number) < 1
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		periodId = fields.periodId :: number,
		offerId = fields.offerId :: string,
		offerRevision = fields.offerRevision :: string,
		quantity = fields.quantity :: number,
	}
end

local function validateResources(data: Types.PlayerDoc): string?
	local materialError = InventoryCapacity.ValidateMaterialState(data)
	if materialError then
		return materialError
	end
	local upgrades = data.inventoryUpgrades
	local equipmentUpgrade = if upgrades then upgrades.equipment else nil
	if
		equipmentUpgrade ~= nil
		and (
			not whole(equipmentUpgrade)
			or equipmentUpgrade >= #Inventory.capacityByCategory.equipment
		)
	then
		return "InvalidInventoryUpgrade"
	end
	if not plain(data.equipment) then
		return "InvalidInventoryState"
	end
	for id, entry in data.equipment do
		if
			not isId(id)
			or not plain(entry)
			or not isId(entry.definitionId)
			or (entry.finishId ~= nil and not isId(entry.finishId))
			or (entry.isStarterGrant ~= nil and type(entry.isStarterGrant) ~= "boolean")
		then
			return "InvalidInventoryState"
		end
	end
	if not plain(data.currency) or not whole(data.currency.gold) then
		return "InvalidCurrency"
	end
	local refundGold, refundError = GoldCreditUtil.GetRefundReserve(data)
	if refundGold == nil then
		return refundError or "InvalidCraftingState"
	end
	if refundGold > MAX_SAFE_INTEGER - data.currency.gold then
		return "ArithmeticOverflow"
	end
	return nil
end

local function resolveState(
	data: Types.PlayerDoc,
	now: number
): (Types.ShopPeriod?, { [string]: number }?, string?)
	if data.version ~= PlayerData.schemaVersion then
		return nil, nil, "UnsupportedVersion"
	end
	local period, catalogError = ShopCatalog.Resolve(now)
	if not period then
		return nil, nil, catalogError or "InvalidShopConfiguration"
	end
	local purchased, stockError = ShopStock.Read(data.shop, period.periodId)
	if not purchased then
		return nil, nil, stockError or "InvalidShopState"
	end
	return period, purchased, nil
end

local function inventoryRoom(data: Types.PlayerDoc, offer: Types.ShopOffer): (number?, string?)
	if
		not whole(offer.unitGold)
		or offer.unitGold < 1
		or not whole(offer.stockLimit)
		or offer.stockLimit < 1
	then
		return nil, "InvalidShopConfiguration"
	end
	if offer.kind == "Material" then
		if not isId(offer.materialId) then
			return nil, "InvalidShopConfiguration"
		end
		return InventoryCapacity.GetMaterialRoom(data, offer.materialId :: string), nil
	elseif offer.kind == "Equipment" then
		-- Launch Featured grants one copy, preserving the scalar transaction receipt contract.
		if offer.stockLimit ~= 1 or not isId(offer.definitionId) or not isId(offer.finishId) then
			return nil, "InvalidShopConfiguration"
		end
		local capacity = InventoryCapacity.GetUsage(data, "equipment")
		return math.max(0, capacity.limit - capacity.used), nil
	end
	return nil, "InvalidShopConfiguration"
end

local function stockRemaining(purchased: { [string]: number }, offer: Types.ShopOffer): number
	return math.max(0, offer.stockLimit - (purchased[offer.stockKey] or 0))
end

local function reservedIdentities(data: Types.PlayerDoc): ({ [string]: boolean }?, string?)
	local used: { [string]: boolean } = {}
	for id in data.equipment do
		used[id] = true
	end
	for jobId, job in data.craftingJobs or {} do
		if not isId(jobId) then
			return nil, "InvalidCraftingState"
		end
		used[jobId] = true
		local receipt = job.receipt
		if receipt == nil then
			continue
		end
		-- Crafting owns full receipt semantics. Inspect only the identities a new grant must
		-- not overwrite, including retained resolved promises and reservation-only legacy jobs.
		if not plain(receipt.result) or not plain(receipt.result.instanceIds) then
			return nil, "InvalidCraftingState"
		end
		local size = #receipt.result.instanceIds
		local count = 0
		for index, instanceId in receipt.result.instanceIds do
			if not whole(index) or index < 1 or index > size or not isId(instanceId) then
				return nil, "InvalidCraftingState"
			end
			count += 1
			used[instanceId] = true
		end
		if count == 0 or count ~= size then
			return nil, "InvalidCraftingState"
		end
	end
	return used, nil
end

local function idPart(value: string): string
	return `{#value}:{value}`
end

function ShopCommands.new(DataService: DataSource, options: Options?): ShopCommands
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[ShopService.ShopCommands] DataService.GetLoadedData and Transact required"
	)
	local clock = if options and options.clock
		then options.clock
		else function(): number
			return workspace:GetServerTimeNow()
		end
	local createId = if options and options.createId
		then options.createId
		else function(): string
			return `equipment_{HttpService:GenerateGUID(false)}`
		end
	local api = {}

	function api.Get(player: Player): Types.ShopViewResult
		local data = DataService.GetLoadedData(player)
		if not data then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local revision = currentRevision(data)
		if revision < 0 then
			return { ok = false, code = "InvalidTransaction", revision = revision }
		end
		local sampled, now = pcall(clock)
		if not sampled or type(now) ~= "number" or now ~= now or now < 0 or now >= 2 ^ 53 then
			return { ok = false, code = "InvalidTimestamp", revision = revision }
		end
		local period, purchased, stateError = resolveState(data, now)
		if not period or not purchased then
			return { ok = false, code = stateError, revision = revision }
		end
		local resourcesError = validateResources(data)
		if resourcesError then
			return { ok = false, code = resourcesError, revision = revision }
		end
		local offers: { Types.ShopOfferView } = {}
		for _, offer in period.offers do
			local room, roomError = inventoryRoom(data, offer)
			if room == nil then
				return { ok = false, code = roomError, revision = revision }
			end
			local remaining = stockRemaining(purchased, offer)
			local affordable = math.floor(data.currency.gold / offer.unitGold)
			local maximum = math.min(remaining, room, affordable)
			local code: string? = nil
			if remaining < 1 then
				code = "InsufficientStock"
			elseif affordable < 1 then
				code = "InsufficientGold"
			elseif room < 1 then
				code = "InventoryFull"
			end
			local view: Types.ShopOfferView = {
				offerId = offer.offerId,
				offerRevision = offer.offerRevision,
				stockKey = offer.stockKey,
				kind = offer.kind,
				materialId = offer.materialId,
				definitionId = offer.definitionId,
				finishId = offer.finishId,
				unitGold = offer.unitGold,
				stockLimit = offer.stockLimit,
				remainingStock = remaining,
				maxPurchasable = maximum,
				purchaseCode = code,
			}
			table.insert(offers, view)
		end
		return {
			ok = true,
			revision = revision,
			view = {
				sampledAt = now,
				periodId = period.periodId,
				startsAt = period.startsAt,
				refreshAt = period.refreshAt,
				featuredElement = period.featuredElement,
				offers = offers,
				upgrades = ShopUpgrades.Snapshot(data),
			},
		}
	end

	function api.Buy(player: Player, rawRequest: Types.BuyShopOfferRequest): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local periodText = string.format("%.0f", request.periodId + 0)
		local quantityText = string.format("%.0f", request.quantity)
		local signature = `period={periodText};offer={idPart(request.offerId)};revision={idPart(
			request.offerRevision
		)};quantity={quantityText}`
		if #signature > PlayerData.maxSignatureLength then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Shop.BuyOffer",
			signature = signature,
		}, function(draft: Types.PlayerDoc, now: number): Types.TransactionOutcome
			local period, purchased, stateError = resolveState(draft, now)
			if not period or not purchased then
				return { ok = false, code = stateError }
			end
			if request.periodId ~= period.periodId then
				return { ok = false, code = "OfferExpired" }
			end
			local offer: Types.ShopOffer? = nil
			for _, candidate in period.offers do
				if candidate.offerId == request.offerId then
					offer = candidate
					break
				end
			end
			if not offer then
				return { ok = false, code = "OfferNotFound" }
			end
			if offer.offerRevision ~= request.offerRevision then
				return { ok = false, code = "OfferChanged" }
			end
			local resourcesError = validateResources(draft)
			if resourcesError then
				return { ok = false, code = resourcesError }
			end
			local room, roomError = inventoryRoom(draft, offer)
			if room == nil then
				return { ok = false, code = roomError }
			end
			local remaining = stockRemaining(purchased, offer)
			if request.quantity > remaining then
				return { ok = false, code = "InsufficientStock" }
			end
			if request.quantity > math.floor(MAX_SAFE_INTEGER / offer.unitGold) then
				return { ok = false, code = "ArithmeticOverflow" }
			end
			local cost = request.quantity * offer.unitGold
			if not whole(cost) then
				return { ok = false, code = "ArithmeticOverflow" }
			end
			if cost > draft.currency.gold then
				return { ok = false, code = "InsufficientGold" }
			end
			if request.quantity > room then
				return { ok = false, code = "InventoryFull" }
			end
			local instanceId: string? = nil
			if offer.kind == "Equipment" then
				local used, identityError = reservedIdentities(draft)
				if not used then
					return { ok = false, code = identityError }
				end
				local generated = createId()
				if not isId(generated) or used[generated] then
					return { ok = false, code = "InstanceIdConflict" }
				end
				instanceId = generated
			else
				local materialId = offer.materialId :: string
				local owned = draft.materials[materialId]
				local total = if owned then owned.total else 0
				if request.quantity > MAX_SAFE_INTEGER - total then
					return { ok = false, code = "ArithmeticOverflow" }
				end
			end
			-- All validation and identity allocation precedes edits. The transaction also rolls
			-- back due-job preparation if this command fails or loses its active session.
			local values: Types.TransactionValues = {
				offerId = offer.offerId,
				offerRevision = offer.offerRevision,
				periodId = period.periodId,
				quantity = request.quantity,
				unitGold = offer.unitGold,
				goldSpent = cost,
				goldBalance = draft.currency.gold - cost,
				remainingStock = remaining - request.quantity,
			}
			if instanceId then
				local definitionId, finishId =
					offer.definitionId :: string, offer.finishId :: string
				draft.equipment[instanceId] =
					{ definitionId = definitionId, finishId = finishId, isStarterGrant = false }
				values.instanceId = instanceId
				values.definitionId = definitionId
				values.finishId = finishId
			else
				local materialId = offer.materialId :: string
				local entry = draft.materials[materialId]
				if entry then
					entry.total += request.quantity
				else
					draft.materials[materialId] = { total = request.quantity }
				end
				values.materialId = materialId
			end
			draft.currency.gold -= cost
			purchased[offer.stockKey] = (purchased[offer.stockKey] or 0) + request.quantity
			draft.shop = { periodId = period.periodId, purchased = purchased }
			return { ok = true, values = values }
		end)
	end

	return api
end

return table.freeze(ShopCommands)
