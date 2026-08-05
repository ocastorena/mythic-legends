-- ServerScriptService/Services/ProductionService
-- Coordinates Material production while InventoryService remains the owner of
-- Consumables, Mythlings, and Materials.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimitUtil = require(Infrastructure:WaitForChild("RateLimitUtil"))

local Accrual = require(script.Accrual)

local ProductionService = {}
local getStatus: RemoteFunction
local collect: RemoteFunction
local requestLimiter = RateLimitUtil.new(8, 3)
local removingConnection: RBXScriptConnection?

function ProductionService.Init(context)
	Accrual.Init(context.Services.InventoryService, context.Configurations.Mythlings)
	getStatus = context.Remotes.Production.GetStatus
	collect = context.Remotes.Production.Collect
end

function ProductionService.Start()
	getStatus.OnServerInvoke = function(player: Player, mythlingId: unknown)
		if not requestLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if type(mythlingId) ~= "string" or #mythlingId == 0 or #mythlingId > 128 then
			return { ok = false, code = "InvalidMythlingId" }
		end
		local status = ProductionService.GetProduction(player, mythlingId)
		if not status then
			return { ok = false, code = "NotAvailable" }
		end
		return { ok = true, value = status }
	end
	collect.OnServerInvoke = function(player: Player, mythlingId: unknown)
		if not requestLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if type(mythlingId) ~= "string" or #mythlingId == 0 or #mythlingId > 128 then
			return { ok = false, code = "InvalidMythlingId" }
		end
		local collected, code = ProductionService.CollectProduction(player, mythlingId)
		return if collected then { ok = true } else { ok = false, code = code or "CollectFailed" }
	end
	removingConnection = Players.PlayerRemoving:Connect(function(player)
		requestLimiter:Forget(player)
	end)
end

function ProductionService.Stop()
	getStatus.OnServerInvoke = nil
	collect.OnServerInvoke = nil
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	requestLimiter:Clear()
end

function ProductionService.GetProduction(player: Player, mythlingId: string): Accrual.ProductionStatus?
	return Accrual.Get(player, mythlingId)
end

function ProductionService.CollectProduction(player: Player, mythlingId: string): (boolean, string?)
	return Accrual.Collect(player, mythlingId)
end

function ProductionService.StartProduction(player: Player, mythlingId: string)
	Accrual.Start(player, mythlingId)
end

function ProductionService.StopProduction(player: Player, mythlingId: string)
	Accrual.Stop(player, mythlingId)
end

return ProductionService
