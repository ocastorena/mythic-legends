--!strict
-- ServerScriptService/Services/ProductionService
-- Coordinates saved stand production and collection into the loaded player's inventory.

local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local Players = game:GetService("Players")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))

local Accrual = require(script.Accrual)
local ServerTypes = require(ServerScriptService.Domain.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("ProductionService")
local accrual: Accrual.Accrual

local ProductionService = {}
local getStatus: RemoteFunction
local collect: RemoteFunction
local requestLimiter = RateLimiter.new(8, 3)

function ProductionService.Init(serviceContext: ServerTypes.Context)
	accrual = Accrual.new(
		serviceContext.Services.DataService,
		serviceContext.Configurations.Mythlings,
		function(player, standId)
			return serviceContext.Services.BaseService.HasStand(player, standId)
		end
	)
	getStatus = serviceContext.Remotes.Production.GetStatus
	collect = serviceContext.Remotes.Production.Collect
end

local function validStandId(standId: unknown): boolean
	return type(standId) == "number" and standId % 1 == 0 and standId >= 0 and standId <= 128
end

function ProductionService.Start()
	if not lifecycle:Start() then
		return
	end
	getStatus.OnServerInvoke = function(
		player: Player,
		standId: unknown
	): {
		ok: boolean,
		code: string?,
		value: Accrual.ProductionStatus?,
	}
		if not requestLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if type(standId) ~= "number" or not validStandId(standId) then
			return { ok = false, code = "InvalidStandId" }
		end
		local status = ProductionService.GetProduction(player, standId)
		if not status then
			return { ok = false, code = "NotAvailable" }
		end
		return { ok = true, value = status }
	end
	collect.OnServerInvoke = function(
		player: Player,
		standId: unknown
	): {
		ok: boolean,
		code: string?,
		value: Accrual.ProductionCollection?,
	}
		if not requestLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if type(standId) ~= "number" or not validStandId(standId) then
			return { ok = false, code = "InvalidStandId" }
		end
		local collected, code, value = ProductionService.CollectProduction(player, standId)
		return if collected
			then { ok = true, value = value }
			else { ok = false, code = code or "CollectFailed" }
	end
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		requestLimiter:Forget(player)
	end)
end

function ProductionService.Stop()
	if not lifecycle:Stop() then
		return
	end
	RemoteUtil.ClearServerHandler(getStatus)
	RemoteUtil.ClearServerHandler(collect)
	requestLimiter:Clear()
end

function ProductionService.GetProduction(player: Player, standId: number): Accrual.ProductionStatus?
	return accrual.Get(player, standId)
end

function ProductionService.CollectProduction(
	player: Player,
	standId: number
): (boolean, string?, Accrual.ProductionCollection?)
	return accrual.Collect(player, standId)
end

function ProductionService.SettleProduction(player: Player, standId: number): (boolean, string?)
	return accrual.Settle(player, standId)
end

return ProductionService
