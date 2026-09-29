--!strict
-- ServerScriptService/Services/InventoryService/EquipmentSaleCommand
-- Sell one unequipped owned instance at its current catalogue price without releasing refunds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local GoldCreditUtil = require(ServerScriptService.Shared.GoldCreditUtil)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Transact: (
		Player,
		Types.TransactionRequest,
		ServerTypes.ProfileMutation
	) -> Types.TransactionResult,
}
export type EquipmentSaleCommand = {
	Sell: (Player, Types.SellEquipmentRequest) -> Types.TransactionResult,
}

local EquipmentSaleCommand = {}
local REQUEST_FIELDS = {
	requestId = true,
	expectedRevision = true,
	instanceId = true,
	expectedDefinitionId = true,
	expectedFinishId = true,
	expectedGold = true,
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

local function parseRequest(value: unknown): Types.SellEquipmentRequest?
	if not isPlain(value) then
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
		or not isId(fields.instanceId)
		or not isId(fields.expectedDefinitionId)
		or (fields.expectedFinishId ~= nil and not isId(fields.expectedFinishId))
		or not whole(fields.expectedGold)
		or (fields.expectedGold :: number) <= 0
	then
		return nil
	end
	return {
		requestId = fields.requestId :: string,
		expectedRevision = fields.expectedRevision :: number,
		instanceId = fields.instanceId :: string,
		expectedDefinitionId = fields.expectedDefinitionId :: string,
		expectedFinishId = fields.expectedFinishId :: string?,
		expectedGold = fields.expectedGold :: number,
	}
end

local function idPart(value: string): string
	return `{#value}:{value}`
end

function EquipmentSaleCommand.new(DataService: DataSource): EquipmentSaleCommand
	assert(
		type(DataService) == "table"
			and type(DataService.GetLoadedData) == "function"
			and type(DataService.Transact) == "function",
		"[InventoryService.EquipmentSaleCommand] DataService.GetLoadedData and Transact required"
	)
	local api = {}

	function api.Sell(
		player: Player,
		rawRequest: Types.SellEquipmentRequest
	): Types.TransactionResult
		local loaded = DataService.GetLoadedData(player)
		if not loaded then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local request = parseRequest(rawRequest)
		if not request then
			return { ok = false, code = "InvalidRequest", revision = currentRevision(loaded) }
		end
		-- A missing plain-item finish differs from every explicit ID. Preserve all safe-integer
		-- price digits so distinct selections cannot reuse the same transaction receipt.
		local finish = if request.expectedFinishId then idPart(request.expectedFinishId) else "none"
		local gold = string.format("%.0f", request.expectedGold)
		local signature = `instance={idPart(request.instanceId)};definition={idPart(
			request.expectedDefinitionId
		)};finish={finish};gold={gold}`
		return DataService.Transact(player, {
			id = request.requestId,
			expectedRevision = request.expectedRevision,
			operation = "Inventory.SellEquipment",
			signature = signature,
		}, function(draft: Types.PlayerDoc, _now: number): Types.TransactionOutcome
			if draft.version ~= PlayerData.schemaVersion then
				return { ok = false, code = "UnsupportedVersion" }
			end
			if not isPlain(draft.equipment) then
				return { ok = false, code = "InvalidInventoryState" }
			end
			local entry = draft.equipment[request.instanceId]
			if entry == nil then
				return { ok = false, code = "NotOwned" }
			end
			if
				not isPlain(entry)
				or not isId(entry.definitionId)
				or (entry.finishId ~= nil and not isId(entry.finishId))
				or (entry.isStarterGrant ~= nil and type(entry.isStarterGrant) ~= "boolean")
			then
				return { ok = false, code = "InvalidInventoryState" }
			end
			local loadout = draft.combatLoadout
			if
				not isPlain(loadout)
				or (loadout.primaryWeaponInstanceId ~= nil and not isId(
					loadout.primaryWeaponInstanceId
				))
				or (loadout.shieldInstanceId ~= nil and not isId(loadout.shieldInstanceId))
			then
				return { ok = false, code = "InvalidLoadoutState" }
			end
			if entry.isStarterGrant == true then
				return { ok = false, code = "StarterProtected" }
			end
			if
				loadout.primaryWeaponInstanceId == request.instanceId
				or loadout.shieldInstanceId == request.instanceId
			then
				return { ok = false, code = "Equipped" }
			end
			if
				entry.definitionId ~= request.expectedDefinitionId
				or entry.finishId ~= request.expectedFinishId
			then
				return { ok = false, code = "EquipmentChanged" }
			end
			local resolved = EquipmentCatalog.Resolve(entry.definitionId, entry.finishId)
			local price = if resolved then resolved.sellGold else nil
			if not whole(price) or (price :: number) <= 0 then
				return { ok = false, code = "NotSellable" }
			end
			local goldGranted = price :: number
			if goldGranted ~= request.expectedGold then
				return { ok = false, code = "PriceChanged" }
			end
			local creditError = GoldCreditUtil.CreditToDraft(draft, goldGranted)
			if creditError then
				return { ok = false, code = creditError }
			end
			draft.equipment[request.instanceId] = nil
			local values: Types.TransactionValues = {
				instanceId = request.instanceId,
				definitionId = entry.definitionId,
				goldGranted = goldGranted,
				goldBalance = draft.currency.gold,
			}
			if entry.finishId ~= nil then
				values.finishId = entry.finishId
			end
			return { ok = true, values = values }
		end)
	end

	return api
end

return table.freeze(EquipmentSaleCommand)
