--!strict
-- ServerScriptService/Services/InventoryService/MaterialDisposalCommand
-- Sell or discard an exact owned Material selection without touching production or reservations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type MaterialDisposalCommand = {
	Sell: (Player, Types.SellMaterialRequest) -> Types.TransactionResult,
	Discard: (Player, Types.DiscardMaterialRequest) -> Types.TransactionResult,
}
type Request = {
	requestId: string,
	expectedRevision: number,
	materialId: string,
	quantity: number,
	expectedOwnedQuantity: number,
	expectedUnitGold: number?,
}

local MaterialDisposalCommand = {}
local MAX_SAFE_INTEGER = 9007199254740991
local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	materialId = true,
	quantity = true,
	expectedOwnedQuantity = true,
}
local ELEMENTS: { [string]: boolean } = {
	Fire = true,
	Water = true,
	Earth = true,
	Air = true,
	Light = true,
	Dark = true,
}
table.freeze(ELEMENTS)

local function whole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value % 1 == 0
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function isPlain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
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

local function parseRequest(value: unknown, isSale: boolean): Request?
	if not isPlain(value) then
		return nil
	end
	local fields = value :: { [string]: unknown }
	for key in fields do
		if
			type(key) ~= "string"
			or (not REQUEST_FIELDS[key] and not (isSale and key == "expectedUnitGold"))
		then
			return nil
		end
	end
	if
		not isId(fields.requestId)
		or not whole(fields.expectedRevision)
		or not isId(fields.materialId)
		or not whole(fields.quantity)
		or (fields.quantity :: number) < 1
		or not whole(fields.expectedOwnedQuantity)
		or (
			isSale
			and (not whole(fields.expectedUnitGold) or (fields.expectedUnitGold :: number) < 1)
		)
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		materialId = fields.materialId :: string,
		quantity = fields.quantity :: number,
		expectedOwnedQuantity = fields.expectedOwnedQuantity :: number,
		expectedUnitGold = if isSale then fields.expectedUnitGold :: number else nil,
	}
end

local function validMaterial(definition: Types.MaterialDef?): boolean
	if not definition or not isPlain(definition) then
		return false
	end
	local element = definition.element
	return definition.launchEnabled == true
		and definition.category == "material"
		and element ~= nil
		and ELEMENTS[element] == true
		and whole(definition.stackLimit)
		and definition.stackLimit == Inventory.materialStackLimit
end

function MaterialDisposalCommand.new(DataService: DataSource): MaterialDisposalCommand
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[InventoryService.MaterialDisposalCommand] DataService.GetLoadedData and Transact required"
	)
	local api = {}

	local function run(
		player: Player,
		rawRequest: unknown,
		isSale: boolean
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest, isSale)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		local quantity = string.format("%.0f", request.quantity + 0)
		local owned = string.format("%.0f", request.expectedOwnedQuantity + 0)
		local signature =
			`material={#request.materialId}:{request.materialId};quantity={quantity};owned={owned}`
		if isSale then
			-- The closed sale parser requires this positive quote; discard never accepts one.
			local quote = string.format("%.0f", (request.expectedUnitGold :: number) + 0)
			signature ..= `;unitGold={quote}`
		end
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = if isSale then "Inventory.SellMaterial" else "Inventory.DiscardMaterial",
			signature = signature,
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			if draft.version ~= PlayerData.schemaVersion then
				return { ok = false, code = "UnsupportedVersion" }
			end
			local materialError = InventoryCapacity.ValidateMaterialState(draft)
			if materialError then
				return { ok = false, code = materialError }
			end
			local definition = Materials[request.materialId]
			if not validMaterial(definition) then
				return { ok = false, code = "InvalidMaterial" }
			end
			local entry = draft.materials[request.materialId]
			local actual = if entry then entry.total else 0
			if actual ~= request.expectedOwnedQuantity then
				return { ok = false, code = "QuantityChanged" }
			end
			if not entry or actual == 0 then
				return { ok = false, code = "NotOwned" }
			end
			if request.quantity > actual then
				return { ok = false, code = "InsufficientMaterials" }
			end
			local goldGranted = 0
			local unitGold: number? = nil
			local goldBalance: number? = nil
			if isSale then
				local configuredGold = definition.sellGold
				if not whole(configuredGold) or (configuredGold :: number) < 1 then
					return { ok = false, code = "InvalidSaleDefinition" }
				end
				local price = configuredGold :: number
				if price ~= request.expectedUnitGold then
					return { ok = false, code = "PriceChanged" }
				end
				if not isPlain(draft.currency) or not whole(draft.currency.gold) then
					return { ok = false, code = "InvalidCurrency" }
				end
				-- Bound multiplication first, then validate the exact product and pre-addition
				-- headroom. Rounding must never turn an overflowing grant into an accepted sale.
				if request.quantity > math.floor(MAX_SAFE_INTEGER / price) then
					return { ok = false, code = "ArithmeticOverflow" }
				end
				goldGranted = request.quantity * price
				if
					not whole(goldGranted)
					or goldGranted > MAX_SAFE_INTEGER - draft.currency.gold
				then
					return { ok = false, code = "ArithmeticOverflow" }
				end
				local balance = draft.currency.gold + goldGranted
				if not whole(balance) then
					return { ok = false, code = "ArithmeticOverflow" }
				end
				unitGold = price
				goldBalance = balance
			end
			local remaining = actual - request.quantity
			entry.total = remaining
			if remaining == 0 then
				draft.materials[request.materialId] = nil
			end
			local values: Types.TransactionValues = {
				materialId = request.materialId,
				quantity = request.quantity,
				remainingQuantity = remaining,
				goldGranted = goldGranted,
			}
			if unitGold ~= nil and goldBalance ~= nil then
				draft.currency.gold = goldBalance
				values.unitGold = unitGold
				values.goldBalance = goldBalance
			end
			return { ok = true, values = values }
		end)
	end

	function api.Sell(player: Player, request: Types.SellMaterialRequest): Types.TransactionResult
		return run(player, request, true)
	end

	function api.Discard(
		player: Player,
		request: Types.DiscardMaterialRequest
	): Types.TransactionResult
		return run(player, request, false)
	end

	return api
end

return table.freeze(MaterialDisposalCommand)
