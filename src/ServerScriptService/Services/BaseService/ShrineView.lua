--!strict
-- ServerScriptService/Services/BaseService/ShrineView
-- Project committed Shrine state only; opening a view never awards or settles earned work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Progression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local MythlingProgressionUtil = require(ServerScriptService.Shared.MythlingProgressionUtil)
local ShrineUpgradePurchase = require(script.Parent.ShrineUpgradePurchase)

local ShrineView = {}
export type DataSource = { GetLoadedData: (Player) -> Types.PlayerDoc? }
export type ShrineView = { Get: (Player, unknown) -> Types.ShrineViewResult }

local function whole(value: unknown): boolean
	return type(value) == "number" and value >= 0 and value < 2 ^ 53 and value % 1 == 0
end

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if plain(state) then
		local revision = (state :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function parseRequest(raw: unknown): string?
	if not plain(raw) then
		return nil
	end
	local fields = raw :: { [string]: unknown }
	for key in fields do
		if key ~= "shrineInstanceId" then
			return nil
		end
	end
	local id = fields.shrineInstanceId
	return if type(id) == "string" and #id > 0 and #id <= 128 then id else nil
end

local function project(data: Types.PlayerDoc, id: string): (Types.ShrineView?, string?)
	local snapshot, problem = ShrineAccounting.ReadSnapshot(data)
	if not snapshot then
		return nil, problem
	end
	local state, metadata = snapshot.state, snapshot.metadata
	local shrine = state.shrines[id]
	if not shrine then
		return nil, "ShrineNotOwned"
	end
	if not plain(data.currency) or not whole(data.currency.gold) then
		return nil, "InvalidCurrency"
	end
	problem = InventoryCapacity.ValidateMaterialState(data)
	if problem then
		return nil, problem
	end
	local upgrade, upgradeCode = ShrineUpgradePurchase.ReadOffer(data, state, metadata, id)
	if not upgrade and upgradeCode ~= "MaxLevel" then
		return nil, upgradeCode
	end
	local definition = Shrines[shrine.shrineId]
	local level = definition.levels[shrine.level]
	local productionView, productionError = ShrineAccrual.ReadProduction(state, id, metadata)
	if not productionView then
		return nil, productionError
	end
	local assigned: { [string]: boolean } = {}
	for _, owned in state.shrines do
		for _, workerId in owned.workerIdsBySlot do
			assigned[workerId] = true
		end
	end
	local function workerView(workerId: string): Types.ShrineWorkerView
		local worker = state.workers[workerId]
		return {
			workerId = workerId,
			formId = worker.formId,
			level = worker.level,
			xp = worker.xp,
			yieldPerHour = MythlingProgressionUtil.GetYield(
				metadata.forms[worker.formId].baseYieldPerHour,
				worker.level,
				Progression
			),
		}
	end
	local slots: { Types.ShrineSlotView } = {}
	for slotId = 1, level.workerSlots do
		local workerId = shrine.workerIdsBySlot[tostring(slotId)]
		local worker = if workerId then workerView(workerId) else nil
		table.insert(slots, { slotId = slotId, worker = worker })
	end
	local available: { Types.ShrineWorkerView } = {}
	for workerId, worker in state.workers do
		if
			not assigned[workerId]
			and metadata.forms[worker.formId].element == definition.element
		then
			table.insert(available, workerView(workerId))
		end
	end
	table.sort(available, function(left: Types.ShrineWorkerView, right: Types.ShrineWorkerView)
		return left.workerId < right.workerId
	end)
	local collectable =
		math.min(shrine.stored, InventoryCapacity.GetMaterialRoom(data, definition.materialId))
	local collectCode = if shrine.stored == 0
		then "NothingToCollect"
		elseif collectable == 0 then "InventoryFull"
		else nil
	local dismantleCode = if next(shrine.workerIdsBySlot) ~= nil
		then "ShrineOccupied"
		elseif shrine.stored > 0 then "MaterialsStored"
		else nil
	-- ReadSnapshot validated this owned map; never return the saved record or accounting ledger.
	local ownedShrines = data.base.shrines :: { [string]: Types.ShrineRecord }
	return {
		shrineInstanceId = id,
		shrineId = shrine.shrineId,
		buildSlotId = ownedShrines[id].buildSlotId,
		level = shrine.level,
		maxLevel = definition.maxLevel,
		element = definition.element,
		materialId = definition.materialId,
		stored = shrine.stored,
		storageCapacity = level.capacity,
		yieldPerHour = productionView.yieldPerHour,
		isProducing = productionView.isProducing,
		productionProgress = productionView.productionProgress,
		estimatedSecondsToNextMaterial = productionView.estimatedSecondsToNextMaterial,
		slots = slots,
		availableWorkers = available,
		collectable = collectable,
		canCollect = collectCode == nil,
		collectCode = collectCode,
		canDismantle = dismantleCode == nil,
		dismantleCode = dismantleCode,
		upgrade = upgrade,
		upgradeCode = upgradeCode,
	},
		nil
end

function ShrineView.new(
	DataService: DataSource,
	checkAccess: ((Player, Types.PlayerDoc, string) -> string?)?
): ShrineView
	assert(
		type(DataService) == "table" and type(DataService.GetLoadedData) == "function",
		"[BaseService.ShrineView] DataService.GetLoadedData required"
	)
	local api = {}
	function api.Get(player: Player, rawRequest: unknown): Types.ShrineViewResult
		local data = DataService.GetLoadedData(player)
		if not data then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local revision = currentRevision(data)
		if revision < 0 then
			return { ok = false, code = "InvalidTransaction", revision = revision }
		end
		local id = parseRequest(rawRequest)
		if not id then
			return { ok = false, code = "InvalidRequest", revision = revision }
		end
		local accessProblem = if checkAccess then checkAccess(player, data, id) else nil
		if accessProblem then
			return { ok = false, code = accessProblem, revision = revision }
		end
		local view, problem = project(data, id)
		if not view then
			return { ok = false, code = problem, revision = revision }
		end
		return { ok = true, revision = revision, view = view }
	end
	return api
end

return table.freeze(ShrineView)
