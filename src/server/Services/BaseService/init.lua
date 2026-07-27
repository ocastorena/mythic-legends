-- ServerScriptService/Services/BaseService
local BaseService = {}

-- Roblox services
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))

local log = LogUtil.For("BaseService")

-- Module dependencies
local StandUtil = require(script.StandUtil)
local BaseUtil = require(script.BaseUtil)

-- ===== Module state =====
local Context: any = nil
local running = false
local MAX_SLOTS = 8

-- slotIndex -> { userId, baseModel }
local SLOTS: { [number]: { userId: number, model: Model } } = {}

-- Cached assets
local Arena: BasePart
local BaseIslands: Folder
local BasesFolder: Folder
local BaseModel: Model
local MythlingAssets: Folder
local GetStandsRemote: RemoteFunction
local BaseEventRemote: RemoteEvent
local MythlingsEvent: RemoteEvent
local MythlingsMeta: ModuleScript
local DataService: any
local InventoryService: any
local ProductionService: any

-- ===== Utilities =====

local function resolveAssets()
	Arena = Context.Instances.Arena
	BaseIslands = Context.Instances.BaseIslands
	BasesFolder = Context.Instances.Bases
	MythlingAssets = Context.Instances.MythlingAssets
	MythlingsMeta = Context.Metadata.Mythlings
	GetStandsRemote = Context.Remotes.GetStands
	BaseEventRemote = Context.Remotes.BaseEvent
	MythlingsEvent = Context.Remotes.MythlingsEvent
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

	player.CharacterAdded:Connect(function(char)
		BaseUtil.TeleportToBaseSpawn(player, char, base)
	end)

	local mythlingsSection = DataService.GetSection(player, "mythlings")

	StandUtil.LoadMythlingsOnStands(mythlingsSection, base, MythlingAssets, MythlingsMeta)
end

local function handleBaseEvent(player: Player, eventType: string, payload: any)
	if eventType == "PlaceMythling" then
		local standId = payload.standId
		local mythlingId = payload.mythlingId
		local base = getPlayerBase(player)
		local mythlingSection = DataService.GetSection(player, "mythlings")
		local mythlingEntry = mythlingSection[mythlingId]
		local mythlingMeta = MythlingsMeta[mythlingEntry.typeId]
		local result, message =
			StandUtil.SetMythlingOnStand(mythlingEntry, base, standId, MythlingAssets, mythlingMeta)
		if not result then
			log.warn(message)
		else
			InventoryService.MarkDirty(player)
		end
		ProductionService.StartProduction(player, mythlingId)
	elseif eventType == "RemoveMythling" then
		local mythlingId = payload.mythlingId
		local base = getPlayerBase(player)
		local mythlingSection = DataService.GetSection(player, "mythlings")
		local mythlingEntry = mythlingSection[mythlingId]
		local result, message = StandUtil.RemoveMythlingFromStand(mythlingEntry, base)
		if result then
			InventoryService.MarkDirty(player)
		else
			log.warn(message)
		end
		ProductionService.StopProduction(player, mythlingId)
	end
end

local function handleInventoryEvent(player: Player, eventType: string, mythlingId: number)
	if eventType == "Delete" then
		local base = getPlayerBase(player)
		local mythlingSection = DataService.GetSection(player, "mythlings")
		local mythlingEntry = mythlingSection[mythlingId]
		StandUtil.RemoveMythlingFromStand(mythlingEntry, base)
	end
end

local function handlePlayerRemoving(player: Player)
	BaseUtil.RemoveBaseFor(player, SLOTS)
end

local function handleGetStands(player: Player)
	return DataService.GetSection(player, "base").stands
end

-- ===== Service lifecycle =====
function BaseService.Init(context)
	Context = context
	resolveAssets()
	log.info("Initialized")
end

function BaseService.Start()
	if running then
		return
	end
	running = true

	PlayerUtil.OnPlayer(handlePlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoving)
	BaseEventRemote.OnServerEvent:Connect(handleBaseEvent)
	MythlingsEvent.OnServerEvent:Connect(handleInventoryEvent)
	GetStandsRemote.OnServerInvoke = handleGetStands
end

return BaseService
