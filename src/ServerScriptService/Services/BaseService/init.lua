--!strict
-- ServerScriptService/Services/BaseService
local BaseService = {}

-- Roblox services
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))

local log = LogUtil.For("BaseService")

-- Module dependencies
local StandPlacement = require(script.StandPlacement)
local BaseRuntime = require(script.BaseRuntime)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local ServerTypes = require(ServerScriptService.Domain.Types)
local Trove = require(game:GetService("ReplicatedStorage").Packages.Trove)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("BaseService")

-- ===== Module state =====
local serviceContext: ServerTypes.Context
local MAX_SLOTS = 8

-- slotIndex -> { userId, baseModel }
local slots: BaseRuntime.Slots = {}

-- Cached assets
local arena: BasePart
local baseIslands: Folder
local basesFolder: Folder
local baseModel: Model?
local mythlingAssets: Folder
local placeMythlingRemote: RemoteFunction
local removeMythlingRemote: RemoteFunction
local MythlingsMeta: { [string]: Types.MythlingDef }
local DataService: ServerTypes.DataApi
local InventoryService: ServerTypes.InventoryApi
local ProductionService: ServerTypes.ProductionApi
local placementLimiter = RateLimiter.new(6, 2)

local playerTroves: { [Player]: Trove.Trove } = {}

-- ===== Utilities =====

local function resolveAssets()
	arena = serviceContext.Instances.Arena
	baseIslands = serviceContext.Instances.BaseIslands
	basesFolder = serviceContext.Instances.Bases
	mythlingAssets = serviceContext.Instances.MythlingAssets
	MythlingsMeta = serviceContext.Configurations.Mythlings
	placeMythlingRemote = serviceContext.Remotes.Base.PlaceMythling
	removeMythlingRemote = serviceContext.Remotes.Base.RemoveMythling
	DataService = serviceContext.Services.DataService
	InventoryService = serviceContext.Services.InventoryService
	ProductionService = serviceContext.Services.ProductionService

	local root = serviceContext.Instances.BaseAssets
	local template = root:FindFirstChild("BaseLevel1")
	baseModel = if template and template:IsA("Model") then template else nil
	if not (baseModel and baseModel:IsA("Model")) then
		log.warn("Missing base model: BaseLevel1")
	end
end

local function getPlayerBase(player: Player): Model?
	for _, slot in pairs(slots) do
		if slot.userId == player.UserId then
			return slot.base
		end
	end
	return nil
end

function BaseService.GetSpawnPoint(player: Player): BasePart?
	local base = getPlayerBase(player)
	if not base or base.Parent ~= basesFolder then
		return nil
	end
	local spawnPart = base:FindFirstChild("Spawn")
	return if spawnPart and spawnPart:IsA("BasePart") then spawnPart else nil
end

local function handlePlayerAdded(player: Player, isCurrent: () -> boolean)
	if not DataService.Load(player) or not isCurrent() then
		return
	end
	local playerTrove = lifecycle.trove:Extend()
	playerTroves[player] = playerTrove
	local result, message = BaseRuntime.SpawnBaseFor(
		player,
		slots,
		MAX_SLOTS,
		baseModel,
		arena,
		baseIslands,
		basesFolder
	)
	if not result then
		log.warn(message)
	end

	local base = getPlayerBase(player)
	if not base then
		return
	end

	playerTrove:Connect(player.CharacterAdded, function(char: Model)
		BaseRuntime.TeleportToBaseSpawn(player, char, base)
	end)

	local mythlingsSection = DataService.GetData(player).mythlings

	StandPlacement.LoadMythlingsOnStands(mythlingsSection, base, mythlingAssets, MythlingsMeta)
end

function BaseService.HasStand(player: Player, standId: number): boolean
	return StandPlacement.HasStand(getPlayerBase(player), standId)
end

type PlacementRequest = { standId: number, mythlingId: string }
type PlacementResult = { ok: boolean, code: string? }
local function parseRequest(payload: unknown): PlacementRequest?
	if type(payload) ~= "table" then
		return nil
	end
	local fields = payload :: { [string]: unknown }
	local standId, mythlingId = fields.standId, fields.mythlingId
	if
		type(standId) ~= "number"
		or standId % 1 ~= 0
		or standId < 0
		or standId > 128
		or type(mythlingId) ~= "string"
		or #mythlingId == 0
		or #mythlingId > 128
	then
		return nil
	end
	return { standId = standId, mythlingId = mythlingId }
end

