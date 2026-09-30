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
local BaseAccess = require(script.BaseAccess)
local BaseRequests = require(script.BaseRequests)
local CraftingAccess = require(script.CraftingAccess)
local BaseView = require(script.BaseView)
local ShrineView = require(script.ShrineView)
local ShrineAccess = require(script.ShrineAccess)
local ShrineConstruction = require(script.ShrineConstruction)
local BaseExpansionPurchase = require(script.BaseExpansionPurchase)
local ShrineWorkers = require(script.ShrineWorkers)
local ShrineUpgradePurchase = require(script.ShrineUpgradePurchase)
local ShrineRemoval = require(script.ShrineRemoval)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local BaseRequestsConfiguration =
	require(game:GetService("ReplicatedStorage").Shared.Configurations.BaseRequests)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Trove = require(game:GetService("ReplicatedStorage").Packages.Trove)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("BaseService")

-- ===== Module state =====
local serviceContext: ServerTypes.Context
local MAX_SLOTS = 8
local CHARACTER_ROOT_TIMEOUT_SECONDS = 10

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
local shrineConstruction: ShrineConstruction.ShrineConstruction?
local baseView: BaseView.BaseView?
local shrineView: ShrineView.ShrineView?
local baseExpansion: BaseExpansionPurchase.BaseExpansionPurchase?
local shrineWorkers: ShrineWorkers.ShrineWorkers?
local shrineUpgradePurchase: ShrineUpgradePurchase.ShrineUpgradePurchase?
local shrineRemoval: ShrineRemoval.ShrineRemoval?
local InventoryService: ServerTypes.InventoryApi
local ProductionService: ServerTypes.ProductionApi
local placementLimiter = RateLimiter.new(6, 2)
local requestLimiter: RateLimiter.RateLimiter?
local requests: BaseRequests.Requests?
local getBaseRemote: RemoteFunction?
local buildShrineRemote: RemoteFunction?
local expandBaseRemote: RemoteFunction?
local getShrineRemote: RemoteFunction?
local assignShrineRemote: RemoteFunction?
local removeShrineRemote: RemoteFunction?
local upgradeShrineRemote: RemoteFunction?
local dismantleShrineRemote: RemoteFunction?

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
	getBaseRemote = serviceContext.Remotes.Base.GetBase
	buildShrineRemote = serviceContext.Remotes.Base.BuildShrine
	expandBaseRemote = serviceContext.Remotes.Base.ExpandBase
	getShrineRemote = serviceContext.Remotes.Base.GetShrine
	assignShrineRemote = serviceContext.Remotes.Base.AssignShrineWorker
	removeShrineRemote = serviceContext.Remotes.Base.RemoveShrineWorker
	upgradeShrineRemote = serviceContext.Remotes.Base.UpgradeShrine
	dismantleShrineRemote = serviceContext.Remotes.Base.DismantleShrine
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

local function available(player: Player): boolean
	return lifecycle:IsRunning()
		and typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function checkAccess(player: Player, data: Types.PlayerDoc): string?
	if not available(player) then
		return "DataUnavailable"
	end
	return BaseAccess.Check(player.UserId, player.Character, data.base, slots, basesFolder)
end

function BaseService.GetBase(player: Player): Types.BaseViewResult
	local reader = baseView
	if not reader or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return reader.Get(player)
end

function BaseService.GetShrine(
	player: Player,
	request: Types.GetShrineRequest
): Types.ShrineViewResult
	local reader = shrineView
	if not reader or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return reader.Get(player, request)
end

function BaseService.CheckShrineAccess(
	player: Player,
	baseRecord: Types.BaseRecord,
	shrineInstanceId: string
): string?
	if not available(player) then
		return "DataUnavailable"
	end
	return ShrineAccess.Check(
		player.UserId,
		player.Character,
		baseRecord,
		slots,
		basesFolder,
		shrineInstanceId
	)
end

local function checkShrineAccess(
	player: Player,
	data: Types.PlayerDoc,
	shrineInstanceId: string
): string?
	return BaseService.CheckShrineAccess(player, data.base, shrineInstanceId)
end

function BaseService.CheckCraftingAccess(
	player: Player,
	baseRecord: Types.BaseRecord,
	stationInstanceId: string?
): string?
	if
		not lifecycle:IsRunning()
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return "DataUnavailable"
	end
	return CraftingAccess.Check(
		player.UserId,
		player.Character,
		baseRecord,
		slots,
		basesFolder,
		stationInstanceId
	)
end

-- Fresh purchases update the existing Base projection; replay performs no presentation work.
function BaseService.BuildShrine(
	player: Player,
	request: Types.BuildShrineRequest
): Types.TransactionResult
	local construction = shrineConstruction
	if not construction or not available(player) then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = construction.Build(player, request)
	if result.ok and not result.replayed then
		local base = getPlayerBase(player)
		local data = DataService.GetLoadedData(player)
		if base and base.Parent == basesFolder and data then
			BaseRuntime.RefreshCapacity(base, data.base)
		end
	end
	return result
