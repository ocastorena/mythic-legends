--!strict
-- ServerScriptService/Domain/Inventory/InventoryCapacity

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local Types = require(ReplicatedStorage.Shared.Types)

local InventoryCapacity = {}

export type Category = "materials" | "mythlings" | "equipment"
export type MaterialEntries = { [string]: Types.MaterialEntry }
export type MaterialState = {
	materials: MaterialEntries,
	inventoryUpgrades: { [string]: number }?,
	craftingJobs: { [string]: Types.CraftingJob }?,
}

type MaterialTotals = { [string]: number }
type MaterialValidationError = "InvalidInventoryState" | "InvalidReservations"
type ReservationState = { craftingJobs: { [string]: Types.CraftingJob }? }
type UpgradeState = { inventoryUpgrades: { [string]: number }? }

local function isAcceptedTable(value: unknown, requirePlain: boolean?): boolean
	return type(value) == "table" and (not requirePlain or getmetatable(value) == nil)
end

local function isAcceptedMaterialId(value: unknown, requireNonempty: boolean?): boolean
	return type(value) == "string" and (not requireNonempty or #value > 0)
end

local function isWholeQuantity(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function addQuantity(totals: MaterialTotals, materialId: string, value: unknown): boolean
	if not isWholeQuantity(value) then
		return false
	end
	local nextTotal = (totals[materialId] or 0) + (value :: number)
	if not isWholeQuantity(nextTotal) then
		return false
	end
	totals[materialId] = nextTotal
	return true
end

local function getActiveReservations(
	data: ReservationState,
	strictShape: boolean?
): (boolean, number, MaterialTotals)
	local equipment = 0
	local materials: MaterialTotals = {}
	local rawJobs: unknown = data.craftingJobs
	if rawJobs == nil then
		return true, equipment, materials
	end
	if not isAcceptedTable(rawJobs, strictShape) then
		return false, equipment, materials
	end

	for _, rawJob in rawJobs :: { [unknown]: unknown } do
		if not isAcceptedTable(rawJob, strictShape) then
			return false, equipment, materials
		end
		local job = rawJob :: { [string]: unknown }
		local status = job.status
		if status == "Active" then
			local rawReservations = job.reservations
			if not isAcceptedTable(rawReservations, strictShape) then
				return false, equipment, materials
			end
			local reservations = rawReservations :: { [string]: unknown }
			if not isWholeQuantity(reservations.equipment) then
				return false, equipment, materials
			end
			local nextEquipment = equipment + (reservations.equipment :: number)
			if not isWholeQuantity(nextEquipment) then
				return false, equipment, materials
			end
			equipment = nextEquipment

			local rawMaterials = reservations.materials
			if not isAcceptedTable(rawMaterials, strictShape) then
				return false, equipment, materials
			end
			for rawMaterialId, quantity in rawMaterials :: { [unknown]: unknown } do
				if
					not isAcceptedMaterialId(rawMaterialId, strictShape)
					or not addQuantity(materials, rawMaterialId :: string, quantity)
				then
					return false, equipment, materials
				end
			end
		elseif status ~= "Completed" and status ~= "Cancelled" then
			return false, equipment, materials
		end
	end

	return true, equipment, materials
end

local function getMaterialTotals(
	data: MaterialState,
	strictShape: boolean?
): (boolean, MaterialTotals, MaterialValidationError?)
	local valid, _, totals = getActiveReservations(data, strictShape)
	if not valid then
		return false, totals, "InvalidReservations"
	end
	local rawOwned: unknown = data.materials
	if not isAcceptedTable(rawOwned, strictShape) then
		return false, totals, "InvalidInventoryState"
	end
	for rawMaterialId, rawEntry in rawOwned :: { [unknown]: unknown } do
		if
			not isAcceptedMaterialId(rawMaterialId, strictShape)
			or not isAcceptedTable(rawEntry, strictShape)
		then
			return false, totals, "InvalidInventoryState"
		end
		local entry = rawEntry :: { [string]: unknown }
		if not addQuantity(totals, rawMaterialId :: string, entry.total) then
			return false, totals, "InvalidInventoryState"
		end
	end
	return true, totals, nil
end

local function getPurchasedLevel(data: UpgradeState, category: Category): number?
	local rawUpgrades: unknown = data.inventoryUpgrades
	if type(rawUpgrades) ~= "table" then
		return nil
	end
	return (rawUpgrades :: { [string]: unknown })[category] :: number?
end

local function countEntries(rawEntries: unknown): (boolean, number)
	if type(rawEntries) ~= "table" then
		return false, 0
	end
	local count = 0
	for _ in rawEntries :: { [unknown]: unknown } do
		count += 1
	end
	return true, count
end

function InventoryCapacity.GetLimit(category: Category, purchasedLevel: number?): number
	local capacities = Inventory.capacityByCategory[category]
	if not capacities then
		return 0
	end
	local level = if type(purchasedLevel) == "number" then purchasedLevel else 0
	if level ~= level or level == math.huge or level == -math.huge then
		level = 0
	end
	local index = math.clamp(math.floor(level), 0, #capacities - 1) + 1
	return capacities[index]
end

function InventoryCapacity.GetMythlingLimit(purchasedLevel: number?): number
	return InventoryCapacity.GetLimit("mythlings", purchasedLevel)
end

function InventoryCapacity.ValidateMaterialState(data: MaterialState): string?
	if not isAcceptedTable(data, true) or not isAcceptedTable(data.materials, true) then
		return "InvalidInventoryState"
	end

	local rawUpgrades: unknown = data.inventoryUpgrades
	if rawUpgrades ~= nil then
		if not isAcceptedTable(rawUpgrades, true) then
			return "InvalidInventoryUpgrade"
		end
		local purchasedLevel = (rawUpgrades :: { [string]: unknown }).materials
		if
			purchasedLevel ~= nil
			and (
				not isWholeQuantity(purchasedLevel)
				or (purchasedLevel :: number) > #Inventory.capacityByCategory.materials - 1
			)
		then
			return "InvalidInventoryUpgrade"
		end
	end

	local rawJobs: unknown = data.craftingJobs
	if rawJobs ~= nil and not isAcceptedTable(rawJobs, true) then
		return "InvalidReservations"
	end
	local valid, _, problem = getMaterialTotals(data, true)
	if not valid then
		return problem or "InvalidInventoryState"
	end
	return nil
end

function InventoryCapacity.GetUsage(
	data: Types.PlayerDoc,
	category: Category
): Types.InventoryCapacity
	local limit = InventoryCapacity.GetLimit(category, getPurchasedLevel(data, category))
	if category == "materials" then
		local valid, totals = getMaterialTotals(data)
		if not valid then
			return { used = limit, limit = limit }
		end
		local used = 0
		for _, total in totals do
			used += math.ceil(total / Inventory.materialStackLimit)
		end
		return { used = used, limit = limit }
	elseif category == "equipment" then
		local validOwned, owned = countEntries(data.equipment)
		local validReservations, reserved = getActiveReservations(data)
		if not validOwned or not validReservations then
			return { used = limit, limit = limit }
		end
		return { used = owned + reserved, limit = limit }
	end

	local validOwned, owned = countEntries(data.mythlings)
	return { used = if validOwned then owned else limit, limit = limit }
end

function InventoryCapacity.GetMaterialRoom(
	data: MaterialState,
	materialId: string,
	stackLimit: number?
): number
	local resolvedStackLimit = stackLimit or Inventory.materialStackLimit
	if materialId == "" or not isWholeQuantity(resolvedStackLimit) or resolvedStackLimit == 0 then
		return 0
	end

	local valid, totals = getMaterialTotals(data)
	if not valid then
		return 0
	end
	local limit = InventoryCapacity.GetLimit("materials", getPurchasedLevel(data, "materials"))
	local used = 0
	for id, total in totals do
		local currentStackLimit = if id == materialId
			then resolvedStackLimit
			else Inventory.materialStackLimit
		used += math.ceil(total / currentStackLimit)
	end
	if used > limit then
		return 0
	end

	local matchingTotal = totals[materialId] or 0
	local matchingSlots = math.ceil(matchingTotal / resolvedStackLimit)
	local compatibleRoom = matchingSlots * resolvedStackLimit - matchingTotal
	local emptySlots = limit - used
	return compatibleRoom + emptySlots * resolvedStackLimit
end

return table.freeze(InventoryCapacity)
