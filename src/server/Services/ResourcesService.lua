local Players = game:GetService("Players")

local DataService = nil

local ResourcesEvent = nil
local ResourcesRequest = nil
local ResourcesMeta = nil

-- cache CacheByPlayer[userId] = {mythlings}
local CacheByPlayer = {}

local function handleResourcesRequest(player: Player, action: string, payload: any)
	if action == "GetResources" then
		return CacheByPlayer[player.UserId].resources
	end
	return
end

local ResourcesService = {}

function ResourcesService.Init(context)
	DataService = context.Services.DataService

	ResourcesEvent = context.Remotes.ResourcesEvent
	ResourcesRequest = context.Remotes.ResourcesRequest
	ResourcesMeta = context.Metadata.Resources

	print("[ResourcesService] Initialized")
end

function ResourcesService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		local resources = DataService.GetSection(player, "resources")
		CacheByPlayer[player.UserId] = { resources = resources }
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	ResourcesRequest.OnServerInvoke = handleResourcesRequest

	print("[ResourcesService] Started")
end

return ResourcesService
