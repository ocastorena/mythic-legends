--!strict
-- ServerScriptService/Services/InventoryService/Materials
-- Owns the Material portion of each player's inventory.

local ServerTypes = require(game:GetService("ServerScriptService").Domain.Types)

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

function Materials.Add(player: Player, materialId: string, amount: number)
	local materials = Materials.List(player)
	if not materials[materialId] then
		materials[materialId] = { total = amount }
	else
		materials[materialId].total += amount
	end
	DataService.MarkDirty(player)
end

return Materials
