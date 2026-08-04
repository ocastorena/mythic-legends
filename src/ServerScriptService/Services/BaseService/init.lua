-- ServerScriptService/Services/BaseService
local BaseService = {}

-- Roblox services
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local RateLimiter = require(Infrastructure:WaitForChild("RateLimiter"))

local log = LogUtil.For("BaseService")

-- Module dependencies
local StandUtil = require(script.StandUtil)
local BaseUtil = require(script.BaseUtil)

-- ===== Module state =====
local Context: any = nil
local running = false
local MAX_SLOTS = 8

-- slotIndex -> { userId, baseModel }
local SLOTS: { [number]: { userId: number, base: Model } } = {}

-- Cached assets
local Arena: BasePart
local BaseIslands: Folder
local BasesFolder: Folder
local BaseModel: Model
local MythlingAssets: Folder
local PlaceMythlingRemote: RemoteFunction
local RemoveMythlingRemote: RemoteFunction
local MythlingsMeta: ModuleScript
local DataService: any
local InventoryService: any
local ProductionService: any
local placementLimiter = RateLimiter.new(6, 2)
local connections: { RBXScriptConnection } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

-- ===== Utilities =====

local function resolveAssets()
	Arena = Context.Instances.Arena
	BaseIslands = Context.Instances.BaseIslands
	BasesFolder = Context.Instances.Bases
	MythlingAssets = Context.Instances.MythlingAssets
	MythlingsMeta = Context.Configurations.Mythlings
	PlaceMythlingRemote = Context.Remotes.Base.PlaceMythling
	RemoveMythlingRemote = Context.Remotes.Base.RemoveMythling
	DataService = Context.Services.DataService
	InventoryService = Context.Services.InventoryService
	ProductionService = Context.Services.ProductionService

	local root = Context.Instances.BaseAssets
	BaseModel = root:FindFirstChild("BaseLevel1")
	if not (BaseModel and BaseModel:IsA("Model")) then
		log.warn("Missing base model: BaseLevel1")
	end
end

local function getPlayerBase(player: Player)
	for _, slot in pairs(SLOTS) do
		if slot.userId == player.UserId then
			return slot.base
		end
	end
	return nil
end

local function handlePlayerAdded(player: Player)
	local result, message = BaseUtil.SpawnBaseFor(player, SLOTS, MAX_SLOTS, BaseModel, Arena, BaseIslands, BasesFolder)
	if not result then
		log.warn(message)
	end

	local base = getPlayerBase(player)
	if not base then
		return { ok = false, code = "BaseUnavailable" }
	end

	characterConnections[player] = player.CharacterAdded:Connect(function(char)
		BaseUtil.TeleportToBaseSpawn(player, char, base)
	end)

	local mythlingsSection = DataService.GetSection(player, "mythlings")

	StandUtil.LoadMythlingsOnStands(mythlingsSection, base, MythlingAssets, MythlingsMeta)
end

local function validRequest(standId: unknown, mythlingId: unknown): boolean
	return type(standId) == "number"
		and standId % 1 == 0
		and standId >= 0
		and standId <= 128
		and type(mythlingId) == "string"
		and #mythlingId > 0
		and #mythlingId <= 128
end

local function handlePlaceMythling(player: Player, payload: unknown)
	if not placementLimiter:Allow(player) then
		return { ok = false, code = "RateLimited" }
	end
	if type(payload) ~= "table" or not validRequest(payload.standId, payload.mythlingId) then
		return { ok = false, code = "InvalidRequest" }
	end
	local standId = payload.standId
	local mythlingId = payload.mythlingId
	local mythlingSection = DataService.GetSection(player, "mythlings")
	local mythlingEntry = mythlingSection[mythlingId]
	if not mythlingEntry then
		return { ok = false, code = "NotOwned" }
	end
	local base = getPlayerBase(player)
	if not base then
		return { ok = false, code = "BaseUnavailable" }
	end
	local mythlingMeta = MythlingsMeta[mythlingEntry.typeId]
	local result, message =
		StandUtil.SetMythlingOnStand(mythlingEntry, base, standId, MythlingAssets, mythlingMeta)
	if not result then
		log.warn(message)
		return { ok = false, code = "PlacementRejected" }
	end
	InventoryService.MarkDirty(player)
	ProductionService.StartProduction(player, mythlingId)
	return { ok = true }
end

local function handleRemoveMythling(player: Player, payload: unknown)
	if not placementLimiter:Allow(player) then
		return { ok = false, code = "RateLimited" }
	end
	if type(payload) ~= "table" or not validRequest(payload.standId, payload.mythlingId) then
		return { ok = false, code = "InvalidRequest" }
	end
	local mythlingId = payload.mythlingId
	local mythlingSection = DataService.GetSection(player, "mythlings")
	local mythlingEntry = mythlingSection[mythlingId]
	if not mythlingEntry then
		return { ok = false, code = "NotOwned" }
	end
	if mythlingEntry.standId ~= payload.standId then
		return { ok = false, code = "StandMismatch" }
	end
	local base = getPlayerBase(player)
	if not base then
		return { ok = false, code = "BaseUnavailable" }
	end
	local result, message = StandUtil.RemoveMythlingFromStand(mythlingEntry, base)
	if result then
		InventoryService.MarkDirty(player)
	else
		log.warn(message)
		return { ok = false, code = "RemovalRejected" }
	end
	ProductionService.StopProduction(player, mythlingId)
	return { ok = true }
end

function BaseService.RemoveMythlingFromStand(player: Player, mythlingId: string): boolean
	local mythlingEntry = DataService.GetSection(player, "mythlings")[mythlingId]
	if not mythlingEntry then
		return false
	end
	if mythlingEntry.standId == nil then
		return true
	end
	local base = getPlayerBase(player)
	if not base then
		return false
	end
	local removed = StandUtil.RemoveMythlingFromStand(mythlingEntry, base)
	if not removed then
		return false
	end
	ProductionService.StopProduction(player, mythlingId)
	return true
end

local function handlePlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
	BaseUtil.RemoveBaseFor(player, SLOTS)
	placementLimiter:Forget(player)
end

-- ===== Service lifecycle =====
function BaseService.Init(context)
	Context = context
	resolveAssets()
end

function BaseService.Start()
	if running then
		return
	end
	running = true

	table.insert(connections, PlayerUtil.OnPlayer(handlePlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(handlePlayerRemoving))
	PlaceMythlingRemote.OnServerInvoke = handlePlaceMythling
	RemoveMythlingRemote.OnServerInvoke = handleRemoveMythling
end

function BaseService.Stop()
	running = false
	PlaceMythlingRemote.OnServerInvoke = nil
	RemoveMythlingRemote.OnServerInvoke = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player in characterConnections do
		handlePlayerRemoving(player)
	end
	placementLimiter:Clear()
end

return BaseService
