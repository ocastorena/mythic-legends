local ProductionService = {}

-- Roblox services
local Players = game:GetService("Players")


-- Context passed from Bootstrap (holds Config, Instances, Remotes, etc.)
local DataService = nil

local MythlingsData = nil

local ProductionEvent = nil

local ProductionRequest = nil

-- Cache
local playerCache = {}

-- Utilities
local function computeAccrual(player: Player, mythlingId: string)
	
	if not playerCache[player][mythlingId] then return end

	local mythlingType = playerCache[player][mythlingId].typeId
	if not mythlingType then return end
	
	local currentAmount = 0
	
	-- get rate (per minute) for mythling
	local rate = MythlingsData[mythlingType].production.baseRate
	-- get capacity for mythling
	local capacity = MythlingsData[mythlingType].production.baseCapacity
	-- get time elapsed from last collection
	local lastCollection = playerCache[player][mythlingId].lastCollection
	if not lastCollection then return end
	
	local timeElapsed = tick() - lastCollection
	
	-- calculate and return currentAmount
	currentAmount = rate * timeElapsed / 60
	-- clamp to max capacity
	if currentAmount > capacity then
		currentAmount = capacity
	end
	
	-- round to the lower whole number
	currentAmount = math.floor(currentAmount)
	
	--print(`Mythling {mythlingId} generated {currentAmount} {MythlingsData[mythlingType].production.resource}`)
	return currentAmount, capacity, rate
end

local function getMythlingsOnStands(player: Player)
	local stands = DataService.GetSection(player, "base").stands
	local mythlings = DataService.GetSection(player, "mythlings")
	local mythlingsOnStands = {}
	for _, mythlingId in pairs(stands) do
		local mythling = mythlings[mythlingId]
		if mythling then
			mythlingsOnStands[mythlingId] = mythling
		end
	end
	playerCache[player] = mythlingsOnStands
end

local function handlePlayerAdded(player: Player)
	getMythlingsOnStands(player)
	print("mythlingsOnStands:", playerCache[player])
end

local function handlePlayerRemoved(player: Player)
	-- TODO: Clean up player state
end

local function handleProductionEvent(player: Player, action: string, payload: any)
	if action == "GetProduction" then
		computeAccrual(player, payload.mythlingId)
	end
end

local function handleProductionRequest(player: Player, action: string, payload: any)
	if action == "GetProduction" then
		local production, capacity, rate = computeAccrual(player, payload.mythlingId)
		return {production = production, capacity = capacity, rate = rate}
	end
	if action == "CollectProduction" then
		local typeId = playerCache[player][payload.mythlingId].typeId
		local resource = MythlingsData[typeId].production.resource
		local production, capacity, rate = computeAccrual(player, payload.mythlingId)
		local resources = DataService.GetSection(player, "resources")
		if not resources[resource] then
			resources[resource] = {total = production}
		else
			resources[resource].total += production
		end
		local time = tick()
		playerCache[player][payload.mythlingId].lastCollection = time
	end
end

-- Public API
function ProductionService.StartProduction(player: Player, mythlingId: string)
	if not playerCache[player] then return end
	getMythlingsOnStands(player)
	if not playerCache[player][mythlingId] then return end
	local time = tick()
	playerCache[player][mythlingId].lastCollection = time
	--local mythlings = DataService.GetSection(player, "mythlings")
	--mythlings[mythlingId].lastCollection = time
end

function ProductionService.StopProduction(player: Player, mythlingId: string)
	if not playerCache[player] then return end
	playerCache[player][mythlingId] = nil
	--local mythlings = DataService.GetSection(player, "mythlings")
	--mythlings[mythlingId].lastCollection = nil
end

function ProductionService.UpdateLastCollection(player: Player, mythlingId: string)
	if not playerCache[player] then return end
	local time = tick()
	playerCache[player][mythlingId].lastCollection = time
	--local mythlings = DataService.GetSection(player, "mythlings")
	--mythlings[mythlingId].lastCollection = time
end

function ProductionService.Init(context)
	DataService = context.Services.DataService
	
	MythlingsData = context.Metadata.MythlingsData
	
	ProductionEvent   = context.Remotes.ProductionEvent
	ProductionRequest = context.Remotes.ProductionRequest
end

function ProductionService.Start()
	Players.PlayerAdded:Connect(handlePlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoved)
	ProductionEvent.OnServerEvent:Connect(handleProductionEvent)
	
	ProductionRequest.OnServerInvoke = handleProductionRequest
end

return ProductionService
