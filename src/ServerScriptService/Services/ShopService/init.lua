--!strict
-- ServerScriptService/Services/ShopService
-- Owns headless Shop views and purchases; refresh derives from shared server time, not a timer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local ShopCatalog = require(script.ShopCatalog)
local ShopCommands = require(script.ShopCommands)

local ShopService = {}
local lifecycle = ServiceLifecycle.new("ShopService")
local commands: ShopCommands.ShopCommands?

function ShopService.Init(context: ServerTypes.Context)
	local valid, problem = ShopCatalog.ValidateLaunch()
	assert(valid, `[ShopService] Invalid Shop catalogue: {tostring(problem)}`)
	commands = ShopCommands.new(context.Services.DataService)
end

function ShopService.Start()
	if not lifecycle:Start() then
		return
	end
	assert(commands, "[ShopService] Init must precede Start")
end

function ShopService.Stop()
	if not lifecycle:Stop() then
		return
	end
	commands = nil
end

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
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
