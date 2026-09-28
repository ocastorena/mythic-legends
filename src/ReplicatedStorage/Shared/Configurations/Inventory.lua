--!strict
-- ReplicatedStorage/Shared/Configurations/Inventory

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

local capacityByCategory: { [string]: { number } } = {
	materials = { 12, 24, 36 },
	mythlings = { 24, 36, 48 },
	equipment = { 12, 24, 36 },
}

return FreezeUtil.DeepFreeze({
	capacityByCategory = capacityByCategory,
	materialStackLimit = 1_000,
	-- Compatibility for the existing capture path while consumers adopt category capacity.
	mythlingCapacities = capacityByCategory.mythlings,
})
