--!strict
-- ServerScriptService/Services/InventoryService/Capacity

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local Types = require(ReplicatedStorage.Shared.Types)

local Capacity = {}

export type Category = "materials" | "mythlings" | "equipment"

type MaterialTotals = { [string]: number }

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

local function getActiveReservations(data: Types.PlayerDoc): (boolean, number, MaterialTotals)
	local equipment = 0
	local materials: MaterialTotals = {}
	local rawJobs: unknown = data.craftingJobs
	if rawJobs == nil then
		return true, equipment, materials
	end
	if type(rawJobs) ~= "table" then
		return false, equipment, materials
	end

	for _, rawJob in rawJobs :: { [unknown]: unknown } do
		if type(rawJob) ~= "table" then
			return false, equipment, materials
		end
		local job = rawJob :: { [string]: unknown }
		local status = job.status
		if status == "Active" then
			local rawReservations = job.reservations
			if type(rawReservations) ~= "table" then
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
			if type(rawMaterials) ~= "table" then
				return false, equipment, materials
			end
			for rawMaterialId, quantity in rawMaterials :: { [unknown]: unknown } do
				if
					type(rawMaterialId) ~= "string"
					or not addQuantity(materials, rawMaterialId, quantity)
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

local function getMaterialTotals(data: Types.PlayerDoc): (boolean, MaterialTotals)
	local valid, _, totals = getActiveReservations(data)
	if not valid then
		return false, totals
	end
	local rawOwned: unknown = data.materials
	if type(rawOwned) ~= "table" then
		return false, totals
	end
	for rawMaterialId, rawEntry in rawOwned :: { [unknown]: unknown } do
		if type(rawMaterialId) ~= "string" or type(rawEntry) ~= "table" then
			return false, totals
		end
		local entry = rawEntry :: { [string]: unknown }
		if not addQuantity(totals, rawMaterialId, entry.total) then
			return false, totals
		end
	end
	return true, totals
end

local function getPurchasedLevel(data: Types.PlayerDoc, category: Category): number?
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

function Capacity.GetLimit(category: Category, purchasedLevel: number?): number
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

function Capacity.GetMythlingLimit(purchasedLevel: number?): number
	return Capacity.GetLimit("mythlings", purchasedLevel)
end

function Capacity.GetUsage(data: Types.PlayerDoc, category: Category): Types.InventoryCapacity
	local limit = Capacity.GetLimit(category, getPurchasedLevel(data, category))
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

function Capacity.GetMaterialRoom(
	data: Types.PlayerDoc,
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
	local limit = Capacity.GetLimit("materials", getPurchasedLevel(data, "materials"))
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

return table.freeze(Capacity)
