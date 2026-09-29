--!strict
-- ServerScriptService/Services/InventoryService/Materials
-- Owns the Material portion of each player's inventory.

local ServerScriptService = game:GetService("ServerScriptService")
local InventoryCapacity = require(ServerScriptService.Domain.Inventory.InventoryCapacity)
local ServerTypes = require(ServerScriptService.Domain.Types)

local Materials = {}

local DataService: ServerTypes.DataApi
local sessionsByUserId: ServerTypes.InventorySessions

function Materials.Init(
	serviceContext: ServerTypes.Context,
	sessions: ServerTypes.InventorySessions
)
	DataService = serviceContext.Services.DataService
	sessionsByUserId = sessions
end

function Materials.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.materials = DataService.GetData(player).materials
end

function Materials.List(player: Player): ServerTypes.Materials
	local session = sessionsByUserId[player.UserId]
	assert(session and session.materials, "[InventoryService.Materials] Inventory is unavailable")
	return session.materials
end

function Materials.Add(player: Player, materialId: string, amount: number): boolean
	if
		type(materialId) ~= "string"
		or #materialId == 0
		or #materialId > 128
		or type(amount) ~= "number"
		or amount ~= amount
		or amount <= 0
		or amount >= math.huge
		or amount % 1 ~= 0
	then
		return false
	end
	local result = DataService.Update(player, "GrantMaterial", function(draft)
		if InventoryCapacity.GetMaterialRoom(draft, materialId) < amount then
			return { ok = false, code = "InventoryFull" }
		end
		local current = draft.materials[materialId]
		draft.materials[materialId] = { total = (if current then current.total else 0) + amount }
		return { ok = true }
	end)
	return result.ok
end

return Materials
