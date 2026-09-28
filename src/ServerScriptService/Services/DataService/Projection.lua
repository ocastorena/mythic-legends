--!strict
-- ServerScriptService/Services/DataService/Projection

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Projection = {}

local function clone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = clone(child)
	end
	return result
end

function Projection.Build(data: Types.PlayerDoc): { [string]: any }
	local equipment = {}
	for id, entry in pairs(data.equipment) do
		equipment[id] = { definitionId = entry.definitionId, finishId = entry.finishId }
	end
	-- Explicit allowlist. Profile identity, starter-grant authority, jobs/reservations,
	-- request signatures and resolution receipts never cross the replication boundary.
	return clone({
		currency = data.currency,
		materials = data.materials,
		consumables = data.consumables,
		equipment = equipment,
		combatLoadout = data.combatLoadout,
		mythlings = data.mythlings,
		base = data.base,
		inventoryUpgrades = data.inventoryUpgrades,
		transactionRevision = if data.transactions then data.transactions.revision else 0,
	})
end

return table.freeze(Projection)
