-- ServerScriptService/Services/MythlingService
-- Server-only service that manages a player's Mythlings.
-- Persistence is delegated to DataService (authoritative read/write).
local Players = game:GetService("Players")

local DataService = nil

local MythlingsEvent = nil
local MythlingsRequest = nil
local MythlingsData = nil

-- cache CacheByPlayer[userId] = {mythlings}
local CacheByPlayer = {}
-- ===================== helpers =====================

local function makeId(): string
	return string.format("%s%d%04x", "myth_", os.time(), math.random(0, 0xFFFF))
end

local function computeAccrual(player: Player, mythlingId: string)
	if not CacheByPlayer[player.UserId].mythlings[mythlingId] then
		print(`[MythlingService] mythlingId {mythlingId} not found in cache for userId {player.UserId}`)
		return 0, 0, 0
	end

	local mythlingType = CacheByPlayer[player.UserId].mythlings[mythlingId].typeId
	if not mythlingType then
		print(`[MythlingService] typeId {mythlingType} not found for mythlingId {mythlingId}`)
		return 0, 0, 0
	end

	local currentAmount = 0

	-- get rate (per minute) for mythling
	local rate = MythlingsData[mythlingType].production.baseRate
	-- get capacity for mythling
	local capacity = MythlingsData[mythlingType].production.baseCapacity
	-- get time elapsed from last collection
	local lastCollection = CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt
	if not lastCollection then
		-- If production hasn't been started yet, initialize it now and report zero accrued at base rate/capacity.
		local now = os.time()
		CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt = now
		return 0, capacity, rate
	end

	local timeElapsed = os.time() - lastCollection

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

local function handleMythlingsRequest(player: Player, action: string, payload: any)
	if action == "GetMythlings" then
		return CacheByPlayer[player.UserId].mythlings
	end
	if action == "GetProduction" then
		local production, capacity, rate = computeAccrual(player, payload.mythlingId)
		return { production = production, capacity = capacity, rate = rate }
	end
	if action == "CollectProduction" then
		local typeId = CacheByPlayer[player.UserId].mythlings[payload.mythlingId].typeId
		local resource = MythlingsData[typeId].production.resourceId
		local production, capacity, rate = computeAccrual(player, payload.mythlingId)
		local resources = DataService.GetSection(player, "resources")
		if not resources[resource] then
			resources[resource] = { total = production }
		else
			resources[resource].total += production
		end
		local time = os.time()
		CacheByPlayer[player.UserId].mythlings[payload.mythlingId].lastCollectionAt = time
	end
	return
end

-- ===================== public API =====================
local MythlingService = {}

function MythlingService.SaveWonMythling(player: Player, params: any): string
	print("[MythlingService] SaveWonMythling")
	assert(player and player.UserId, "[MythlingService.SaveWonMythling] invalid player")
	assert(params, "[MythlingService.SaveWonMythling] params required")

	local list = CacheByPlayer[player.UserId].mythlings
	local id = makeId()
	local entry = {
		typeId = params.typeId,
		variantId = params.variantId,
		claimedAt = os.time(),
	}

	list[id] = entry
	print("cache:", CacheByPlayer[player.UserId].mythlings)
	DataService.SaveNow(player)
	return id
end

-- Delete an inventory entry by id (used by your side-panel Delete).
function MythlingService.RemoveMythling(player: Player, mythlingId: string): boolean
	assert(player and player.UserId, "[MythlingService.RemoveMythling] invalid player")
	assert(type(mythlingId) == "string", "[MythlingService.RemoveMythling] mythlingId must be string")

	local list = CacheByPlayer[player.UserId].mythlings

	list[mythlingId] = nil
	DataService.SaveNow(player)
	return true
end

-- Lightweight list for UI grids (bandwidth-friendly).
-- Each row: { id, typeName, standIndex, claimedAt, thumbnailId? }
function MythlingService.ListMythlings(player: Player): { any }
	assert(player and player.UserId, "[MythlingService.ListMythlings] invalid player")

	local list = CacheByPlayer[player.UserId].mythlings
	return list
end

-- Fetch the full server entry (for systems that need details).
function MythlingService.GetMythling(player: Player, mythlingId: string): any?
	assert(player and player.UserId, "[MythlingService.GetMythling] invalid player")
	assert(type(mythlingId) == "string", "[MythlingService.GetMythling] mythlingId must be string")

	local list = CacheByPlayer[player.UserId].mythlings
	return mythlingId and list[mythlingId] or nil
end

function MythlingService.StartProduction(player: Player, mythlingId: string)
	if not CacheByPlayer[player.UserId] then
		return
	end
	if not CacheByPlayer[player.UserId].mythlings[mythlingId] then
		return
	end
	local time = os.time()
	CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt = time
end

function MythlingService.StopProduction(player: Player, mythlingId: string)
	if not CacheByPlayer[player.UserId] then
		return
	end
	if not CacheByPlayer[player.UserId].mythlings[mythlingId] then
		return
	end
	CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt = nil
end

function MythlingService.Init(context)
	DataService = context.Services.DataService

	MythlingsEvent = context.Remotes.MythlingsEvent
	MythlingsRequest = context.Remotes.MythlingsRequest
	MythlingsData = context.Metadata.Mythlings

	MythlingsEvent.OnServerEvent:Connect(function(player, event, msg)
		if event == "Delete" then
			local result = MythlingService.RemoveMythling(player, msg)
			if result then
				local list = MythlingService.ListMythlings(player)
				MythlingsEvent:FireClient(player, "Update", list)
			end
		end
	end)

	print("[MythlingService] Initialized")
end

function MythlingService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		local mythlings = DataService.GetSection(player, "mythlings")
		CacheByPlayer[player.UserId] = { mythlings = mythlings }
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	MythlingsRequest.OnServerInvoke = handleMythlingsRequest

	print("[MythlingService] Started")
end

return MythlingService
