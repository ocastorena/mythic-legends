--!strict
-- ServerScriptService/Services/InventoryService/CapacityUpgradePurchase
-- Buy one permanent category-capacity upgrade without borrowing its new space for payment.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local UpgradePaymentUtil = require(ServerScriptService.Shared.UpgradePaymentUtil)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type CapacityUpgradePurchase = {
	Upgrade: (Player, Types.UpgradeInventoryCapacityRequest) -> Types.TransactionResult,
}

local CapacityUpgradePurchase = {}
local CATEGORIES: { InventoryCapacity.Category } = { "materials", "mythlings", "equipment" }
table.freeze(CATEGORIES)
local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	category = true,
	expectedUpgradeCount = true,
	expectedGoldCost = true,
	expectedMaterialQuantity = true,
}

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isPlain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if type(state) == "table" then
		local revision = (state :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function parseRequest(value: unknown): Types.UpgradeInventoryCapacityRequest?
	if not isPlain(value) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or (fields.category ~= "materials" and fields.category ~= "mythlings" and fields.category ~= "equipment")
		or not whole(fields.expectedUpgradeCount)
		or not whole(fields.expectedGoldCost)
		or not whole(fields.expectedMaterialQuantity)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		category = fields.category :: InventoryCapacity.Category,
		expectedUpgradeCount = fields.expectedUpgradeCount :: number,
		expectedGoldCost = fields.expectedGoldCost :: number,
		expectedMaterialQuantity = fields.expectedMaterialQuantity :: number,
	}
end

local function hasValidConfiguration(): boolean
	if
		not isPlain(Inventory.capacityByCategory)
		or not isPlain(Inventory.capacityUpgradeCosts)
		or #Inventory.capacityUpgradeCosts ~= 2
		or not UpgradePaymentUtil.ValidateMaterialMix(Inventory.upgradeMaterialIds)
	then
		return false
	end
	local costCount = 0
	for index, cost in Inventory.capacityUpgradeCosts do
		if
			not whole(index)
			or index < 1
			or index > 2
			or not UpgradePaymentUtil.ValidateCost(cost)
		then
			return false
		end
		costCount += 1
	end
	if costCount ~= 2 then
		return false
	end
	for _, category in CATEGORIES do
		local capacities = Inventory.capacityByCategory[category]
		if not isPlain(capacities) or #capacities ~= 3 then
			return false
		end
		local count = 0
		for index, limit in capacities do
			if not whole(index) or index < 1 or index > 3 or not whole(limit) or limit < 1 then
				return false
			end
			count += 1
		end
		if
			count ~= 3
			or capacities[2] - capacities[1] ~= 12
			or capacities[3] - capacities[2] ~= 12
		then
			return false
		end
	end
	return true
end

local function hasValidPurchasedCounts(data: Types.PlayerDoc): boolean
	local upgrades = data.inventoryUpgrades
	if upgrades == nil then
		return true
	end
	if not isPlain(upgrades) then
		return false
	end
	for _, category in CATEGORIES do
		local count = upgrades[category]
		if count ~= nil and (not whole(count) or count > #Inventory.capacityUpgradeCosts) then
			return false
		end
	end
	return true
end

local function hasValidOwnedCollection(
	data: Types.PlayerDoc,
	category: InventoryCapacity.Category
): boolean
	local owned: unknown = if category == "materials"
		then data.materials
		elseif category == "mythlings" then data.mythlings
		else data.equipment
	if not isPlain(owned) then
		return false
	end
	for id, entry in owned :: { [unknown]: unknown } do
		if not isId(id) or not isPlain(entry) then
			return false
		end
	end
	return true
end

function CapacityUpgradePurchase.new(DataService: DataSource): CapacityUpgradePurchase
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[InventoryService.CapacityUpgradePurchase] DataService.GetLoadedData and Transact required"
	)
	local api = {}

	function api.Upgrade(
		player: Player,
		rawRequest: Types.UpgradeInventoryCapacityRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local count = string.format("%.0f", request.expectedUpgradeCount + 0)
		local gold = string.format("%.0f", request.expectedGoldCost + 0)
		local quantity = string.format("%.0f", request.expectedMaterialQuantity + 0)
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Inventory.UpgradeCapacity",
			signature = `category={#request.category}:{request.category};count={count};gold={gold};quantity={quantity}`,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			if draft.version ~= PlayerData.schemaVersion then
				return { ok = false, code = "UnsupportedVersion" }
			end
			if not hasValidConfiguration() then
				return { ok = false, code = "InvalidUpgradeConfiguration" }
			end
			if not hasValidPurchasedCounts(draft) then
				return { ok = false, code = "InvalidInventoryUpgrade" }
			end
			if not hasValidOwnedCollection(draft, request.category) then
				return { ok = false, code = "InvalidInventoryState" }
			end
			local upgrades = draft.inventoryUpgrades
			local previousCount = if upgrades then upgrades[request.category] or 0 else 0
			if previousCount ~= request.expectedUpgradeCount then
				return { ok = false, code = "UpgradeCountChanged" }
			end
			if previousCount >= #Inventory.capacityUpgradeCosts then
				return { ok = false, code = "MaxCapacity" }
			end
			local nextCount = previousCount + 1
			local cost = Inventory.capacityUpgradeCosts[nextCount]
			if
				request.expectedGoldCost ~= cost.gold
				or request.expectedMaterialQuantity ~= cost.materialQuantity
			then
				return { ok = false, code = "PriceChanged" }
			end
			-- Validate and pay using the OLD category capacities and unchanged reservations.
			-- In particular, a Materials upgrade cannot create the space needed for its costs.
			local paymentError =
				UpgradePaymentUtil.PayToDraft(draft, cost, Inventory.upgradeMaterialIds)
			if paymentError then
				return { ok = false, code = paymentError }
			end
			local purchasedCounts: { [string]: number } = upgrades or {}
			if not upgrades then
				draft.inventoryUpgrades = purchasedCounts
			end
			purchasedCounts[request.category] = nextCount
			local capacities = Inventory.capacityByCategory[request.category]
			local usage = InventoryCapacity.GetUsage(draft, request.category)
			return {
				ok = true,
				values = {
					category = request.category,
					previousUpgradeCount = previousCount,
					upgradeCount = nextCount,
					limit = usage.limit,
					maxLimit = capacities[#capacities],
					goldSpent = cost.gold,
					materialsSpentPerType = cost.materialQuantity,
				},
			}
		end)
	end

	return api
end

return table.freeze(CapacityUpgradePurchase)
