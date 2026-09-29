--!strict
-- ServerScriptService/Services/BaseService/BaseExpansionPurchase
-- Spend a fixed Gold/Material mix and permanently add one empty Shrine build slot atomically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local BaseState = require(ServerScriptService.Shared.BaseState)
local UpgradePaymentUtil = require(ServerScriptService.Shared.UpgradePaymentUtil)

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
		or not UpgradePaymentUtil.ValidateMaterialMix(Bases.expansionMaterialIds)
		or #Bases.buildSlotGrants == 0
		or #Bases.buildSlotUpgradeCosts ~= #Bases.buildSlotGrants
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
			or not UpgradePaymentUtil.ValidateCost(cost)
		then
			return false
		end
		count += 1
	end
	if count ~= #Bases.buildSlotGrants then
		return false
	end
	return whole(Bases.initialShrineSlots + #Bases.buildSlotGrants)
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
			local paymentError =
				UpgradePaymentUtil.PayToDraft(draft, cost, Bases.expansionMaterialIds)
			if paymentError then
				return { ok = false, code = paymentError }
			end
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
