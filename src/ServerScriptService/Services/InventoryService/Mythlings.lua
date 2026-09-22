--!strict
-- ServerScriptService/Services/InventoryService/Mythlings
-- Owns the player's mythling records. Production timing is owned by ProductionService.

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local log = LogUtil.For("InventoryService.Mythlings")

local ServerTypes = require(game:GetService("ServerScriptService").Domain.Types)

local Mythlings = {}

local DataService: ServerTypes.DataApi
local sessionsByUserId: ServerTypes.InventorySessions

local function makeId(): string
	return `myth_{HttpService:GenerateGUID(false)}`
end

local function getOwned(player: Player)
	local session = sessionsByUserId[player.UserId]
	return session and session.mythlings or nil
end

local function getOwnedEntry(player: Player, mythlingId: unknown): Types.MythlingEntry?
	if type(mythlingId) ~= "string" then
		return nil
	end
	local owned = getOwned(player)
	return owned and owned[mythlingId] or nil
end

function Mythlings.Init(
	serviceContext: ServerTypes.Context,
	sessions: ServerTypes.InventorySessions
)
	DataService = serviceContext.Services.DataService
	sessionsByUserId = sessions
end

function Mythlings.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.mythlings = DataService.GetData(player).mythlings
end

function Mythlings.SaveWon(player: Player, params: { typeId: string, variantId: string }): string?
	assert(player and player.UserId, "[InventoryService.Mythlings] invalid player")
	assert(params, "[InventoryService.Mythlings] params required")

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

	if not DataService.MarkDirty(player) then
		list[id] = nil
		log.warn(`Profile became unavailable while granting Mythling to userId {player.UserId}`)
		return nil
	end
	DataService.SaveNow(player)
	return id
end

function Mythlings.Remove(player: Player, mythlingId: string): boolean
	assert(player and player.UserId, "[InventoryService.Mythlings] invalid player")

	local list = getOwned(player)
	if not (list and type(mythlingId) == "string" and list[mythlingId]) then
		return false
	end

	list[mythlingId] = nil
	DataService.MarkDirty(player)
	DataService.SaveNow(player)
	return true
end

function Mythlings.Get(player: Player, mythlingId: string): Types.MythlingEntry?
	assert(player and player.UserId, "[InventoryService.Mythlings] invalid player")
	return getOwnedEntry(player, mythlingId)
end

return Mythlings