end

function BaseService.ExpandBase(
	player: Player,
	request: Types.ExpandBaseRequest
): Types.TransactionResult
	local expansion = baseExpansion
	if
		not lifecycle:IsRunning()
		or not expansion
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = expansion.Expand(player, request)
	if result.ok and not result.replayed then
		local base = getPlayerBase(player)
		local data = DataService.GetLoadedData(player)
		if base and base.Parent == basesFolder and data then
			BaseRuntime.RefreshCapacity(base, data.base)
		end
	end
	return result
end

local function getShrineWorkers(player: Player): ShrineWorkers.ShrineWorkers?
	if
		not lifecycle:IsRunning()
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return nil
	end
	return shrineWorkers
end

-- Canonical commands own transactions; fresh access checks run inside their callbacks.
function BaseService.AssignShrineWorker(
	player: Player,
	request: Types.AssignShrineWorkerRequest
): Types.TransactionResult
	local workers = getShrineWorkers(player)
	if not workers then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return workers.Assign(player, request)
end

function BaseService.RemoveShrineWorker(
	player: Player,
	request: Types.RemoveShrineWorkerRequest
): Types.TransactionResult
	local workers = getShrineWorkers(player)
	if not workers then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return workers.Remove(player, request)
end

function BaseService.UpgradeShrine(
	player: Player,
	request: Types.UpgradeShrineRequest
): Types.TransactionResult
	local purchase = shrineUpgradePurchase
	if
		not lifecycle:IsRunning()
		or not purchase
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return purchase.Upgrade(player, request)
end

function BaseService.DismantleShrine(
	player: Player,
	request: Types.DismantleShrineRequest
): Types.TransactionResult
	local removal = shrineRemoval
	if
		not lifecycle:IsRunning()
		or not removal
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = removal.Dismantle(player, request)
	if result.ok and not result.replayed then
		local base = getPlayerBase(player)
		local data = DataService.GetLoadedData(player)
		if base and base.Parent == basesFolder and data then
			BaseRuntime.RefreshCapacity(base, data.base)
		end
	end
	return result
end

local function bindCharacterSpawn(
	player: Player,
	base: Model,
	owner: Trove.Trove,
	isCurrent: () -> boolean
)
	local characterOwner = owner:Extend()
	local activeCharacter: Model? = nil

	local function onCharacter(character: Model)
		if activeCharacter == character then
			return
		end
		activeCharacter = character
		characterOwner:Clean()

		local function teleportWhenReady()
			local root = character:WaitForChild("HumanoidRootPart", CHARACTER_ROOT_TIMEOUT_SECONDS)
			if not isCurrent() or player.Character ~= character or base.Parent ~= basesFolder then
				return
			end
			if not (root and root:IsA("BasePart")) then
				log.warn(`Character root unavailable for userId={player.UserId}`)
				return
			end
			local teleported, message = BaseRuntime.TeleportToBaseSpawn(player, character, base)
			if not teleported then
				log.warn(`Base spawn failed for userId={player.UserId}: {message or "unknown"}`)
			end
		end

		characterOwner:Add(task.defer(function()
			teleportWhenReady()
			characterOwner:Pop(coroutine.running())
		end))
	end

	owner:Connect(player.CharacterAdded, onCharacter)
	owner:Connect(player.CharacterRemoving, function(character: Model)
		if activeCharacter == character then
			activeCharacter = nil
			characterOwner:Clean()
		end
	end)
	if player.Character then
		onCharacter(player.Character)
	end
end

