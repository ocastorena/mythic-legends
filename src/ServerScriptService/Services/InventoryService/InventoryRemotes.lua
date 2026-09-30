--!strict
-- ServerScriptService/Services/InventoryService/InventoryRemotes
-- Owns explicit Inventory endpoints and their shared admission budget, never Inventory mutations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local InventoryRequestsConfiguration =
	require(ReplicatedStorage.Shared.Configurations.InventoryRequests)
local InventoryRequests = require(script.Parent.InventoryRequests)
local lifecycle = ServiceLifecycle.new("InventoryRemotes")

local InventoryRemotes = {}
local network: Types.Network?
local requests: InventoryRequests.Requests?
local limiter: RateLimiter.RateLimiter?

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

function InventoryRemotes.Init(serviceContext: ServerTypes.Context)
	local burst = InventoryRequestsConfiguration.requestBurst
	local refill = InventoryRequestsConfiguration.requestRefillPerSecond
	assert(
		type(burst) == "number"
			and burst >= 1
			and burst < math.huge
			and burst % 1 == 0
			and type(refill) == "number"
			and refill > 0
			and refill < math.huge,
		"[InventoryService.InventoryRemotes] Invalid request tuning"
	)
	local requestLimiter = RateLimiter.new(burst, refill)
	local InventoryService = serviceContext.Services.InventoryService
	limiter = requestLimiter
	network = serviceContext.Remotes
	requests = InventoryRequests.new({
		isAvailable = available,
		allowRequest = function(player: Player): boolean
			return requestLimiter:Allow(player)
		end,
		commands = {
			-- Cast only at this untrusted-to-typed boundary; each canonical command validates
			-- its own closed envelope before submitting the revision-bound transaction.
			EvolveMythling = function(player: Player, input: unknown): Types.TransactionResult
				return InventoryService.EvolveMythling(player, input :: Types.EvolveMythlingRequest)
			end,
			SellMythling = function(player: Player, input: unknown): Types.TransactionResult
				return InventoryService.SellMythling(player, input :: Types.SellMythlingRequest)
			end,
			SellEquipment = function(player: Player, input: unknown): Types.TransactionResult
				return InventoryService.SellEquipment(player, input :: Types.SellEquipmentRequest)
			end,
			SellMaterial = function(player: Player, input: unknown): Types.TransactionResult
				return InventoryService.SellMaterial(player, input :: Types.SellMaterialRequest)
			end,
			DiscardMaterial = function(player: Player, input: unknown): Types.TransactionResult
				return InventoryService.DiscardMaterial(
					player,
					input :: Types.DiscardMaterialRequest
				)
			end,
			UpgradeCapacity = function(player: Player, input: unknown): Types.TransactionResult
				return InventoryService.UpgradeCapacity(
					player,
					input :: Types.UpgradeInventoryCapacityRequest
				)
			end,
		},
	})
end

function InventoryRemotes.Start()
	if not lifecycle:Start() then
		return
	end
	local remotes =
		assert(network, "[InventoryService.InventoryRemotes] Init must precede Start").Inventory
	local handler =
		assert(requests, "[InventoryService.InventoryRemotes] Requests are not initialized")
	local requestLimiter =
		assert(limiter, "[InventoryService.InventoryRemotes] Limiter is not initialized")
	remotes.EvolveMythling.OnServerInvoke = handler.EvolveMythling
	remotes.SellMythling.OnServerInvoke = handler.SellMythling
	remotes.SellEquipment.OnServerInvoke = handler.SellEquipment
	remotes.SellMaterial.OnServerInvoke = handler.SellMaterial
	remotes.DiscardMaterial.OnServerInvoke = handler.DiscardMaterial
	remotes.UpgradeCapacity.OnServerInvoke = handler.UpgradeCapacity
	remotes.DeleteMythling.OnServerInvoke = handler.DeleteMythling
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		requestLimiter:Forget(player)
	end)
end

function InventoryRemotes.Stop()
	if not lifecycle:Stop() then
		return
	end
	if network then
		local remotes = network.Inventory
		for _, remote in
			{
				remotes.EvolveMythling,
				remotes.SellMythling,
				remotes.SellEquipment,
				remotes.SellMaterial,
				remotes.DiscardMaterial,
				remotes.UpgradeCapacity,
				remotes.DeleteMythling,
			}
		do
			RemoteUtil.ClearServerHandler(remote)
		end
	end
	if limiter then
		limiter:Clear()
	end
	network = nil
	requests = nil
	limiter = nil
end

return InventoryRemotes
