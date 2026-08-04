-- ServerScriptService/Services/ProductionService
-- Coordinates Material production while InventoryService remains the owner of
-- Consumables, Mythlings, and Materials.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local RateLimitUtil = require(Infrastructure:WaitForChild("RateLimitUtil"))

local Accrual = require(script.Accrual)

local log = LogUtil.For("ProductionService")
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
		ProductionService.CollectProduction(player, mythlingId)
		return { ok = true }
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
