-- ServerScriptService/ServerModules/Services/InventoryService/InventoryRemotes
-- Owns the canonical client request contract at the InventoryService boundary.

local InventoryRemotes = {}

local Mythlings: any
local Materials: any
local Consumables: any
local MythlingsEvent: RemoteEvent
local MaterialsRequest: RemoteFunction
local ConsumablesRequest: RemoteFunction

function InventoryRemotes.Init(context, mythlings, materials, consumables)
	Mythlings = mythlings
	Materials = materials
	Consumables = consumables
	MythlingsEvent = context.Remotes.MythlingsEvent
	MaterialsRequest = context.Remotes.MaterialsRequest
	ConsumablesRequest = context.Remotes.ConsumablesRequest
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

	MaterialsRequest.OnServerInvoke = function(player: Player, action: string)
		if action == "GetMaterials" then
			return Materials.List(player)
		end
	end

	ConsumablesRequest.OnServerInvoke = function(player: Player, action: string)
		if action == "GetConsumables" then
			return Consumables.List(player)
		end
	end
end

return InventoryRemotes
