--!strict
-- ServerScriptService/Services/CraftingService
-- Owns admitted crafting endpoints and automatic receipt resolution, never Station presentation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local Crafting = require(ReplicatedStorage.Shared.Configurations.Crafting)
local CraftingRequestsConfiguration =
	require(ReplicatedStorage.Shared.Configurations.CraftingRequests)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local LogUtil = require(ServerScriptService.Infrastructure.LogUtil)
local CraftingJobs = require(script.CraftingJobs)
local CraftingCommands = require(script.CraftingCommands)
local CraftingRequests = require(script.CraftingRequests)
local DueJobs = require(script.DueJobs)

local CraftingService = {}
local lifecycle = ServiceLifecycle.new("CraftingService")
local log = LogUtil.For("CraftingService")
local commands: CraftingCommands.CraftingCommands?
local scheduler: DueJobs.DueJobs?
local requests: CraftingRequests.Requests?
local limiter: RateLimiter.RateLimiter?
local getStationRemote: RemoteFunction?
local startJobRemote: RemoteFunction?
local cancelJobRemote: RemoteFunction?

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

function CraftingService.Init(context: ServerTypes.Context)
	local DataService = context.Services.DataService
	local BaseService = context.Services.BaseService
	assert(
		type(BaseService) == "table" and type(BaseService.CheckCraftingAccess) == "function",
		"[CraftingService] BaseService.CheckCraftingAccess required"
	)
	local burst = CraftingRequestsConfiguration.requestBurst
	local refill = CraftingRequestsConfiguration.requestRefillPerSecond
	assert(
		type(burst) == "number"
			and burst >= 1
			and burst < math.huge
			and burst % 1 == 0
			and type(refill) == "number"
			and refill > 0
			and refill < math.huge,
		"[CraftingService] Invalid Crafting request tuning"
	)
	local requestLimiter = RateLimiter.new(burst, refill)
	limiter = requestLimiter
	local jobs = CraftingJobs.new()
	commands = CraftingCommands.new(
		DataService,
		jobs,
		nil,
		function(player, data, stationInstanceId)
			return BaseService.CheckCraftingAccess(player, data.base, stationInstanceId)
		end
	)
	getStationRemote = context.Remotes.Crafting.GetStation
	startJobRemote = context.Remotes.Crafting.StartJob
	cancelJobRemote = context.Remotes.Crafting.CancelJob
	requests = CraftingRequests.new({
		isAvailable = available,
		allowRequest = function(player: Player): boolean
			return requestLimiter:Allow(player)
		end,
		getStation = function(player: Player, input: unknown): Types.CraftingStationViewResult
			-- CraftingCommands validates the complete envelope at this untrusted API boundary.
			return CraftingService.GetStation(player, input :: Types.GetCraftingStationRequest)
		end,
		startJob = function(player: Player, input: unknown): Types.TransactionResult
			return CraftingService.StartJob(player, input :: Types.StartCraftingRequest)
		end,
		cancelJob = function(player: Player, input: unknown): Types.TransactionResult
			return CraftingService.CancelJob(player, input :: Types.CancelCraftingRequest)
		end,
	})
	-- These pure closures remain valid during DataService's final release even after Stop.
	DataService.RegisterMutationPreparation("Crafting", jobs.SettleDueToDraft)
	DataService.RegisterProfileSettlement("Crafting", function(draft, now)
		return jobs.SettleDueToDraft(draft, now)
	end)
	scheduler = DueJobs.new(
		DataService,
		function()
			return Players:GetPlayers()
		end,
		Crafting.resolutionIntervalSeconds,
		nil,
		function(player, code)
			log.error(`Crafting settlement failed for userId {player.UserId}`, code)
		end
	)
end

function CraftingService.Start()
	if not lifecycle:Start() then
		return
	end
	local timer = scheduler
	assert(timer, "[CraftingService] Init must precede Start")
	local handler = assert(requests, "[CraftingService] Crafting requests are not initialized")
	local requestLimiter = assert(limiter, "[CraftingService] Request limiter is not initialized")
	local getRemote =
		assert(getStationRemote, "[CraftingService] GetStation remote is not initialized")
	local startRemote =
		assert(startJobRemote, "[CraftingService] StartJob remote is not initialized")
	local cancelRemote =
		assert(cancelJobRemote, "[CraftingService] CancelJob remote is not initialized")
	getRemote.OnServerInvoke = handler.GetStation
	startRemote.OnServerInvoke = handler.StartJob
	cancelRemote.OnServerInvoke = handler.CancelJob
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		requestLimiter:Forget(player)
	end)
	lifecycle.trove:Connect(RunService.Heartbeat, timer.Step)
end

function CraftingService.Stop()
	if not lifecycle:Stop() then
		return
	end
	if getStationRemote then
		RemoteUtil.ClearServerHandler(getStationRemote)
	end
	if startJobRemote then
		RemoteUtil.ClearServerHandler(startJobRemote)
	end
	if cancelJobRemote then
		RemoteUtil.ClearServerHandler(cancelJobRemote)
	end
	if limiter then
		limiter:Clear()
	end
	commands = nil
	scheduler = nil
	requests = nil
	limiter = nil
end

function CraftingService.GetStation(
	player: Player,
	request: Types.GetCraftingStationRequest
): Types.CraftingStationViewResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.GetStation(player, request)
end

function CraftingService.StartJob(
	player: Player,
	request: Types.StartCraftingRequest
): Types.TransactionResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.Start(player, request)
end

function CraftingService.CancelJob(
	player: Player,
	request: Types.CancelCraftingRequest
): Types.TransactionResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.Cancel(player, request)
end

return CraftingService
