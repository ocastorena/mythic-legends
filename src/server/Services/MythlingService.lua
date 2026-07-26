-- ServerScriptService/Services/MythlingService
-- Server-only service that manages a player's Mythlings.
-- Persistence is delegated to DataService (authoritative read/write).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = ReplicatedStorage:WaitForChild("Util")
local PlayerUtil = require(Util:WaitForChild("PlayerUtil"))
local LogUtil = require(Util:WaitForChild("LogUtil"))

local log = LogUtil.For("MythlingService")

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

--- The player's owned-mythling table, or nil if they have no cache entry yet. Every path
--- reachable from a remote must go through this: a request arriving before the join
--- handler ran would otherwise index a nil cache and error.
local function getOwned(player: Player)
	local cache = CacheByPlayer[player.UserId]
	return cache and cache.mythlings or nil
end

--- Looks up one owned mythling, validating the id came from the client as a string.
local function getOwnedEntry(player: Player, mythlingId: any)
	if type(mythlingId) ~= "string" then
		return nil
	end
	local owned = getOwned(player)
	return owned and owned[mythlingId] or nil
end

local function computeAccrual(player: Player, mythlingId: string)
	local entry = getOwnedEntry(player, mythlingId)
	if not entry then
		log.debug(`mythlingId {tostring(mythlingId)} not found for userId {player.UserId}`)
		return 0, 0, 0
	end

	local mythlingType = entry.typeId
	if not mythlingType or not MythlingsData[mythlingType] then
		log.warn(`Unknown typeId '{tostring(mythlingType)}' for mythlingId {mythlingId}`)
		return 0, 0, 0
	end

	local currentAmount = 0

	-- get rate (per minute) for mythling
	local rate = MythlingsData[mythlingType].production.baseRate
	-- get capacity for mythling
	local capacity = MythlingsData[mythlingType].production.baseCapacity
	-- get time elapsed from last collection
	local lastCollection = entry.lastCollectionAt
	if not lastCollection then
		-- If production hasn't been started yet, initialize it now and report zero accrued at base rate/capacity.
		entry.lastCollectionAt = os.time()
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
		return getOwned(player)
	end

	-- Everything below needs a mythling id from the client, so validate once here rather
	-- than dereferencing straight off the payload.
	if type(payload) ~= "table" then
		return
	end
	local entry = getOwnedEntry(player, payload.mythlingId)
	if not entry then
		return
	end

	if action == "GetProduction" then
		local production, capacity, rate = computeAccrual(player, payload.mythlingId)
		return { production = production, capacity = capacity, rate = rate }
	end

	if action == "CollectProduction" then
		local def = MythlingsData[entry.typeId]
		if not def then
			return
		end
		local resource = def.production.resourceId
		local production = computeAccrual(player, payload.mythlingId)

		local resources = DataService.GetSection(player, "resources")
		if not resources[resource] then
			resources[resource] = { total = production }
		else
			resources[resource].total += production
		end
		entry.lastCollectionAt = os.time()
	end
	return
end

-- ===================== public API =====================
local MythlingService = {}

function MythlingService.SaveWonMythling(player: Player, params: any): string?
	assert(player and player.UserId, "[MythlingService.SaveWonMythling] invalid player")
	assert(params, "[MythlingService.SaveWonMythling] params required")

	local list = getOwned(player)
	if not list then
		log.warn(`No cache for userId {player.UserId}; cannot save won mythling`)
		return nil
	end

	local id = makeId()
	list[id] = {
		typeId = params.typeId,
		variantId = params.variantId,
		claimedAt = os.time(),
	}

	log.debug(`Saved won mythling {id} for userId {player.UserId}`)
	DataService.SaveNow(player)
	return id
end

-- Delete an inventory entry by id (used by your side-panel Delete).
function MythlingService.RemoveMythling(player: Player, mythlingId: string): boolean
	assert(player and player.UserId, "[MythlingService.RemoveMythling] invalid player")

	-- mythlingId arrives straight off a remote, so validate rather than assert: an assert
	-- here lets any client raise a server-side error at will.
	local list = getOwned(player)
	if not (list and type(mythlingId) == "string" and list[mythlingId]) then
		return false
	end

	list[mythlingId] = nil
	DataService.SaveNow(player)
	return true
end

-- Lightweight list for UI grids (bandwidth-friendly).
-- Each row: { id, typeName, standIndex, claimedAt, thumbnailId? }
function MythlingService.ListMythlings(player: Player): { any }
	assert(player and player.UserId, "[MythlingService.ListMythlings] invalid player")
	return getOwned(player) or {}
end

-- Fetch the full server entry (for systems that need details).
function MythlingService.GetMythling(player: Player, mythlingId: string): any?
	assert(player and player.UserId, "[MythlingService.GetMythling] invalid player")
	return getOwnedEntry(player, mythlingId)
end

function MythlingService.StartProduction(player: Player, mythlingId: string)
	local entry = getOwnedEntry(player, mythlingId)
	if not entry then
		return
	end
	entry.lastCollectionAt = os.time()
end

function MythlingService.StopProduction(player: Player, mythlingId: string)
	local entry = getOwnedEntry(player, mythlingId)
	if not entry then
		return
	end
	entry.lastCollectionAt = nil
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

	log.info("Initialized")
end

function MythlingService.Start()
	PlayerUtil.OnPlayer(function(player: Player)
		local mythlings = DataService.GetSection(player, "mythlings")
		CacheByPlayer[player.UserId] = { mythlings = mythlings }
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		CacheByPlayer[player.UserId] = nil
	end)

	MythlingsRequest.OnServerInvoke = handleMythlingsRequest

	log.info("Started")
end

return MythlingService
