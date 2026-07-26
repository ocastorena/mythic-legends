-- ServerScriptService/Services/CurrencyService
local Players = game:GetService("Players")

local DataService = nil

local CurrencyEvent: RemoteEvent = nil

-- cache CacheByPlayer[userId] = {currency}
local CacheByPlayer = {}

local function setupRunies(userId: number)
	local cache = CacheByPlayer[userId]
	if not cache.currency then
		error(`[CurrencyService] Player cache not found!`)
		return
	end

	if not cache.currency.runies then
		cache.currency.runies = 0
		print(`[CurrencyService] First time setup for runies`)
		return
	end
end

local CurrencyService = {}

function CurrencyService.Init(context)
	DataService = context.Services.DataService
	CurrencyEvent = context.Remotes.CurrencyEvent

	print("[CurrencyService] Initialized")
end

function CurrencyService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		local currency = DataService.GetSection(player, "currency")
		CacheByPlayer[player.UserId] = { currency = currency }
		-- setup runies if first time
		setupRunies(player.UserId)
		print("sending event")
		CurrencyEvent:FireClient(player, "RuniesUpdate", CacheByPlayer[player.UserId].currency.runies)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	print("[CurrencyService] Started")
end

return CurrencyService
