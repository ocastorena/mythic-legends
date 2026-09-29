--!strict
-- ServerScriptService/Services/ShopService/ShopUpgrades
-- Read-only capacity quotes; InventoryService remains the sole upgrade mutation owner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local UpgradePaymentUtil = require(ServerScriptService.Shared.UpgradePaymentUtil)

local ShopUpgrades = {}
local CATEGORIES: { InventoryCapacity.Category } = { "materials", "mythlings", "equipment" }

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function stateProblem(data: Types.PlayerDoc, category: InventoryCapacity.Category): string?
	local upgrades = data.inventoryUpgrades
	if upgrades ~= nil then
		if not plain(upgrades) then
			return "InvalidInventoryUpgrade"
		end
		for _, key in CATEGORIES do
			local level = upgrades[key]
			if level ~= nil and (not whole(level) or level > #Inventory.capacityUpgradeCosts) then
				return "InvalidInventoryUpgrade"
			end
		end
	end
	local collection: unknown = if category == "materials"
		then data.materials
		elseif category == "mythlings" then data.mythlings
		else data.equipment
	if not plain(collection) then
		return "InvalidInventoryState"
	end
	for id, entry in collection :: { [unknown]: unknown } do
		if type(id) ~= "string" or #id == 0 or #id > 128 or not plain(entry) then
			return "InvalidInventoryState"
		end
	end
	return InventoryCapacity.ValidateMaterialState(data)
end

local function paymentProblem(data: Types.PlayerDoc, cost: UpgradePaymentUtil.Cost): string?
	if not plain(data.currency) then
		return "InvalidCurrency"
	end
	-- PayToDraft mutates only currency and owned Material entries. Copy those surfaces so this
	-- preview uses exactly the real payment/capacity rules without reserving or spending anything.
	local candidate = table.clone(data)
	candidate.currency = table.clone(data.currency)
	candidate.materials = {}
	for id, entry in data.materials do
		candidate.materials[id] = table.clone(entry)
	end
	return UpgradePaymentUtil.PayToDraft(candidate, cost, Inventory.upgradeMaterialIds)
end

function ShopUpgrades.Snapshot(data: Types.PlayerDoc): { Types.ShopUpgradeView }
	local views: { Types.ShopUpgradeView } = {}
	for _, category in CATEGORIES do
		local problem = stateProblem(data, category)
		local levels = Inventory.capacityByCategory[category]
		local rawLevel = if plain(data.inventoryUpgrades)
			then (data.inventoryUpgrades :: { [string]: number })[category]
			else nil
		local level = if rawLevel ~= nil
				and whole(rawLevel)
				and rawLevel < #levels
			then rawLevel
			else 0
		local view: Types.ShopUpgradeView = {
			category = category,
			purchasedUpgradeCount = level,
			capacity = levels[level + 1],
			maxCapacity = levels[#levels],
			materials = {},
			canPurchase = false,
			purchaseCode = problem,
		}
		local cost = Inventory.capacityUpgradeCosts[level + 1]
		if cost then
			view.nextCapacity = levels[level + 2]
			view.goldCost = cost.gold
			for _, materialId in Inventory.upgradeMaterialIds do
				local entry = if plain(data.materials) then data.materials[materialId] else nil
				local owned = if plain(entry) and whole((entry :: Types.MaterialEntry).total)
					then (entry :: Types.MaterialEntry).total
					else 0
				table.insert(view.materials, {
					materialId = materialId,
					quantity = cost.materialQuantity,
					ownedQuantity = owned,
				})
			end
			if not problem then
				view.purchaseCode = paymentProblem(data, cost)
				view.canPurchase = view.purchaseCode == nil
			end
		elseif not problem then
			view.purchaseCode = "MaxCapacity"
		end
		table.insert(views, view)
	end
	return views
end

return table.freeze(ShopUpgrades)
