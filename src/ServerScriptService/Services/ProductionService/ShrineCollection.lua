--!strict
-- ServerScriptService/Services/ProductionService/ShrineCollection
-- Detached settlement and whole-Material transfer; ShrineCollector commits both together.

local ServerScriptService = game:GetService("ServerScriptService")

local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

export type State = ShrineAccrual.State
export type Metadata = ShrineAccrual.Metadata
export type InventoryState = InventoryCapacity.MaterialState
export type Request = { shrineInstanceId: string, expectedMaterialId: string }
export type Result = {
	production: State,
	materials: InventoryCapacity.MaterialEntries,
	shrineInstanceId: string,
	materialId: string,
	collected: number,
	remaining: number,
}

local REQUEST_FIELDS = { shrineInstanceId = true, expectedMaterialId = true }
local ShrineCollection = {}

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function parseRequest(request: unknown): Request?
	if type(request) ~= "table" or getmetatable(request) ~= nil then
		return nil
	end
	local fields = request :: { [string]: unknown }
	for key in fields do
		if not REQUEST_FIELDS[key] then
			return nil
		end
	end
	if not isId(fields.shrineInstanceId) or not isId(fields.expectedMaterialId) then
		return nil
	end
	return {
		shrineInstanceId = fields.shrineInstanceId :: string,
		expectedMaterialId = fields.expectedMaterialId :: string,
	}
end

-- Both views must be derived from the SAME authenticated, loaded player profile. These pure
-- operations supply neither ownership authentication nor request receipts. Never commit just the
-- inventory grant: its matching Shrine debit, accrual cursor, pending work and XP form one result.
function ShrineCollection.Collect(
	state: State,
	inventory: InventoryState,
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
	local problem = ShrineAccrual.Validate(state, now, metadata, production, progression)
	if problem then
		return nil, problem
	end
	if now < state.lastAccruedAt then
		return nil, "BackdatedChange"
	end
	local ownedShrine = state.shrines[request.shrineInstanceId]
	if not ownedShrine then
		return nil, "ShrineNotOwned"
	end
	local materialId = metadata.shrines[ownedShrine.shrineId].materialId
	if materialId ~= request.expectedMaterialId then
		return nil, "MaterialChanged"
	end
	problem = InventoryCapacity.ValidateMaterialState(inventory)
	if problem then
		return nil, problem
	end

	local settled, accrualError =
		ShrineAccrual.Accrue(state, now, metadata, production, progression)
	if not settled then
		return nil, accrualError
	end
	local shrine = settled.shrines[request.shrineInstanceId]
	if shrine.stored == 0 then
		-- A full bag is irrelevant when only unfinished work (or no work) is available.
		return nil, "NothingToCollect"
	end
	local room = InventoryCapacity.GetMaterialRoom(inventory, materialId)
	local amount = math.min(shrine.stored, room)
	if amount <= 0 then
		return nil, "InventoryFull"
	end

	local materials: InventoryCapacity.MaterialEntries = {}
	for id, entry in inventory.materials do
		materials[id] = table.clone(entry)
	end
	local ownedMaterial = materials[materialId]
	if ownedMaterial then
		ownedMaterial.total += amount
	else
		materials[materialId] = { total = amount }
	end
	shrine.stored -= amount
	return {
		production = settled,
		materials = materials,
		shrineInstanceId = request.shrineInstanceId,
		materialId = materialId,
		collected = amount,
		remaining = shrine.stored,
	},
		nil
end

return table.freeze(ShrineCollection)
