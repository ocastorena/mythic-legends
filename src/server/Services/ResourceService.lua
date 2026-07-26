-- ServerScriptService/Services/ResourceService
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = ReplicatedStorage:WaitForChild("Util")
local PlayerUtil = require(Util:WaitForChild("PlayerUtil"))
local LogUtil = require(Util:WaitForChild("LogUtil"))

local log = LogUtil.For("ResourceService")

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

local ResourceService = {}

function ResourceService.Init(context)
	DataService = context.Services.DataService

	ResourcesEvent = context.Remotes.ResourcesEvent
	ResourcesRequest = context.Remotes.ResourcesRequest
	ResourcesMeta = context.Metadata.Resources

	log.info("Initialized")
end

function ResourceService.Start()
	PlayerUtil.OnPlayer(function(player: Player)
		local resources = DataService.GetSection(player, "resources")
		CacheByPlayer[player.UserId] = { resources = resources }
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	ResourcesRequest.OnServerInvoke = handleResourcesRequest

	log.info("Started")
end

return ResourceService
