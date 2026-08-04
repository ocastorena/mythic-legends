-- ServerScriptService/Services/InventoryService/InventoryRemotes

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimitUtil = require(Infrastructure:WaitForChild("RateLimitUtil"))

local InventoryRemotes = {}

local Mythlings: any
local BaseService: any
local deleteMythling: RemoteFunction
local deleteLimiter = RateLimitUtil.new(3, 0.5)
local removingConnection: RBXScriptConnection?

function InventoryRemotes.Init(context, mythlings)
	Mythlings = mythlings
	BaseService = context.Services.BaseService
	deleteMythling = context.Remotes.Inventory.DeleteMythling
end

function InventoryRemotes.Start()
	deleteMythling.OnServerInvoke = function(player: Player, mythlingId: unknown)
		if not deleteLimiter:Allow(player) then
			return { ok = false, code = "RateLimited" }
		end
		if type(mythlingId) ~= "string" or #mythlingId == 0 or #mythlingId > 128 then
			return { ok = false, code = "InvalidMythlingId" }
		end
		if not Mythlings.Get(player, mythlingId) then
			return { ok = false, code = "NotOwned" }
		end

		if not BaseService.RemoveMythlingFromStand(player, mythlingId) then
			return { ok = false, code = "PlacementCleanupFailed" }
		end
		if not Mythlings.Remove(player, mythlingId) then
			return { ok = false, code = "DeleteFailed" }
		end
		return { ok = true }
	end

	removingConnection = Players.PlayerRemoving:Connect(function(player)
		deleteLimiter:Forget(player)
	end)
end

function InventoryRemotes.Stop()
	deleteMythling.OnServerInvoke = nil
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	deleteLimiter:Clear()
end

return InventoryRemotes
