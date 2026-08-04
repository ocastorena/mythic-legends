-- ServerScriptService/Services/InventoryService/Materials
-- Owns the Material portion of each player's inventory.

local Materials = {}

local DataService: any
local sessionsByUserId: { [number]: any }

function Materials.Init(context, sessions)
	DataService = context.Services.DataService
	sessionsByUserId = sessions
end

function Materials.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.materials = DataService.GetSection(player, "materials")
end

function Materials.List(player: Player): any
	return sessionsByUserId[player.UserId].materials
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
