-- ServerScriptService/ServerModules/Services/InventoryService/Mythlings
-- Owns the player's mythling records. Production timing is owned by ProductionService.

local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("ServerModules"):WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("InventoryService.Mythlings")

local Mythlings = {}

local DataManager: any
local sessionsByUserId: { [number]: any }

local function makeId(): string
	return string.format("%s%d%04x", "myth_", os.time(), math.random(0, 0xFFFF))
end

local function getOwned(player: Player)
	local session = sessionsByUserId[player.UserId]
	return session and session.mythlings or nil
end

local function getOwnedEntry(player: Player, mythlingId: any)
	if type(mythlingId) ~= "string" then
		return nil
	end
	local owned = getOwned(player)
	return owned and owned[mythlingId] or nil
end

function Mythlings.Init(context, sessions)
	DataManager = context.Services.DataManager
	sessionsByUserId = sessions
end

function Mythlings.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.mythlings = DataManager.GetSection(player, "mythlings")
end

function Mythlings.SaveWon(player: Player, params: any): string?
	assert(player and player.UserId, "[InventoryService.SaveWonMythling] invalid player")
	assert(params, "[InventoryService.SaveWonMythling] params required")

	local list = getOwned(player)
	if not list then
		log.warn(`No inventory session for userId {player.UserId}; cannot save won mythling`)
		return nil
	end

	local id = makeId()
	list[id] = {
		typeId = params.typeId,
		variantId = params.variantId,
		claimedAt = os.time(),
	}

	DataManager.MarkDirty(player)
	DataManager.SaveNow(player)
	return id
end

function Mythlings.Remove(player: Player, mythlingId: string): boolean
	assert(player and player.UserId, "[InventoryService.RemoveMythling] invalid player")

	local list = getOwned(player)
	if not (list and type(mythlingId) == "string" and list[mythlingId]) then
		return false
	end

	list[mythlingId] = nil
	DataManager.MarkDirty(player)
	DataManager.SaveNow(player)
	return true
end

function Mythlings.Get(player: Player, mythlingId: string): any?
	assert(player and player.UserId, "[InventoryService.GetMythling] invalid player")
	return getOwnedEntry(player, mythlingId)
end

return Mythlings
