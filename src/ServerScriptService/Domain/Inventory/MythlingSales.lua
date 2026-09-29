--!strict
-- ServerScriptService/Domain/Inventory/MythlingSales
-- Detached removal and fixed-price Gold grants; the live adapter owns the atomic profile commit.

local ShrineAccrual = require(script.Parent.Parent.Production.ShrineAccrual)

export type State = ShrineAccrual.State
export type SaleDefinition = { gold: number }
export type FormDefinition = ShrineAccrual.FormDefinition & { sale: SaleDefinition? }
export type Metadata = {
	forms: { [string]: FormDefinition },
	shrines: { [string]: ShrineAccrual.ShrineDefinition },
}
export type Request = { workerId: string, expectedFormId: string, expectedGoldValue: number }
export type Result = {
	production: State,
	gold: number,
	workerId: string,
	formId: string,
	goldGranted: number,
}

local MAX_SAFE_INTEGER = 9007199254740991
local REQUEST_FIELDS = { workerId = true, expectedFormId = true, expectedGoldValue = true }
local MythlingSales = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isWhole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value % 1 == 0
end

local function isPlainTable(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function parseRequest(rawRequest: unknown): Request?
	if not isPlainTable(rawRequest) then
		return nil
	end
	local fields = rawRequest :: { [string]: unknown }
	for key in fields do
		if type(key) ~= "string" or not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if
		not isId(fields.workerId)
		or not isId(fields.expectedFormId)
		or not isWhole(fields.expectedGoldValue)
		or (fields.expectedGoldValue :: number) <= 0
	then
		return nil
	end
	return {
		workerId = fields.workerId :: string,
		expectedFormId = fields.expectedFormId :: string,
		expectedGoldValue = fields.expectedGoldValue :: number,
	}
end

local function getAccountingMetadata(metadata: Metadata): ShrineAccrual.Metadata?
	if
		not isPlainTable(metadata)
		or not isPlainTable(metadata.forms)
		or not isPlainTable(metadata.shrines)
	then
		return nil
	end
	-- Project the wider definition dictionary; accounting treats server metadata as read-only.
	local accounting: ShrineAccrual.Metadata = { forms = {}, shrines = metadata.shrines }
	for id, definition in metadata.forms do
		accounting.forms[id] = definition
	end
	return accounting
end

-- The ledger must include ALL owned workers and Shrine assignments from the same authenticated
-- loaded profile as Gold. Neither ownership nor time nor metadata may come from client state.
-- Commit the complete ledger, selected owned-record removal, Gold and revision/receipt together.
-- This pure reducer cannot supply authentication, duplicate receipts or durable persistence.
function MythlingSales.Sell(
	state: State,
	gold: number,
	now: number,
	rawRequest: Request,
	metadata: Metadata,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (Result?, string?)
	local request = parseRequest(rawRequest)
	if not request then
		return nil, "InvalidRequest"
	end
	local accounting = getAccountingMetadata(metadata)
	if not accounting then
		return nil, "InvalidMetadata"
	end
	local problem = ShrineAccrual.Validate(state, now, accounting, production, progression)
	if problem then
		return nil, problem
	end
	if not isWhole(gold) then
		return nil, "InvalidCurrency"
	end
	if now < state.lastAccruedAt then
		return nil, "BackdatedChange"
	end
	local worker = state.workers[request.workerId]
	if not worker then
		return nil, "WorkerNotOwned"
	end
	if worker.formId ~= request.expectedFormId then
		return nil, "FormChanged"
	end
	for _, shrine in state.shrines do
		for _, workerId in shrine.workerIdsBySlot do
			if workerId == request.workerId then
				return nil, "WorkerAlreadyAssigned"
			end
		end
	end
	local form = metadata.forms[worker.formId]
	if not isPlainTable(form) then
		return nil, "InvalidSaleDefinition"
	end
	local sale = form.sale
	if sale == nil then
		return nil, "NotSellable"
	end
	if not isPlainTable(sale) or not isWhole(sale.gold) or sale.gold <= 0 then
		return nil, "InvalidSaleDefinition"
	end
	if request.expectedGoldValue ~= sale.gold then
		return nil, "PriceChanged"
	end
	-- Check BEFORE addition so floating-point rounding cannot hide an overflowing Gold grant.
	if sale.gold > MAX_SAFE_INTEGER - gold then
		return nil, "ArithmeticOverflow"
	end

	local settled, accrualError =
		ShrineAccrual.Accrue(state, now, accounting, production, progression)
	if not settled then
		return nil, accrualError
	end
	-- Previously earned Shrine work remains there. Individual XP leaves with the sold instance;
	-- neither pending credit nor levels can transfer to a replacement or modify this fixed price.
	settled.workers[request.workerId] = nil
	return {
		production = settled,
		gold = gold + sale.gold,
		workerId = request.workerId,
		formId = worker.formId,
		goldGranted = sale.gold,
	},
		nil
end

return table.freeze(MythlingSales)
