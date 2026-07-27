-- ServerScriptService/Services/InventoryService/Resources
-- Owns the resource portion of each player's inventory.

local Resources = {}

local DataService: any
local sessionsByUserId: { [number]: any }

function Resources.Init(context, sessions)
	DataService = context.Services.DataService
	sessionsByUserId = sessions
end

function Resources.LoadPlayer(player: Player)
	local session = sessionsByUserId[player.UserId]
	session.resources = DataService.GetSection(player, "resources")
end

function Resources.List(player: Player): any
	return sessionsByUserId[player.UserId].resources
end

function Resources.Add(player: Player, resourceId: string, amount: number)
	local resources = Resources.List(player)
	if not resources[resourceId] then
		resources[resourceId] = { total = amount }
	else
		resources[resourceId].total += amount
	end
	DataService.MarkDirty(player)
end

return Resources
