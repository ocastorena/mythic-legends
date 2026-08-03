-- ServerScriptService/ServerModules/Services/CurrencyService
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("ServerModules"):WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))

local log = LogUtil.For("CurrencyService")

local DataManager = nil

local CurrencyEvent: RemoteEvent = nil

-- cache CacheByPlayer[userId] = {currency}
local CacheByPlayer = {}

local function setupRunies(userId: number): boolean
	local cache = CacheByPlayer[userId]
	if not cache.currency then
		log.warn("Player cache not found")
		return false
	end

	if not cache.currency.runies then
		cache.currency.runies = 0
		log.debug("First-time runies setup")
		return true
	end

	return false
end

local CurrencyService = {}

function CurrencyService.Init(context)
	DataManager = context.Services.DataManager
	CurrencyEvent = context.Remotes.CurrencyEvent

	log.info("Initialized")
end

function CurrencyService.Start()
	PlayerUtil.OnPlayer(function(player: Player)
		local currency = DataManager.GetSection(player, "currency")
		CacheByPlayer[player.UserId] = { currency = currency }
		-- setup runies if first time
		if setupRunies(player.UserId) then
			DataManager.MarkDirty(player)
		end

		CurrencyEvent:FireClient(player, "RuniesUpdate", CacheByPlayer[player.UserId].currency.runies)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	log.info("Started")
end

return CurrencyService
