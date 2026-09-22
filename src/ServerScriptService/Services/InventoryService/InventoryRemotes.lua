--!strict
-- ServerScriptService/Services/InventoryService/InventoryRemotes

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))

local ServerTypes = require(ServerScriptService.Domain.Types)
local Mythlings = require(script.Parent.Mythlings)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("InventoryRemotes")

local InventoryRemotes = {}

local BaseService: ServerTypes.BaseApi
local deleteMythling: RemoteFunction
local deleteLimiter = RateLimiter.new(3, 0.5)

function InventoryRemotes.Init(serviceContext: ServerTypes.Context)
	BaseService = serviceContext.Services.BaseService
	deleteMythling = serviceContext.Remotes.Inventory.DeleteMythling
end

function InventoryRemotes.Start()
	if not lifecycle:Start() then
		return
	end
	deleteMythling.OnServerInvoke = function(
		player: Player,
		mythlingId: unknown
	): { ok: boolean, code: string? }
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

	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		deleteLimiter:Forget(player)
	end)
end

function InventoryRemotes.Stop()
	if not lifecycle:Stop() then
		return
	end
	RemoteUtil.ClearServerHandler(deleteMythling)
	deleteLimiter:Clear()
end

return InventoryRemotes
