--!strict
-- ServerScriptService/Services/InventoryService/Mythlings
-- Owns the player's mythling records. Production timing is owned by ProductionService.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ServerTypes = require(ServerScriptService.Shared.Types)

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

function Mythlings.GetCapacity(player: Player): Types.InventoryCapacity?
	local data = DataService.GetLoadedData(player)
	local owned = getOwned(player)
	if not data or not owned or owned ~= data.mythlings then
		return nil
	end
	return InventoryCapacity.GetUsage(data, "mythlings")
end

function Mythlings.SaveWon(player: Player, params: { typeId: string, variantId: string }): string?
	assert(player and player.UserId, "[InventoryService.Mythlings] invalid player")
	assert(params, "[InventoryService.Mythlings] params required")

	local list = getOwned(player)
	local capacity = Mythlings.GetCapacity(player)
	if not list or not capacity or capacity.used >= capacity.limit then
		return nil
	end

	local id = makeId()
	local result = DataService.Update(player, "CaptureMythling", function(draft)
		local current = InventoryCapacity.GetUsage(draft, "mythlings")
		if current.used >= current.limit then
			return { ok = false, code = "InventoryFull" }
		end
		draft.mythlings[id] = {
			typeId = params.typeId,
			variantId = params.variantId,
			claimedAt = os.time(),
			level = 1,
			xp = 0,
		}
		return { ok = true, values = { instanceId = id } }
	end)
	if not result.ok then
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

	local result = DataService.Update(player, "RemoveMythling", function(draft)
		local entry = draft.mythlings[mythlingId]
		if not entry then
			return { ok = false, code = "NotOwned" }
		end
		if entry.standId ~= nil then
			return { ok = false, code = "Assigned" }
		end
		draft.mythlings[mythlingId] = nil
		return { ok = true }
	end)
	if not result.ok then
		return false
	end
	DataService.SaveNow(player)
	return true
end

function Mythlings.Get(player: Player, mythlingId: string): Types.MythlingEntry?
	assert(player and player.UserId, "[InventoryService.Mythlings] invalid player")
	return getOwnedEntry(player, mythlingId)
end

return Mythlings
