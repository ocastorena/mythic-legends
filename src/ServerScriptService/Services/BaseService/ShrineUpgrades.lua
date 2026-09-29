--!strict
-- ServerScriptService/Services/BaseService/ShrineUpgrades
-- Detached payment and level changes; live adapters must commit the complete result atomically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

export type State = ShrineAccrual.State
export type Resources = InventoryCapacity.MaterialState & { gold: number }
export type Metadata = {
	forms: { [string]: ShrineAccrual.FormDefinition },
	shrines: { [string]: ShrineAccrual.ShrineDefinition & { maxLevel: number } },
}
export type Request = {
	shrineInstanceId: string,
	expectedLevel: number,
	expectedMaterialId: string,
	expectedGoldCost: number,
	expectedMaterialQuantity: number,
}
export type Result = {
	production: State,
	materials: InventoryCapacity.MaterialEntries,
	gold: number,
	shrineInstanceId: string,
	previousLevel: number,
	level: number,
	materialId: string,
	goldSpent: number,
	materialsSpent: number,
}

local REQUEST_FIELDS = {
	shrineInstanceId = true,
	expectedLevel = true,
	expectedMaterialId = true,
	expectedGoldCost = true,
	expectedMaterialQuantity = true,
}
local ShrineUpgrades = {}

local function isWhole(value: unknown): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < 2 ^ 53
		and value % 1 == 0
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
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
		not isId(fields.shrineInstanceId)
		or not isId(fields.expectedMaterialId)
		or not isWhole(fields.expectedLevel)
		or (fields.expectedLevel :: number) < 1
		or not isWhole(fields.expectedGoldCost)
		or not isWhole(fields.expectedMaterialQuantity)
	then
		return nil
	end
	return {
		shrineInstanceId = fields.shrineInstanceId :: string,
		expectedLevel = fields.expectedLevel :: number,
		expectedMaterialId = fields.expectedMaterialId :: string,
		expectedGoldCost = fields.expectedGoldCost :: number,
		expectedMaterialQuantity = fields.expectedMaterialQuantity :: number,
	}
end

local function hasValidUpgradePath(
	definition: ShrineAccrual.ShrineDefinition & { maxLevel: number }
): boolean
	if
		not isPlainTable(definition)
		or not isWhole(definition.maxLevel)
		or definition.maxLevel < 1
		or not isPlainTable(definition.levels)
	then
		return false
	end
	local count = 0
	-- Iterate actual entries, not an unbounded range from potentially malformed metadata.
	for levelId, level in definition.levels do
		if
			not isWhole(levelId)
			or levelId < 1
			or levelId > definition.maxLevel
			or not isPlainTable(level)
			or not isWhole(level.capacity)
			or level.capacity < 1
			or level.workerSlots ~= levelId
		then
			return false
		end
		local cost = level.upgradeCost
		if levelId == 1 then
			if cost ~= nil then
				return false
			end
		else
			local previous = definition.levels[levelId - 1]
			if
				not isPlainTable(previous)
				or not isWhole(previous.capacity)
				or previous.capacity >= level.capacity
				or not isPlainTable(cost)
			then
				return false
			end
			local upgradeCost = cost :: Types.ShrineUpgradeCost
			if
				not isWhole(upgradeCost.gold)
				or upgradeCost.gold <= 0
				or not isWhole(upgradeCost.materialQuantity)
				or upgradeCost.materialQuantity <= 0
			then
				return false
			end
		end
		count += 1
	end
	return count == definition.maxLevel
end

local function getAccountingMetadata(metadata: Metadata): ShrineAccrual.Metadata?
	if
		type(metadata) ~= "table"
		or type(metadata.forms) ~= "table"
		or type(metadata.shrines) ~= "table"
	then
		return nil
	end
	-- Project the dictionary's wider definition type without casting the mutable indexer.
	-- Accrual validates the referenced values and never changes static metadata.
	local accounting: ShrineAccrual.Metadata = { forms = metadata.forms, shrines = {} }
	for id, definition in metadata.shrines do
		accounting.shrines[id] = definition
	end
	return accounting
end

-- State, resources and server-authored time must come from one authenticated loaded profile.
-- This reducer supplies no authentication, revision check, receipt, or durable save on its own.
-- Commit production, materials and gold together; preserve jobs/upgrades outside this result.
function ShrineUpgrades.Upgrade(
	state: State,
	resources: Resources,
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
	if now < state.lastAccruedAt then
		return nil, "BackdatedChange"
	end
	local ownedShrine = state.shrines[request.shrineInstanceId]
	if not ownedShrine then
		return nil, "ShrineNotOwned"
	end
	if ownedShrine.level ~= request.expectedLevel then
		return nil, "LevelChanged"
	end
	local definition = metadata.shrines[ownedShrine.shrineId]
	if not hasValidUpgradePath(definition) or ownedShrine.level > definition.maxLevel then
		return nil, "InvalidUpgradeConfiguration"
	end
	if ownedShrine.level == definition.maxLevel then
		return nil, "MaxLevel"
	end
	local nextLevel = ownedShrine.level + 1
	local cost = definition.levels[nextLevel].upgradeCost :: Types.ShrineUpgradeCost
	local materialId = definition.materialId
	if request.expectedMaterialId ~= materialId then
		return nil, "MaterialChanged"
	end
	if
		request.expectedGoldCost ~= cost.gold
		or request.expectedMaterialQuantity ~= cost.materialQuantity
	then
		return nil, "PriceChanged"
	end
	problem = InventoryCapacity.ValidateMaterialState(resources)
	if problem then
		return nil, problem
	end
	if not isWhole(resources.gold) then
		return nil, "InvalidCurrency"
	end
	if resources.gold < cost.gold then
		return nil, "InsufficientGold"
	end
	local ownedMaterial = resources.materials[materialId]
	if not ownedMaterial or ownedMaterial.total < cost.materialQuantity then
		return nil, "InsufficientMaterials"
	end

	-- Settle under the OLD level, so increased capacity cannot recover time spent full.
	local settled, accrualError =
		ShrineAccrual.Accrue(state, now, accounting, production, progression)
	if not settled then
		return nil, accrualError
	end
	local materials: InventoryCapacity.MaterialEntries = {}
	for id, entry in resources.materials do
		materials[id] = table.clone(entry)
	end
	local paidMaterial = materials[materialId]
	paidMaterial.total -= cost.materialQuantity
	if paidMaterial.total == 0 then
		materials[materialId] = nil
	end
	settled.shrines[request.shrineInstanceId].level = nextLevel
	return {
		production = settled,
		materials = materials,
		gold = resources.gold - cost.gold,
		shrineInstanceId = request.shrineInstanceId,
		previousLevel = ownedShrine.level,
		level = nextLevel,
		materialId = materialId,
		goldSpent = cost.gold,
		materialsSpent = cost.materialQuantity,
	},
		nil
end

return table.freeze(ShrineUpgrades)
