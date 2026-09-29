--!strict
-- ServerScriptService/Services/BaseService/BaseExpansionPurchase
-- Spend a fixed Gold/Material mix and permanently add one empty Shrine build slot atomically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local BaseState = require(ServerScriptService.Shared.BaseState)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type BaseExpansionPurchase = {
	Expand: (Player, Types.ExpandBaseRequest) -> Types.TransactionResult,
}

local BaseExpansionPurchase = {}
local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	expectedUpgradeCount = true,
	expectedGoldCost = true,
	expectedMaterialQuantity = true,
}
local ELEMENTS: { [string]: boolean } = {
	Fire = true,
	Water = true,
	Earth = true,
	Air = true,
	Light = true,
	Dark = true,
}
table.freeze(ELEMENTS)

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

local function parseRequest(value: unknown): Types.ExpandBaseRequest?
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
		or not whole(fields.expectedUpgradeCount)
		or not whole(fields.expectedGoldCost)
		or not whole(fields.expectedMaterialQuantity)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		expectedUpgradeCount = fields.expectedUpgradeCount :: number,
		expectedGoldCost = fields.expectedGoldCost :: number,
		expectedMaterialQuantity = fields.expectedMaterialQuantity :: number,
	}
end

local function hasValidConfiguration(): boolean
	if
		not whole(Bases.initialShrineSlots)
		or Bases.initialShrineSlots < 1
		or not isPlain(Bases.buildSlotGrants)
		or not isPlain(Bases.buildSlotUpgradeCosts)
		or not isPlain(Bases.expansionMaterialIds)
		or #Bases.buildSlotGrants == 0
		or #Bases.buildSlotUpgradeCosts ~= #Bases.buildSlotGrants
		or not whole(Inventory.materialStackLimit)
		or Inventory.materialStackLimit < 1
	then
		return false
	end
	local count = 0
	for index, grant in Bases.buildSlotGrants do
		if not whole(index) or index < 1 or index > #Bases.buildSlotGrants or grant ~= 1 then
			return false
		end
		count += 1
	end
	if count ~= #Bases.buildSlotGrants then
		return false
	end
	count = 0
	for index, cost in Bases.buildSlotUpgradeCosts do
		if
			not whole(index)
			or index < 1
			or index > #Bases.buildSlotGrants
			or not isPlain(cost)
			or not whole(cost.gold)
			or cost.gold < 1
			or not whole(cost.materialQuantity)
			or cost.materialQuantity < 1
		then
			return false
		end
		count += 1
	end
	if count ~= #Bases.buildSlotGrants then
		return false
	end
	local elements: { [string]: boolean } = {}
	count = 0
	for index, materialId in Bases.expansionMaterialIds do
		if not whole(index) or index < 1 or index > 6 or not isId(materialId) then
			return false
		end
		local definition = Materials[materialId]
		if not isPlain(definition) or definition.launchEnabled ~= true then
			return false
		end
		local element = definition.element
		if
			not element
			or not ELEMENTS[element]
			or elements[element]
			or definition.category ~= "material"
			or definition.stackLimit ~= Inventory.materialStackLimit
		then
			return false
		end
		elements[element] = true
		count += 1
	end
	return count == 6 and whole(Bases.initialShrineSlots + #Bases.buildSlotGrants)
end

function BaseExpansionPurchase.new(DataService: DataSource): BaseExpansionPurchase
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[BaseService.BaseExpansionPurchase] DataService.GetLoadedData and Transact required"
	)
	local api = {}

	function api.Expand(
		player: Player,
		rawRequest: Types.ExpandBaseRequest
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
			operation = "Base.Expand",
			signature = `count={count};gold={gold};quantity={quantity}`,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			if draft.version ~= PlayerData.schemaVersion then
				return { ok = false, code = "UnsupportedVersion" }
			end
			if not hasValidConfiguration() then
				return { ok = false, code = "InvalidExpansionConfiguration" }
			end
			local base = draft.base
			if not isPlain(base) then
				return { ok = false, code = "InvalidBaseState" }
			end
			local status = BaseState.GetStatus(base)
			if not status then
				return { ok = false, code = "InvalidBaseState" }
			end
			local previousCount = base.buildSlotUpgrades
			if previousCount ~= request.expectedUpgradeCount then
				return { ok = false, code = "UpgradeCountChanged" }
			end
			if status.unlockedShrineSlots >= status.maxShrineSlots then
				return { ok = false, code = "MaxBaseSlots" }
			end
			local nextCount = request.expectedUpgradeCount + 1
			local cost = Bases.buildSlotUpgradeCosts[nextCount]
			if not cost then
				return { ok = false, code = "InvalidExpansionConfiguration" }
			end
			if
				request.expectedGoldCost ~= cost.gold
				or request.expectedMaterialQuantity ~= cost.materialQuantity
			then
				return { ok = false, code = "PriceChanged" }
			end
			local materialError = InventoryCapacity.ValidateMaterialState(draft)
			if materialError then
				return { ok = false, code = materialError }
			end
			if not isPlain(draft.currency) or not whole(draft.currency.gold) then
				return { ok = false, code = "InvalidCurrency" }
			end
			-- The complete fixed recipe must fit before the purchase, with every active refund
			-- reservation retained. Unrelated old holdings do not pay or substitute for it.
			local payment = table.clone(draft)
			payment.materials = {}
			for _, materialId in Bases.expansionMaterialIds do
				payment.materials[materialId] = { total = cost.materialQuantity }
			end
			local paymentCapacity = InventoryCapacity.GetUsage(payment, "materials")
			if paymentCapacity.used > paymentCapacity.limit then
				return { ok = false, code = "MaterialCapacityTooSmall" }
			end
			if draft.currency.gold < cost.gold then
				return { ok = false, code = "InsufficientGold" }
			end
			for _, materialId in Bases.expansionMaterialIds do
				local owned = draft.materials[materialId]
				if not owned or owned.total < cost.materialQuantity then
					return { ok = false, code = "InsufficientMaterials" }
				end
			end
			for _, materialId in Bases.expansionMaterialIds do
				local owned = draft.materials[materialId]
				owned.total -= cost.materialQuantity
				if owned.total == 0 then
					draft.materials[materialId] = nil
				end
			end
			draft.currency.gold -= cost.gold
			base.buildSlotUpgrades = nextCount
			local expanded = BaseState.GetStatus(base)
			if not expanded or expanded.unlockedShrineSlots ~= status.unlockedShrineSlots + 1 then
				return { ok = false, code = "InvalidExpansionConfiguration" }
			end
			-- Only empty build capacity changed: no production inputs or accounting cursors move.
			return {
				ok = true,
				values = {
					previousUpgradeCount = request.expectedUpgradeCount,
					upgradeCount = nextCount,
					unlockedShrineSlots = expanded.unlockedShrineSlots,
					maxShrineSlots = expanded.maxShrineSlots,
					goldSpent = cost.gold,
					materialsSpentPerType = cost.materialQuantity,
				},
			}
		end)
	end

	return api
end

return table.freeze(BaseExpansionPurchase)
