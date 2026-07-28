-- ServerScriptService/Services/InventoryService/Items
-- Owns the persisted item portion of each player's inventory.

local Items = {}

local DataService: any
local sessionsByUserId: { [number]: any }

function Items.Init(context, sessions)
	DataService = context.Services.DataService
	sessionsByUserId = sessions
end

function Items.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.items = DataService.GetSection(player, "items")
end

function Items.List(player: Player): any
	local session = sessionsByUserId[player.UserId]
	return session and session.items or {}
end

return Items
