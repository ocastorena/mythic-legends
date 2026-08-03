-- ServerScriptService/ServerModules/Services/ProductionService/Accrual
-- Calculates a stationed mythling's stored production and transfers collected Materials
-- through InventoryService.

local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("ServerModules"):WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("ProductionService")

local Accrual = {}

local InventoryService: any
local MythlingsData: any

local function getEntry(player: Player, mythlingId: any)
	if type(mythlingId) ~= "string" then
		return nil
	end
	return InventoryService.GetMythling(player, mythlingId)
end

local function calculate(player: Player, mythlingId: string)
	local entry = getEntry(player, mythlingId)
	if not entry then
		log.debug(`mythlingId {tostring(mythlingId)} not found for userId {player.UserId}`)
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
		entry.lastCollectionAt = os.time()
		InventoryService.MarkDirty(player)
		return 0, capacity, rate
	end

	local currentAmount = rate * (os.time() - lastCollection) / 60
	return math.floor(math.min(currentAmount, capacity)), capacity, rate
end

function Accrual.Init(inventoryService, mythlingsData)
	InventoryService = inventoryService
	MythlingsData = mythlingsData
end

function Accrual.Get(player: Player, mythlingId: any): any?
	if not getEntry(player, mythlingId) then
		return nil
	end

	local production, capacity, rate = calculate(player, mythlingId)
	return { production = production, capacity = capacity, rate = rate }
end

function Accrual.Collect(player: Player, mythlingId: any)
	local entry = getEntry(player, mythlingId)
	if not entry then
		return
	end

	local definition = MythlingsData[entry.typeId]
	if not definition then
		return
	end

	local amount = calculate(player, mythlingId)
	InventoryService.AddMaterial(player, definition.production.materialId, amount)
	entry.lastCollectionAt = os.time()
	InventoryService.MarkDirty(player)
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
