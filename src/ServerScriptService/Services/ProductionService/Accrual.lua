-- ServerScriptService/Services/ProductionService/Accrual
-- Calculates a stationed mythling's stored production and transfers collected Materials
-- through InventoryService.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local log = LogUtil.For("ProductionService")

local Accrual = {}

type InventoryServiceApi = {
	GetMythling: (Player, string) -> Types.MythlingEntry?,
	AddMaterial: (Player, string, number) -> (),
	MarkDirty: (Player) -> boolean,
}
export type ProductionStatus = {
	production: number,
	capacity: number,
	rate: number,
}

local InventoryService: InventoryServiceApi
local MythlingsData: { [string]: Types.MythlingDef }

local function getEntry(player: Player, mythlingId: string): Types.MythlingEntry?
	return InventoryService.GetMythling(player, mythlingId)
end

local function calculate(player: Player, mythlingId: string): (number, number, number)
	local entry = getEntry(player, mythlingId)
	if not entry then
		return 0, 0, 0
	end

	local mythlingType = entry.typeId
	if not mythlingType or not MythlingsData[mythlingType] then
		log.warn(`Unknown typeId '{tostring(mythlingType)}' for mythlingId {mythlingId}`)
		return 0, 0, 0
	end

	local production = MythlingsData[mythlingType].production
	local rate = production.baseRate
	local capacity = production.baseCapacity
	local lastCollection = entry.lastCollectionAt
	if not lastCollection then
		return 0, capacity, rate
	end

	local currentAmount = rate * (os.time() - lastCollection) / 60
	return math.floor(math.min(currentAmount, capacity)), capacity, rate
end

function Accrual.Init(inventoryService: InventoryServiceApi, mythlingsData: { [string]: Types.MythlingDef })
	InventoryService = inventoryService
	MythlingsData = mythlingsData
end

function Accrual.Get(player: Player, mythlingId: string): ProductionStatus?
	local entry = getEntry(player, mythlingId)
	if not entry or entry.lastCollectionAt == nil then
		return nil
	end

	local production, capacity, rate = calculate(player, mythlingId)
	return { production = production, capacity = capacity, rate = rate }
end

function Accrual.Collect(player: Player, mythlingId: string): (boolean, string?)
	local entry = getEntry(player, mythlingId)
	if not entry then
		return false, "NotOwned"
	end
	if entry.lastCollectionAt == nil then
		return false, "NotProducing"
	end

	local definition = MythlingsData[entry.typeId]
	if not definition then
		return false, "InvalidDefinition"
	end

	local amount = calculate(player, mythlingId)
	InventoryService.AddMaterial(player, definition.production.materialId, amount)
	entry.lastCollectionAt = os.time()
	InventoryService.MarkDirty(player)
	return true
end

function Accrual.Start(player: Player, mythlingId: string)
	local entry = getEntry(player, mythlingId)
	if entry then
		entry.lastCollectionAt = os.time()
		InventoryService.MarkDirty(player)
	end
end

function Accrual.Stop(player: Player, mythlingId: string)
	local entry = getEntry(player, mythlingId)
	if entry then
		entry.lastCollectionAt = nil
		InventoryService.MarkDirty(player)
	end
end

return Accrual
