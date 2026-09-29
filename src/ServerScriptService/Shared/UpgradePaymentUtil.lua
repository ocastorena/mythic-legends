--!strict
-- ServerScriptService/Shared/UpgradePaymentUtil
-- Shared fixed-mix payment on the caller's transaction draft, before granting any capacity.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local InventoryCapacity = require(script.Parent.InventoryCapacity)

local UpgradePaymentUtil = {}
export type Cost = { gold: number, materialQuantity: number }

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

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

function UpgradePaymentUtil.ValidateCost(value: unknown): boolean
	if not plain(value) then
		return false
	end
	local cost = value :: { [string]: unknown }
	return whole(cost.gold)
		and (cost.gold :: number) > 0
		and whole(cost.materialQuantity)
		and (cost.materialQuantity :: number) > 0
end

function UpgradePaymentUtil.ValidateMaterialMix(value: unknown): boolean
	if
		not plain(value)
		or not whole(Inventory.materialStackLimit)
		or Inventory.materialStackLimit < 1
	then
		return false
	end
	local elements: { [string]: boolean } = {}
	local count = 0
	for index, materialId in value :: { [unknown]: unknown } do
		if
			not whole(index)
			or (index :: number) < 1
			or (index :: number) > 6
			or type(materialId) ~= "string"
			or #materialId == 0
			or #materialId > 128
		then
			return false
		end
		local definition = Materials[materialId]
		if
			not definition
			or definition.launchEnabled ~= true
			or definition.category ~= "material"
			or definition.stackLimit ~= Inventory.materialStackLimit
		then
			return false
		end
		local element = definition.element
		if not element or not ELEMENTS[element] or elements[element] then
			return false
		end
		elements[element] = true
		count += 1
	end
	return count == 6
end

-- Return a rejection code without editing the draft, or nil after applying the complete payment.
-- The owning command validates identity/tier/quote and commits payment + purchase in one transaction.
function UpgradePaymentUtil.PayToDraft(
	draft: Types.PlayerDoc,
	cost: Cost,
	materialIds: { string }
): string?
	if
		not UpgradePaymentUtil.ValidateCost(cost)
		or not UpgradePaymentUtil.ValidateMaterialMix(materialIds)
	then
		return "InvalidUpgradeConfiguration"
	end
	local materialError = InventoryCapacity.ValidateMaterialState(draft)
	if materialError then
		return materialError
	end
	if not plain(draft.currency) or not whole(draft.currency.gold) then
		return "InvalidCurrency"
	end
	-- Prove this recipe fits the PRE-purchase bag alongside unchanged refund reservations.
	-- Retained unrelated over-capacity holdings may still be spent; they cannot pay this mix.
	local payment = table.clone(draft)
	payment.materials = {}
	for _, materialId in materialIds do
		payment.materials[materialId] = { total = cost.materialQuantity }
	end
	local capacity = InventoryCapacity.GetUsage(payment, "materials")
	if capacity.used > capacity.limit then
		return "MaterialCapacityTooSmall"
	end
	if draft.currency.gold < cost.gold then
		return "InsufficientGold"
	end
	for _, materialId in materialIds do
		local owned = draft.materials[materialId]
		if not owned or owned.total < cost.materialQuantity then
			return "InsufficientMaterials"
		end
	end
	for _, materialId in materialIds do
		local owned = draft.materials[materialId]
		owned.total -= cost.materialQuantity
		if owned.total == 0 then
			draft.materials[materialId] = nil
		end
	end
	draft.currency.gold -= cost.gold
	return nil
end

return table.freeze(UpgradePaymentUtil)
