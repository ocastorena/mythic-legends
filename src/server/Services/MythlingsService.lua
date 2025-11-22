-- ServerScriptService/Services/MythlingsService.lua
-- Server-only service that manages a player's Mythlings.
-- Persistence is delegated to DataService (authoritative read/write).
local Players = game:GetService("Players")

local DataService = nil

local MythlingsEvent = nil
local MythlingsRequest = nil
local MythlingsData = nil

-- cache CacheByPlayer[userId] = {mythlings, mythlingsOnStands}
local CacheByPlayer = {}
-- ===================== helpers =====================

local function makeId(): string
	return string.format("%s%d%04x", "myth_", os.time(), math.random(0, 0xFFFF))
end

local function computeAccrual(player: Player, mythlingId: string)
	if not CacheByPlayer[player.UserId].mythlings[mythlingId] then
		return
	end

	local mythlingType = CacheByPlayer[player.UserId].mythlings[mythlingId].typeId
	if not mythlingType then
		return
	end

	local currentAmount = 0

	-- get rate (per minute) for mythling
	local rate = MythlingsData[mythlingType].production.baseRate
	-- get capacity for mythling
	local capacity = MythlingsData[mythlingType].production.baseCapacity
	-- get time elapsed from last collection
	local lastCollection = CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt
	if not lastCollection then
		return
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
	if action == "getMythlings" then
		return CacheByPlayer[player.UserId].mythlings
	end
	if action == "GetProduction" then
		local production, capacity, rate = computeAccrual(player, payload.mythlingId)
		return { production = production, capacity = capacity, rate = rate }
	end
	if action == "CollectProduction" then
		local typeId = CacheByPlayer[player.UserId].mythlings[payload.mythlingId].typeId
		local resource = MythlingsData[typeId].production.resource
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
local MythlingsService = {}

function MythlingsService.SaveWonMythling(player: Player, params: any): string
	print("[MythlingsService] SaveWonMythling")
	assert(player and player.UserId, "[MythlingsService.SaveWonMythling] invalid player")
	assert(params, "[MythlingsService.SaveWonMythling] params required")

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
function MythlingsService.RemoveMythling(player: Player, mythlingId: string): boolean
	assert(player and player.UserId, "[MythlingsService.RemoveMythling] invalid player")
	assert(type(mythlingId) == "string", "[MythlingsService.RemoveMythling] mythlingId must be string")

	local list = CacheByPlayer[player.UserId].mythlings

	list[mythlingId] = nil
	DataService.SaveNow(player)
	return true
end

-- Lightweight list for UI grids (bandwidth-friendly).
-- Each row: { id, typeName, standIndex, claimedAt, thumbnailId? }
function MythlingsService.ListMythlings(player: Player): { any }
	assert(player and player.UserId, "[MythlingsService.ListMythlings] invalid player")

	local list = CacheByPlayer[player.UserId].mythlings
	return list
end

-- Fetch the full server entry (for systems that need details).
function MythlingsService.GetMythling(player: Player, mythlingId: string): any?
	assert(player and player.UserId, "[MythlingsService.GetMythling] invalid player")
	assert(type(mythlingId) == "string", "[MythlingsService.GetMythling] mythlingId must be string")

	local list = CacheByPlayer[player.UserId].mythlings
	return mythlingId and list[mythlingId] or nil
end

function MythlingsService.StartProduction(player: Player, mythlingId: string)
	if not CacheByPlayer[player.UserId] then
		return
	end
	if not CacheByPlayer[player.UserId].mythlings[mythlingId] then
		return
	end
	local time = os.time()
	CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt = time
end

function MythlingsService.StopProduction(player: Player, mythlingId: string)
	if not CacheByPlayer[player.UserId] then
		return
	end
	if not CacheByPlayer[player.UserId].mythlings[mythlingId] then
		return
	end
	CacheByPlayer[player.UserId].mythlings[mythlingId].lastCollectionAt = nil
end

function MythlingsService.Init(context)
	DataService = context.Services.DataService

	MythlingsEvent = context.Remotes.MythlingsEvent
	MythlingsRequest = context.Remotes.MythlingsRequest
	MythlingsData = context.Metadata.Mythlings

	MythlingsEvent.OnServerEvent:Connect(function(player, event, msg)
		if event == "Delete" then
			local result = MythlingsService.RemoveMythling(player, msg)
			if result then
				local list = MythlingsService.ListMythlings(player)
				MythlingsEvent:FireClient(player, "Update", list)
			end
		end
	end)

	print("[MythlingsService] Initialized")
end

function MythlingsService.Start()
	Players.PlayerAdded:Connect(function(player: Player)
		local mythlings = DataService.GetSection(player, "mythlings")
		print("mythlings:", mythlings)
		CacheByPlayer[player.UserId] = { mythlings = mythlings }
		print("mythlings:", CacheByPlayer[player.UserId].mythlings)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	MythlingsRequest.OnServerInvoke = handleMythlingsRequest

	print("[MythlingsService] Started")
end

return MythlingsService
