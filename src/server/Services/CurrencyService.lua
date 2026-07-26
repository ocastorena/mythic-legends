-- ServerScriptService/Services/CurrencyService
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = ReplicatedStorage:WaitForChild("Util")
local PlayerUtil = require(Util:WaitForChild("PlayerUtil"))
local LogUtil = require(Util:WaitForChild("LogUtil"))

local log = LogUtil.For("CurrencyService")

local DataService = nil

local CurrencyEvent: RemoteEvent = nil

-- cache CacheByPlayer[userId] = {currency}
local CacheByPlayer = {}

local function setupRunies(userId: number)
	local cache = CacheByPlayer[userId]
	if not cache.currency then
		log.warn("Player cache not found")
		return
	end

	if not cache.currency.runies then
		cache.currency.runies = 0
		log.debug("First-time runies setup")
		return
	end
end

local CurrencyService = {}

function CurrencyService.Init(context)
	DataService = context.Services.DataService
	CurrencyEvent = context.Remotes.CurrencyEvent

	log.info("Initialized")
end

function CurrencyService.Start()
	PlayerUtil.OnPlayer(function(player: Player)
		local currency = DataService.GetSection(player, "currency")
		CacheByPlayer[player.UserId] = { currency = currency }
		-- setup runies if first time
		setupRunies(player.UserId)

		CurrencyEvent:FireClient(player, "RuniesUpdate", CacheByPlayer[player.UserId].currency.runies)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	log.info("Started")
end

return CurrencyService
