-- ServerScriptService/Services/ProductionService/Accrual
-- All mutations use an already-loaded profile and never yield. Settle and transfer both
-- sides before publishing so collection cannot expose an intermediate grant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Ledger = require(script.Parent.ProductionLedger)

local Accrual = {}
export type ProductionStatus = Types.ProductionStatus
export type ProductionCollection = Types.ProductionCollection

function Accrual.new(dataService, mythlingsData, ownsStand, clock: (() -> number)?)
	local now = clock or os.time
	local api = {}

	local function resolve(player: Player, standId: number)
		local base = dataService.GetLoadedSection(player, "base")
		local mythlings = dataService.GetLoadedSection(player, "mythlings")
		local materials = dataService.GetLoadedSection(player, "materials")
		if not base or not mythlings or not materials then
			return nil, "DataUnavailable"
		end
		local stand = base.stands[tostring(standId)]
		if not (stand and stand.production) and not ownsStand(player, standId) then
			return nil, "StandUnavailable"
		end
		local definition = nil
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
		local timestamp = now()
		local state = (stand and stand.production) or { lastAccruedAt = timestamp, materials = {} }
		local settled = Ledger.Accrue(
			state,
			timestamp,
			if definition then definition.materialId else nil,
			if definition then definition.baseRate else 0,
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
		}, nil
	end

	local function commit(resolved, state)
		local stand = resolved.stand or {}
		stand.production = state
		resolved.base.stands[tostring(resolved.standId)] = stand
	end

	function api.Get(player: Player, standId: number): ProductionStatus?
		local resolved = resolve(player, standId)
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
			rate = if definition then definition.baseRate else 0,
			progress = if work then work.progress else 0,
			materials = resolved.settled.materials,
			active = definition ~= nil,
			sampledAt = resolved.timestamp,
		}
	end

	function api.Settle(player: Player, standId: number): (boolean, string?)
		local resolved, code = resolve(player, standId)
		if not resolved then
			return false, code
		end
		commit(resolved, resolved.settled)
		dataService.MarkDirty(player)
		return true
	end

	function api.Collect(player: Player, standId: number): (boolean, string?, ProductionCollection?)
		local resolved, code = resolve(player, standId)
		if not resolved then
			return false, code, nil
		end
		local remaining, amounts = Ledger.Collect(resolved.settled)
		local total = 0
		for _, amount in pairs(amounts) do
			total += amount
		end
		if total == 0 then
			return false, "NothingToCollect", nil
		end

		-- Inventory capacity/reservations are not implemented in the prototype.
		-- Future partial collection must leave output that cannot fit in this ledger.
		for materialId, amount in pairs(amounts) do
			local owned = resolved.materials[materialId]
			if owned then
				owned.total += amount
			else
				resolved.materials[materialId] = { total = amount }
			end
		end
		commit(resolved, remaining)
		dataService.MarkDirty(player)
		return true, nil, { collected = total, remaining = 0, materials = amounts }
	end

	return api
end

return Accrual