local function handlePlaceMythling(player: Player, payload: unknown): PlacementResult
	if not placementLimiter:Allow(player) then
		return { ok = false, code = "RateLimited" }
	end
	local request = parseRequest(payload)
	if not request then
		return { ok = false, code = "InvalidRequest" }
	end
	local standId = request.standId
	local mythlingId = request.mythlingId
	local data = DataService.GetLoadedData(player)
	if not lifecycle:IsRunning() or not data then
		return { ok = false, code = "DataUnavailable" }
	end
	local mythlingSection = data.mythlings
	local mythlingEntry = mythlingSection[mythlingId]
	if not mythlingEntry then
		return { ok = false, code = "NotOwned" }
	end
	local base = getPlayerBase(player)
	if not base then
		return { ok = false, code = "BaseUnavailable" }
	end
	local mythlingMeta = MythlingsMeta[mythlingEntry.typeId]
	-- Settle the old occupant/empty interval before changing the assignment. A failed
	-- placement may checkpoint work, but cannot erase it or backfill empty time.
	local settled, settleCode = ProductionService.SettleProduction(player, standId)
	if not settled then
		return { ok = false, code = settleCode or "ProductionUnavailable" }
	end
	local result = StandPlacement.SetMythlingOnStand(
		mythlingEntry,
		base,
		standId,
		mythlingAssets,
		mythlingMeta
	)
	if not result then
		return { ok = false, code = "PlacementRejected" }
	end
	InventoryService.MarkDirty(player)
	return { ok = true }
end

local function handleRemoveMythling(player: Player, payload: unknown): PlacementResult
	if not placementLimiter:Allow(player) then
		return { ok = false, code = "RateLimited" }
	end
	local request = parseRequest(payload)
	if not request then
		return { ok = false, code = "InvalidRequest" }
	end
	local mythlingId = request.mythlingId
	local data = DataService.GetLoadedData(player)
	if not lifecycle:IsRunning() or not data then
		return { ok = false, code = "DataUnavailable" }
	end
	local mythlingSection = data.mythlings
	local mythlingEntry = mythlingSection[mythlingId]
	if not mythlingEntry then
		return { ok = false, code = "NotOwned" }
	end
	if mythlingEntry.standId ~= request.standId then
		return { ok = false, code = "StandMismatch" }
	end
	local base = getPlayerBase(player)
	if not base then
		return { ok = false, code = "BaseUnavailable" }
	end
	local settled, settleCode = ProductionService.SettleProduction(player, request.standId)
	if not settled then
		return { ok = false, code = settleCode or "ProductionUnavailable" }
	end
	local result, message = StandPlacement.RemoveMythlingFromStand(mythlingEntry, base)
	if result then
		InventoryService.MarkDirty(player)
	else
		log.warn(message)
		return { ok = false, code = "RemovalRejected" }
	end
	return { ok = true }
end

function BaseService.RemoveMythlingFromStand(player: Player, mythlingId: string): boolean
	local data = DataService.GetLoadedData(player)
	if not lifecycle:IsRunning() or not data then
		return false
	end
	local mythlingEntry = data.mythlings[mythlingId]
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
	if not ProductionService.SettleProduction(player, mythlingEntry.standId) then
		return false
	end
	local removed = StandPlacement.RemoveMythlingFromStand(mythlingEntry, base)
	if not removed then
		return false
	end
	InventoryService.MarkDirty(player)
	return true
end

local function handlePlayerRemoving(player: Player)
	local owner = playerTroves[player]
	if owner then
		playerTroves[player] = nil
		lifecycle.trove:Remove(owner)
	end
	BaseRuntime.RemoveBaseFor(player, slots)
	placementLimiter:Forget(player)
end

-- ===== Service lifecycle =====
function BaseService.Init(context: ServerTypes.Context)
	serviceContext = context
	resolveAssets()
end

function BaseService.Start()
	if not lifecycle:Start() then
		return
	end
	PlayerUtil.OnPlayer(handlePlayerAdded, lifecycle.trove)
	lifecycle.trove:Connect(Players.PlayerRemoving, handlePlayerRemoving)
	placeMythlingRemote.OnServerInvoke = handlePlaceMythling
	removeMythlingRemote.OnServerInvoke = handleRemoveMythling
end

function BaseService.Stop()
	if not lifecycle:Stop() then
		return
	end
	RemoteUtil.ClearServerHandler(placeMythlingRemote)
	RemoteUtil.ClearServerHandler(removeMythlingRemote)
	for player in playerTroves do
		handlePlayerRemoving(player)
	end
	for index, slot in slots do
		slot.base:Destroy()
		slots[index] = nil
	end
	placementLimiter:Clear()
end

return BaseService
