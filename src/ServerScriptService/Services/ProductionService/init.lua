--!strict
-- ServerScriptService/Services/ProductionService
-- Owns prototype stand production and canonical Shrine accounting lifecycle/commands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))

local Accrual = require(script.Accrual)
local ShrineProduction = require(script.ShrineProduction)
local ShrineCollector = require(script.ShrineCollector)
local ProfileProduction = require(script.ProfileProduction)
local ProfileCheckpoints = require(script.ProfileCheckpoints)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("ProductionService")
local accrual: Accrual.Accrual
local shrineProduction: ShrineProduction.ShrineProduction?
local shrineCollector: ShrineCollector.ShrineCollector?
local checkpoints: ProfileCheckpoints.ProfileCheckpoints?
local log = LogUtil.For("ProductionService")

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
	shrineProduction = ShrineProduction.new(serviceContext.Services.DataService)
	shrineCollector = ShrineCollector.new(serviceContext.Services.DataService)
	serviceContext.Services.DataService.RegisterProfileSettlement(
		"Production",
		ProfileProduction.Settle
	)
	checkpoints = ProfileCheckpoints.new(
		serviceContext.Services.DataService,
		function()
			return Players:GetPlayers()
		end,
		Production.onlineCheckpointIntervalSeconds,
		function(player, code)
			log.error(`Profile checkpoint failed for userId {player.UserId}`, code)
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
	local scheduler = checkpoints
	assert(scheduler, "[ProductionService] Init must precede Start")
	lifecycle.trove:Connect(RunService.Heartbeat, scheduler.Step)
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
	shrineProduction = nil
	shrineCollector = nil
	checkpoints = nil
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

-- Server-only demand settlement, not a timer, save acknowledgement, or remote action.
-- A command that changes workers/inputs must settle on its OWN transaction draft instead of
-- calling this first: separate commits would break settlement-plus-mutation atomicity.
function ProductionService.SettleShrines(player: Player): Types.TransactionResult
	local production = shrineProduction
	if
		not lifecycle:IsRunning()
		or not production
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return production.Settle(player)
end

-- Server-only retryable command. This is not the retained prototype Collect remote.
function ProductionService.CollectShrine(
	player: Player,
	request: Types.CollectShrineRequest
): Types.TransactionResult
	local collector = shrineCollector
	if
		not lifecycle:IsRunning()
		or not collector
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return collector.Collect(player, request)
end

return ProductionService
