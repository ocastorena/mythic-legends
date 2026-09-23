--!strict
-- ServerScriptService/Services/InventoryService/Capacity

local Inventory = require(game:GetService("ReplicatedStorage").Shared.Configurations.Inventory)

local Capacity = {}

function Capacity.GetMythlingLimit(purchasedLevel: number?): number
	local level = if type(purchasedLevel) == "number" then purchasedLevel else 0
	if level ~= level or level == math.huge or level == -math.huge then
		level = 0
	end
	local index = math.clamp(math.floor(level), 0, #Inventory.mythlingCapacities - 1) + 1
	return Inventory.mythlingCapacities[index]
end

return table.freeze(Capacity)
