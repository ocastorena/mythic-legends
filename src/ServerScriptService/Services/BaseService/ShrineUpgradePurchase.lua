--!strict
-- ServerScriptService/Services/BaseService/ShrineUpgradePurchase
-- Retry-safe purchase: settle at the old level, pay, and upgrade in one profile transaction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerTypes = require(ServerScriptService.Shared.Types)

local Types = require(ReplicatedStorage.Shared.Types)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local ShrineUpgrades = require(script.Parent.ShrineUpgrades)

local ShrineUpgradePurchase = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type ShrineUpgradePurchase = {
	Upgrade: (Player, Types.UpgradeShrineRequest) -> Types.TransactionResult,
}

local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	shrineInstanceId = true,
	expectedLevel = true,
	expectedMaterialId = true,
	expectedGoldCost = true,
	expectedMaterialQuantity = true,
}

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function currentRevision(data: Types.PlayerDoc): number
	local state: unknown = data.transactions
	if state == nil then
		return 0
	end
	if type(state) == "table" then
		local revision = (state :: { [string]: unknown }).revision
		if whole(revision) then
			return revision :: number
		end
	end
	return -1
end

local function parseRequest(value: unknown): Types.UpgradeShrineRequest?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	local fields = value :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.shrineInstanceId)
		or not whole(fields.expectedLevel)
		or (fields.expectedLevel :: number) < 1
		or not isId(fields.expectedMaterialId)
		or not whole(fields.expectedGoldCost)
		or not whole(fields.expectedMaterialQuantity)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		shrineInstanceId = fields.shrineInstanceId :: string,
		expectedLevel = fields.expectedLevel :: number,
		expectedMaterialId = fields.expectedMaterialId :: string,
		expectedGoldCost = fields.expectedGoldCost :: number,
		expectedMaterialQuantity = fields.expectedMaterialQuantity :: number,
	}
end

local function upgradeMetadata(metadata: ShrineAccrual.Metadata): ShrineUpgrades.Metadata?
	local definitions: ShrineUpgrades.Metadata = { forms = metadata.forms, shrines = {} }
	for id, definition in metadata.shrines do
		local canonical = Shrines[id]
		if not canonical then
			return nil
		end
		-- Keep accounting's same definitions; only Base's purchase policy needs maxLevel.
		definitions.shrines[id] = {
			element = definition.element,
			materialId = definition.materialId,
			levels = definition.levels,
			maxLevel = canonical.maxLevel,
		}
	end
	return definitions
end

function ShrineUpgradePurchase.new(
	DataService: DataSource,
	clock: (() -> number)?
): ShrineUpgradePurchase
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[BaseService.ShrineUpgradePurchase] DataService.GetLoadedData and Transact required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.Upgrade(
		player: Player,
		rawRequest: Types.UpgradeShrineRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		-- Whole-number formatting retains every safe integer digit in rejected as well as
		-- accepted quotes. Normalize signed zero; equivalent numeric selections share intent.
		local level = string.format("%.0f", request.expectedLevel)
		local gold = string.format("%.0f", request.expectedGoldCost + 0)
		local quantity = string.format("%.0f", request.expectedMaterialQuantity + 0)
		local signature =
			`shrine={#request.shrineInstanceId}:{request.shrineInstanceId};level={level};material={#request.expectedMaterialId}:{request.expectedMaterialId};gold={gold};quantity={quantity}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Base.UpgradeShrine",
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local timestamp = now()
			local upgraded: ShrineUpgrades.Result? = nil
			local ok, problem = ShrineAccounting.ChangeShrineLevelToDraft(
				draft,
				timestamp,
				request.shrineInstanceId,
				function(state, time, metadata, production, progression)
					local definitions = upgradeMetadata(metadata)
					if not definitions then
						return nil, "InvalidUpgradeConfiguration"
					end
					local result, upgradeError = ShrineUpgrades.Upgrade(
						state,
						{
							gold = draft.currency.gold,
							materials = draft.materials,
							inventoryUpgrades = draft.inventoryUpgrades,
							craftingJobs = draft.craftingJobs,
						},
						time,
						{
							shrineInstanceId = request.shrineInstanceId,
							expectedLevel = request.expectedLevel,
							expectedMaterialId = request.expectedMaterialId,
							expectedGoldCost = request.expectedGoldCost,
							expectedMaterialQuantity = request.expectedMaterialQuantity,
						},
						definitions,
						production,
						progression
					)
					upgraded = result
					return if result then result.production else nil, upgradeError
				end
			)
			local result = upgraded
			if not ok or not result then
				return { ok = false, code = problem or "UpgradeFailed" }
			end
			-- The accepted accounting and level change, both payment debits, and receipt must
			-- commit together. No separate settlement, Material consumption, or save call.
			draft.materials = result.materials
			draft.currency.gold = result.gold
			return {
				ok = true,
				values = {
					shrineInstanceId = result.shrineInstanceId,
					previousLevel = result.previousLevel,
					level = result.level,
					materialId = result.materialId,
					goldSpent = result.goldSpent,
					materialsSpent = result.materialsSpent,
					settledAt = timestamp,
				},
			}
		end)
	end

	return api
end

return table.freeze(ShrineUpgradePurchase)