local function handlePlayerAdded(player: Player, isCurrent: () -> boolean)
	if not DataService.Load(player) or not isCurrent() then
		return
	end
	local data = DataService.GetLoadedData(player)
	if not data then
		return
	end
	local playerTrove = lifecycle.trove:Extend()
	playerTroves[player] = playerTrove
	local result, message = BaseRuntime.SpawnBaseFor(
		player,
		slots,
		MAX_SLOTS,
		baseModel,
		data.base,
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

	bindCharacterSpawn(player, base, playerTrove, isCurrent)

	StandPlacement.LoadMythlingsOnStands(data.mythlings, base, mythlingAssets, MythlingsMeta)
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
	if requestLimiter then
		requestLimiter:Forget(player)
	end
end

-- ===== Service lifecycle =====
function BaseService.Init(context: ServerTypes.Context)
	serviceContext = context
	resolveAssets()
	local burst = BaseRequestsConfiguration.requestBurst
	local refill = BaseRequestsConfiguration.requestRefillPerSecond
	assert(
		type(burst) == "number"
			and burst >= 1
			and burst < math.huge
			and burst % 1 == 0
			and type(refill) == "number"
			and refill > 0
			and refill < math.huge,
		"[BaseService] Invalid Base request tuning"
	)
	local limiter = RateLimiter.new(burst, refill)
	requestLimiter = limiter
	shrineConstruction = ShrineConstruction.new(DataService, nil, checkAccess)
	baseView = BaseView.new(DataService, checkAccess)
	shrineView = ShrineView.new(DataService, checkShrineAccess)
	baseExpansion = BaseExpansionPurchase.new(DataService, checkAccess)
	requests = BaseRequests.new({
		isAvailable = available,
		allowRequest = function(player: Player): boolean
			return limiter:Allow(player)
		end,
		getBase = function(player: Player): Types.BaseViewResult
			return BaseService.GetBase(player)
		end,
		buildShrine = function(player: Player, input: unknown): Types.TransactionResult
			-- The command validates the whole request at the untrusted-to-typed API boundary.
			return BaseService.BuildShrine(player, input :: Types.BuildShrineRequest)
		end,
		expandBase = function(player: Player, input: unknown): Types.TransactionResult
			return BaseService.ExpandBase(player, input :: Types.ExpandBaseRequest)
		end,
		getShrine = function(player: Player, input: unknown): Types.ShrineViewResult
			return BaseService.GetShrine(player, input :: Types.GetShrineRequest)
		end,
		assignShrineWorker = function(player: Player, input: unknown): Types.TransactionResult
			return BaseService.AssignShrineWorker(player, input :: Types.AssignShrineWorkerRequest)
		end,
		removeShrineWorker = function(player: Player, input: unknown): Types.TransactionResult
			return BaseService.RemoveShrineWorker(player, input :: Types.RemoveShrineWorkerRequest)
		end,
		upgradeShrine = function(player: Player, input: unknown): Types.TransactionResult
			return BaseService.UpgradeShrine(player, input :: Types.UpgradeShrineRequest)
		end,
		dismantleShrine = function(player: Player, input: unknown): Types.TransactionResult
			return BaseService.DismantleShrine(player, input :: Types.DismantleShrineRequest)
		end,
	})
	shrineWorkers = ShrineWorkers.new(DataService, nil, checkShrineAccess)
	shrineUpgradePurchase = ShrineUpgradePurchase.new(DataService, nil, checkShrineAccess)
	shrineRemoval = ShrineRemoval.new(DataService, nil, checkShrineAccess)
end

function BaseService.Start()
	if not lifecycle:Start() then
		return
	end
	local handler = assert(requests, "[BaseService] Init must precede Start")
	local getRemote = assert(getBaseRemote, "[BaseService] GetBase remote is not initialized")
	local buildRemote =
		assert(buildShrineRemote, "[BaseService] BuildShrine remote is not initialized")
	local expandRemote =
		assert(expandBaseRemote, "[BaseService] ExpandBase remote is not initialized")
	getRemote.OnServerInvoke = handler.GetBase
	buildRemote.OnServerInvoke = handler.BuildShrine
	expandRemote.OnServerInvoke = handler.ExpandBase
	local shrineGet = assert(getShrineRemote, "[BaseService] GetShrine remote is not initialized")
	local shrineAssign =
		assert(assignShrineRemote, "[BaseService] AssignShrineWorker remote is not initialized")
	local shrineRemove =
		assert(removeShrineRemote, "[BaseService] RemoveShrineWorker remote is not initialized")
	local shrineUpgrade =
		assert(upgradeShrineRemote, "[BaseService] UpgradeShrine remote is not initialized")
	local shrineDismantle =
		assert(dismantleShrineRemote, "[BaseService] DismantleShrine remote is not initialized")
	shrineGet.OnServerInvoke = handler.GetShrine
	shrineAssign.OnServerInvoke = handler.AssignShrineWorker
	shrineRemove.OnServerInvoke = handler.RemoveShrineWorker
	shrineUpgrade.OnServerInvoke = handler.UpgradeShrine
	shrineDismantle.OnServerInvoke = handler.DismantleShrine
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
	if getBaseRemote then
		RemoteUtil.ClearServerHandler(getBaseRemote)
	end
	if buildShrineRemote then
		RemoteUtil.ClearServerHandler(buildShrineRemote)
	end
	if expandBaseRemote then
		RemoteUtil.ClearServerHandler(expandBaseRemote)
	end
	if getShrineRemote then
		RemoteUtil.ClearServerHandler(getShrineRemote)
	end
	if assignShrineRemote then
		RemoteUtil.ClearServerHandler(assignShrineRemote)
	end
	if removeShrineRemote then
		RemoteUtil.ClearServerHandler(removeShrineRemote)
	end
	if upgradeShrineRemote then
		RemoteUtil.ClearServerHandler(upgradeShrineRemote)
	end
	if dismantleShrineRemote then
		RemoteUtil.ClearServerHandler(dismantleShrineRemote)
	end
	for player in playerTroves do
		handlePlayerRemoving(player)
	end
	for index, slot in slots do
		slot.base:Destroy()
		slots[index] = nil
	end
	placementLimiter:Clear()
	if requestLimiter then
		requestLimiter:Clear()
	end
	requestLimiter = nil
	requests = nil
	shrineConstruction = nil
	baseView = nil
	shrineView = nil
	baseExpansion = nil
	shrineWorkers = nil
	shrineUpgradePurchase = nil
	shrineRemoval = nil
end

return BaseService
