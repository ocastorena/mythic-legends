--!strict
-- ServerScriptService/Services/ProductionService/Accrual
-- All mutations use an already-loaded profile and never yield. Settle and transfer both
-- sides before publishing so collection cannot expose an intermediate grant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local Ledger = require(ServerScriptService.Shared.ProductionLedger)

local Accrual = {}
export type ProductionStatus = Types.ProductionStatus
export type ProductionCollection = Types.ProductionCollection

export type ProductionData = Types.PlayerDoc
export type UpdateDecision = Types.TransactionOutcome
export type UpdateResult = Types.TransactionResult
export type DataSource = {
	GetLoadedData: (Player) -> ProductionData?,
	Update: (Player, string, (ProductionData) -> UpdateDecision) -> UpdateResult,
}
export type Definitions = { [string]: Types.MythlingDef }
type Resolved = {
	base: { stands: { [string]: { production: Types.StandProduction? } } },
	stand: { production: Types.StandProduction? }?,
	standId: number,
	materials: { [string]: Types.MaterialEntry },
	settled: Types.StandProduction,
	definition: Types.MythlingProduction?,
	timestamp: number,
}
export type Accrual = {
	Get: (Player, number) -> ProductionStatus?,
	Settle: (Player, number) -> (boolean, string?),
	Collect: (Player, number) -> (boolean, string?, ProductionCollection?),
}

function Accrual.new(
	DataService: DataSource,
	mythlingsData: Definitions,
	ownsStand: (Player, number) -> boolean,
	clock: (() -> number)?
): Accrual
	local now: () -> number = clock or function()
		return os.time()
	end
	local api = {}

	local function resolve(
		player: Player,
		data: ProductionData,
		standId: number,
		timestamp: number
	): (Resolved?, string?)
		local base, mythlings, materials = data.base, data.mythlings, data.materials
		local stand = base.stands[tostring(standId)]
		if not ownsStand(player, standId) then
			return nil, "StandUnavailable"
		end
		local definition: Types.MythlingProduction? = nil
		for _, entry in pairs(mythlings) do
			if entry.standId == standId then
				if definition then
					return nil, "ConflictingAssignment"
				end
				local metadata = mythlingsData[entry.typeId]
				if not metadata or not metadata.production then
					return nil, "InvalidDefinition"
				end
				definition = metadata.production
			end
		end
		local state = (stand and stand.production) or { lastAccruedAt = timestamp, materials = {} }
		local settled = Ledger.Accrue(
			state,
			timestamp,
			if definition then definition.materialId else nil,
			if definition then definition.materialsPerMinute else 0,
			if definition then definition.baseCapacity else 0
		)
		return {
			base = base,
			stand = stand,
			standId = standId,
			materials = materials,
			settled = settled,
			definition = definition,
			timestamp = timestamp,
		},
			nil
	end

	local function commit(resolved: Resolved, state: Types.StandProduction)
		local stand: { production: Types.StandProduction? } = resolved.stand or {}
		stand.production = state
		resolved.base.stands[tostring(resolved.standId)] = stand
	end

	function api.Get(player: Player, standId: number): ProductionStatus?
		local data = DataService.GetLoadedData(player)
		if not data then
			return nil
		end
		local resolved = resolve(player, data, standId, now())
		if not resolved then
			return nil
		end
		local production = 0
		for _, work in pairs(resolved.settled.materials) do
			production += work.stored
		end
		local definition = resolved.definition
		local work = definition and resolved.settled.materials[definition.materialId]
		return {
			production = production,
			capacity = if definition then definition.baseCapacity else 0,
			rate = if definition then definition.materialsPerMinute else 0,
			progress = if work then work.progress else 0,
			materials = resolved.settled.materials,
			active = definition ~= nil,
			sampledAt = resolved.timestamp,
		}
	end

	function api.Settle(player: Player, standId: number): (boolean, string?)
		local result = DataService.Update(
			player,
			"Production.Settle",
			function(draft: ProductionData)
				local resolved, code = resolve(player, draft, standId, now())
				if not resolved then
					return { ok = false, code = code }
				end
				commit(resolved, resolved.settled)
				return { ok = true }
			end
		)
		return result.ok, result.code
	end

	function api.Collect(player: Player, standId: number): (boolean, string?, ProductionCollection?)
		local collection: ProductionCollection? = nil
		local result = DataService.Update(
			player,
			"Production.Collect",
			function(draft: ProductionData)
				local resolved, code = resolve(player, draft, standId, now())
				if not resolved then
					return { ok = false, code = code }
				end

				local materialIds = {}
				local storedTotal = 0
				for materialId, work in pairs(resolved.settled.materials) do
					if work.stored > 0 then
						table.insert(materialIds, materialId)
						storedTotal += work.stored
					end
				end
				if storedTotal == 0 then
					return { ok = false, code = "NothingToCollect" }
				end
				table.sort(materialIds)

				local amounts = {}
				local collectedTotal = 0
				for _, materialId in ipairs(materialIds) do
					local work = resolved.settled.materials[materialId]
					local amount =
						math.min(work.stored, InventoryCapacity.GetMaterialRoom(draft, materialId))
					if amount > 0 then
						local owned = resolved.materials[materialId]
						if owned then
							owned.total += amount
						else
							resolved.materials[materialId] = { total = amount }
						end
						work.stored -= amount
						amounts[materialId] = amount
						collectedTotal += amount
					end
				end
				if collectedTotal == 0 then
					return { ok = false, code = "InventoryFull" }
				end

				local remainingTotal = storedTotal - collectedTotal
				commit(resolved, resolved.settled)
				collection = {
					collected = collectedTotal,
					remaining = remainingTotal,
					materials = amounts,
				}
				return {
					ok = true,
					values = { collected = collectedTotal, remaining = remainingTotal },
				}
			end
		)
		if not result.ok then
			return false, result.code, nil
		end
		return true, nil, collection
	end

	return api
end

return Accrual
