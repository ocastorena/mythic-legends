--!strict
-- ServerScriptService/Services/ShopService
-- Owns Shop commands and admitted endpoints; refresh derives from shared time, not a timer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local ShopRequestsConfiguration = require(ReplicatedStorage.Shared.Configurations.ShopRequests)
local ShopCatalog = require(script.ShopCatalog)
local ShopCommands = require(script.ShopCommands)
local ShopRequests = require(script.ShopRequests)

local ShopService = {}
local lifecycle = ServiceLifecycle.new("ShopService")
local commands: ShopCommands.ShopCommands?
local requests: ShopRequests.Requests?
local limiter: RateLimiter.RateLimiter?
local getShopRemote: RemoteFunction?
local buyOfferRemote: RemoteFunction?

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

function ShopService.Init(context: ServerTypes.Context)
	local valid, problem = ShopCatalog.ValidateLaunch()
	assert(valid, `[ShopService] Invalid Shop catalogue: {tostring(problem)}`)
	local burst = ShopRequestsConfiguration.requestBurst
	local refill = ShopRequestsConfiguration.requestRefillPerSecond
	assert(
		type(burst) == "number"
			and burst >= 1
			and burst < math.huge
			and burst % 1 == 0
			and type(refill) == "number"
			and refill > 0
			and refill < math.huge,
		"[ShopService] Invalid Shop request tuning"
	)
	local requestLimiter = RateLimiter.new(burst, refill)
	limiter = requestLimiter
	commands = ShopCommands.new(context.Services.DataService)
	getShopRemote = context.Remotes.Shop.GetShop
	buyOfferRemote = context.Remotes.Shop.BuyOffer
	requests = ShopRequests.new({
		isAvailable = available,
		allowRequest = function(player: Player): boolean
			return requestLimiter:Allow(player)
		end,
		getShop = function(player: Player): Types.ShopViewResult
			return ShopService.GetShop(player)
		end,
		buyOffer = function(player: Player, input: unknown): Types.TransactionResult
			-- ShopCommands validates every field at this untrusted-to-typed API boundary.
			return ShopService.BuyOffer(player, input :: Types.BuyShopOfferRequest)
		end,
	})
end

function ShopService.Start()
	if not lifecycle:Start() then
		return
	end
	assert(commands, "[ShopService] Init must precede Start")
	local handler = assert(requests, "[ShopService] Shop requests are not initialized")
	local requestLimiter = assert(limiter, "[ShopService] Shop request limiter is not initialized")
	local getRemote = assert(getShopRemote, "[ShopService] GetShop remote is not initialized")
	local buyRemote = assert(buyOfferRemote, "[ShopService] BuyOffer remote is not initialized")
	getRemote.OnServerInvoke = handler.Get
	buyRemote.OnServerInvoke = handler.Buy
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		requestLimiter:Forget(player)
	end)
end

function ShopService.Stop()
	if not lifecycle:Stop() then
		return
	end
	if getShopRemote then
		RemoteUtil.ClearServerHandler(getShopRemote)
	end
	if buyOfferRemote then
		RemoteUtil.ClearServerHandler(buyOfferRemote)
	end
	if limiter then
		limiter:Clear()
	end
	commands = nil
	requests = nil
	limiter = nil
end

function ShopService.GetShop(player: Player): Types.ShopViewResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.Get(player)
end

function ShopService.BuyOffer(
	player: Player,
	request: Types.BuyShopOfferRequest
): Types.TransactionResult
	local handler = commands
	if not handler or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return handler.Buy(player, request)
end

return ShopService
