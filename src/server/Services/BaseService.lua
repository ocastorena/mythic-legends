-- BaseService
local BaseService = {}

-- Roblox services
local Players = game:GetService("Players")

-- Module dependencies
local BaseUtils  = script.Parent:FindFirstChild("BaseUtils")
local StandsUtil = require(BaseUtils.StandsUtil)
local BasesUtil  = require(BaseUtils.BasesUtil)

-- ===== Module state =====
local Context: any = nil
local running = false
local MAX_SLOTS = 8

-- slotIndex -> { userId, baseModel }
local SLOTS: {[number]: { userId: number, model: Model }} = {}

-- Cached assets
local Arena: BasePart
local ArenaPlate: BasePart
local BasesFolder: Instance
local BaseModel: Model
local MythlingAssets: Instance
local GetStandsRemote: RemoteFunction
local BaseEventRemote: RemoteEvent
local InventoryEventRemote: RemoteEvent
local DataService: any
local ProductionService: any

-- ===== Utilities =====

local function resolveAssets()
	Arena           = Context.Instances.Arena
	ArenaPlate      = Context.Instances.ArenaPlate
	BasesFolder     = Context.Instances.Bases
	MythlingAssets  = Context.Instances.MythlingAssets
	GetStandsRemote = Context.Remotes.GetStands
	BaseEventRemote = Context.Remotes.BaseEvent
	InventoryEventRemote = Context.Remotes.InventoryEvent
	DataService     = Context.Services.DataService
	ProductionService = Context.Services.ProductionService

	local root = Context.Instances.BaseAssets
	BaseModel = root:FindFirstChild("BaseLevel1")
	if not (BaseModel and BaseModel:IsA("Model")) then
		warn("[BaseService] Missing base model: BaseLevel1")
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
	local result, message = BasesUtil.SpawnBaseFor(player, SLOTS, MAX_SLOTS, BaseModel, Arena, ArenaPlate, BasesFolder)
	if not result then warn("[BaseService] " .. message ) end
	
	local base = getPlayerBase(player)
	
	player.CharacterAdded:Connect(function(char)
		BasesUtil.TeleportToBaseSpawn(player, char, base)
	end)
	
	local baseSection = DataService.GetSection(player, "base")
	local mythlingSection = DataService.GetSection(player, "mythlings")

	StandsUtil.LoadMythlingsOnStands(baseSection, mythlingSection, base, MythlingAssets)
end

local function handleBaseEvent(player: Player, eventType: string, payload: any)

	if eventType == "PlaceMythling" then
		local standId = payload.standId
		local mythlingId = payload.mythlingId
		local base = getPlayerBase(player)
		local baseSection = DataService.GetSection(player, "base")
		local mythlingSection = DataService.GetSection(player, "mythlings")
		local result, message = StandsUtil.SetMythlingOnStand(baseSection, mythlingSection, base, standId, mythlingId, MythlingAssets)
		if not result then warn("[BaseService] " .. message ) end
		ProductionService.StartProduction(player, mythlingId)
	elseif eventType == "RemoveMythling" then
		local standId = payload.standId
		local mythlingId = payload.mythlingId
		local base = getPlayerBase(player)
		local baseSection = DataService.GetSection(player, "base")
		local mythlingSection = DataService.GetSection(player, "mythlings")
		StandsUtil.RemoveMythlingFromStand(baseSection, mythlingSection, base, standId)
		ProductionService.StopProduction(player, mythlingId)
	end
end

local function handleInventoryEvent(player: Player, eventType: string, mythlingId: number)
	if eventType == "Delete" then
		local baseModel = getPlayerBase(player)
		local baseSection = DataService.GetSection(player, "base")
		local standId = nil
		for i, id in baseSection.stands do
			if id == mythlingId then
				standId = i
				break
			end
		end
		if standId == nil then return end
		local mythlingSection = DataService.GetSection(player, "mythlings")
		StandsUtil.RemoveMythlingFromStand(baseSection, mythlingSection, baseModel, standId)
	end
end

local function handlePlayerRemoving(player: Player)
	BasesUtil.RemoveBaseFor(player, SLOTS)
end

local function handleGetStands(player: Player)
	return DataService.GetSection(player, "base").stands
end

-- ===== Service lifecycle =====
function BaseService.Init(context)
	Context = context
	resolveAssets()
	print("[BaseService] Initialized")
end

function BaseService.Start()
	if running then return end
	running = true

	Players.PlayerAdded:Connect(handlePlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoving)
	BaseEventRemote.OnServerEvent:Connect(handleBaseEvent)
	InventoryEventRemote.OnServerEvent:Connect(handleInventoryEvent)
	GetStandsRemote.OnServerInvoke = handleGetStands
	
end

return BaseService
