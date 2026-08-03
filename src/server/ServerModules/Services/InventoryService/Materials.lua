-- ServerScriptService/ServerModules/Services/InventoryService/Materials
-- Owns the Material portion of each player's inventory.

local Materials = {}

local DataManager: any
local sessionsByUserId: { [number]: any }

function Materials.Init(context, sessions)
	DataManager = context.Services.DataManager
	sessionsByUserId = sessions
end

function Materials.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.materials = DataManager.GetSection(player, "materials")
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
	DataManager.MarkDirty(player)
end

return Materials
