-- ServerScriptService/Services/ProductionService/ProductionRemotes
-- Preserves the current MythlingsRequest API while production moves to its own service.

local ProductionRemotes = {}

local ProductionService: any
local InventoryService: any
local MythlingsRequest: RemoteFunction

function ProductionRemotes.Init(context, productionService)
	ProductionService = productionService
	InventoryService = context.Services.InventoryService
	MythlingsRequest = context.Remotes.MythlingsRequest
end

function ProductionRemotes.Start()
	MythlingsRequest.OnServerInvoke = function(player: Player, action: string, payload: any)
		if action == "GetMythlings" then
			return InventoryService.ListMythlings(player)
		end

		if type(payload) ~= "table" then
			return
		end

		if action == "GetProduction" then
			return ProductionService.GetProduction(player, payload.mythlingId)
		end
		if action == "CollectProduction" then
			ProductionService.CollectProduction(player, payload.mythlingId)
		end
	end
end

return ProductionRemotes
