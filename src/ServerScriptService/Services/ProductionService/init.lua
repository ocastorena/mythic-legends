-- ServerScriptService/Services/ProductionService
-- Coordinates saved stand production and collection into the loaded player's inventory.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimiter = require(Infrastructure:WaitForChild("RateLimiter"))

local Accrual = require(script.Accrual)
local accrual

local ProductionService = {}
local getStatus: RemoteFunction
local collect: RemoteFunction
local requestLimiter = RateLimiter.new(8, 3)
local removingConnection: RBXScriptConnection?

function ProductionService.Init(context)
	accrual = Accrual.new(context.Services.DataService, context.Configurations.Mythlings, function(player, standId)
		return context.Services.BaseService.HasStand(player, standId)
	end)
	getStatus = context.Remotes.Production.GetStatus
	collect = context.Remotes.Production.Collect
end

local function validStandId(standId: unknown): boolean
	return type(standId) == "number" and standId % 1 == 0 and standId >= 0 and standId <= 128
end

function ProductionService.Start()
	getStatus.OnServerInvoke = function(player: Player, standId: unknown)
		if not requestLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if not validStandId(standId) then
			return { ok = false, code = "InvalidStandId" }
		end
		local status = ProductionService.GetProduction(player, standId)
		if not status then
			return { ok = false, code = "NotAvailable" }
		end
		return { ok = true, value = status }
	end
	collect.OnServerInvoke = function(player: Player, standId: unknown)
		if not requestLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if not validStandId(standId) then
			return { ok = false, code = "InvalidStandId" }
		end
		local collected, code, value = ProductionService.CollectProduction(player, standId)
		return if collected then { ok = true, value = value } else { ok = false, code = code or "CollectFailed" }
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

function ProductionService.GetProduction(player: Player, standId: number): Accrual.ProductionStatus?
	return accrual.Get(player, standId)
end

function ProductionService.CollectProduction(player: Player, standId: number): (boolean, string?, Accrual.ProductionCollection?)
	return accrual.Collect(player, standId)
end

function ProductionService.SettleProduction(player: Player, standId: number): (boolean, string?)
	return accrual.Settle(player, standId)
end

return ProductionService
