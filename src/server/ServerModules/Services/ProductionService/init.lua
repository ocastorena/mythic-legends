-- ServerScriptService/ServerModules/Services/ProductionService
-- Coordinates Material production while InventoryService remains the owner of
-- Consumables, Mythlings, and Materials.

local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("ServerModules"):WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))

local Accrual = require(script.Accrual)
local ProductionRemotes = require(script.ProductionRemotes)

local log = LogUtil.For("ProductionService")
local ProductionService = {}

function ProductionService.Init(context)
	Accrual.Init(context.Services.InventoryService, context.Metadata.Mythlings)
	ProductionRemotes.Init(context, ProductionService)

	log.info("Initialized")
end

function ProductionService.Start()
	ProductionRemotes.Start()
	log.info("Started")
end

function ProductionService.GetProduction(player: Player, mythlingId: any): any?
	return Accrual.Get(player, mythlingId)
end

function ProductionService.CollectProduction(player: Player, mythlingId: any)
	Accrual.Collect(player, mythlingId)
end

function ProductionService.StartProduction(player: Player, mythlingId: string)
	Accrual.Start(player, mythlingId)
end

function ProductionService.StopProduction(player: Player, mythlingId: string)
	Accrual.Stop(player, mythlingId)
end

return ProductionService
