--!strict
-- ServerScriptService/Services/InventoryService/MythlingSaleCommand
-- Retry-safe sale: settle work, remove one owned Mythling, and grant Gold in one transaction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerTypes = require(ServerScriptService.Shared.Types)

local Types = require(ReplicatedStorage.Shared.Types)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local GoldCreditUtil = require(ServerScriptService.Shared.GoldCreditUtil)
local MythlingSales = require(script.Parent.MythlingSales)

local MythlingSaleCommand = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type MythlingSaleCommand = {
	Sell: (Player, Types.SellMythlingRequest) -> Types.TransactionResult,
}

local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	workerId = true,
	expectedFormId = true,
	expectedGoldValue = true,
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

local function parseRequest(value: unknown): Types.SellMythlingRequest?
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
		or not isId(fields.workerId)
		or not isId(fields.expectedFormId)
		or not whole(fields.expectedGoldValue)
		or (fields.expectedGoldValue :: number) <= 0
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		workerId = fields.workerId :: string,
		expectedFormId = fields.expectedFormId :: string,
		expectedGoldValue = fields.expectedGoldValue :: number,
	}
end

local function saleMetadata(metadata: ShrineAccrual.Metadata): MythlingSales.Metadata?
	local definitions: MythlingSales.Metadata = { forms = {}, shrines = metadata.shrines }
	for id, definition in metadata.forms do
		local canonical = MythlingForms[id]
		if not canonical then
			return nil
		end
		-- Preserve accounting's definitions; Inventory resolves eligibility and value from form data.
		definitions.forms[id] = {
			element = definition.element,
			baseYieldPerHour = definition.baseYieldPerHour,
			sale = canonical.sale,
		}
	end
	return definitions
end

function MythlingSaleCommand.new(
	DataService: DataSource,
	clock: (() -> number)?
): MythlingSaleCommand
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[InventoryService.MythlingSaleCommand] DataService.GetLoadedData and Transact required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.Sell(
		player: Player,
		rawRequest: Types.SellMythlingRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		-- Preserve every safe-integer digit so distinct prices cannot share a receipt signature.
		local gold = string.format("%.0f", request.expectedGoldValue)
		local signature =
			`worker={#request.workerId}:{request.workerId};form={#request.expectedFormId}:{request.expectedFormId};gold={gold}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Inventory.SellMythling",
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local timestamp = now()
			local sold: MythlingSales.Result? = nil
			local ok, problem = ShrineAccounting.RemoveWorkerToDraft(
				draft,
				timestamp,
				request.workerId,
				function(state, time, metadata, production, progression)
					local definitions = saleMetadata(metadata)
					if not definitions then
						return nil, "InvalidSaleDefinition"
					end
					local result, saleError = MythlingSales.Sell(state, draft.currency.gold, time, {
						workerId = request.workerId,
						expectedFormId = request.expectedFormId,
						expectedGoldValue = request.expectedGoldValue,
					}, definitions, production, progression)
					sold = result
					return if result then result.production else nil, saleError
				end
			)
			local result = sold
			if not ok or not result then
				return { ok = false, code = problem or "SaleFailed" }
			end
			-- Accounting, owned-record removal, Gold, and the receipt commit together; no separate
			-- settlement, deletion, payment, or save call can expose a partially completed sale.
			local creditError = GoldCreditUtil.CreditToDraft(draft, result.goldGranted)
			if creditError then
				return { ok = false, code = creditError }
			end
			return {
				ok = true,
				values = {
					workerId = result.workerId,
					formId = result.formId,
					goldGranted = result.goldGranted,
					settledAt = timestamp,
				},
			}
		end)
	end

	return api
end

return table.freeze(MythlingSaleCommand)
