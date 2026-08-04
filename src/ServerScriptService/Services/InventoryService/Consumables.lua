-- ServerScriptService/Services/InventoryService/Consumables
-- Owns the persisted Consumable portion of each player's inventory.

local Consumables = {}

local DataService: any
local sessionsByUserId: { [number]: any }

function Consumables.Init(context, sessions)
	DataService = context.Services.DataService
	sessionsByUserId = sessions
end

function Consumables.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.consumables = DataService.GetSection(player, "consumables")
end

return Consumables
