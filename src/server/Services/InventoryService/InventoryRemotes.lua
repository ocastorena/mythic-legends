-- ServerScriptService/Services/InventoryService/InventoryRemotes
-- Keeps the existing client remote contract at the InventoryService boundary.

local InventoryRemotes = {}

local Mythlings: any
local Resources: any
local Items: any
local MythlingsEvent: RemoteEvent
local ResourcesRequest: RemoteFunction
local InventoryRequest: RemoteFunction

function InventoryRemotes.Init(context, mythlings, resources, items)
	Mythlings = mythlings
	Resources = resources
	Items = items
	MythlingsEvent = context.Remotes.MythlingsEvent
	ResourcesRequest = context.Remotes.ResourcesRequest
	InventoryRequest = context.Remotes.InventoryRequest
end

function InventoryRemotes.Start()
	-- BaseService registers its stand-cleanup listener first. Keeping that order ensures a
	-- deleted mythling is removed from its stand before its inventory entry disappears.
	MythlingsEvent.OnServerEvent:Connect(function(player: Player, event: any, payload: any)
		if event ~= "Delete" then
			return
		end

		if Mythlings.Remove(player, payload) then
			MythlingsEvent:FireClient(player, "Update", Mythlings.List(player))
		end
	end)

	ResourcesRequest.OnServerInvoke = function(player: Player, action: string)
		if action == "GetResources" then
			return Resources.List(player)
		end
	end

	InventoryRequest.OnServerInvoke = function(player: Player, action: string)
		if action == "GetItems" then
			return Items.List(player)
		end
	end
end

return InventoryRemotes
