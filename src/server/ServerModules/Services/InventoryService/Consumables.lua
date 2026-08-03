-- ServerScriptService/ServerModules/Services/InventoryService/Consumables
-- Owns the persisted Consumable portion of each player's inventory.

local Consumables = {}

local DataManager: any
local sessionsByUserId: { [number]: any }

function Consumables.Init(context, sessions)
	DataManager = context.Services.DataManager
	sessionsByUserId = sessions
end

function Consumables.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.consumables = DataManager.GetSection(player, "consumables")
end

return Consumables
