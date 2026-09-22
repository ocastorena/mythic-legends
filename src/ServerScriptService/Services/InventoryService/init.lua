--!strict
-- ServerScriptService/Services/InventoryService
-- Owns the player's collectible inventory. Focused modules manage each inventory domain;
-- this service owns their shared session state and exposes the feature-level API.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(infrastructure:WaitForChild("PlayerUtil"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Mythlings = require(script.Mythlings)
local Materials = require(script.Materials)
local InventoryRemotes = require(script.InventoryRemotes)

local ServerTypes = require(ServerScriptService.Domain.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("InventoryService")

local InventoryService = {}
local DataService: ServerTypes.DataApi

-- userId -> { mythlings = table, materials = table, consumables = table }
local sessionsByUserId: ServerTypes.InventorySessions = {}

function InventoryService.Init(serviceContext: ServerTypes.Context)
	DataService = serviceContext.Services.DataService
	Mythlings.Init(serviceContext, sessionsByUserId)
	Materials.Init(serviceContext, sessionsByUserId)
	InventoryRemotes.Init(serviceContext)
end

function InventoryService.Start()
	if not lifecycle:Start() then
		return
	end
	PlayerUtil.OnPlayer(function(player: Player, isCurrent: () -> boolean)
		if not DataService.Load(player) or not isCurrent() then
			return
		end
		sessionsByUserId[player.UserId] = {}
		Mythlings.LoadPlayer(player)
		Materials.LoadPlayer(player)
	end, lifecycle.trove)
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		sessionsByUserId[player.UserId] = nil
	end)
	InventoryRemotes.Start()
end

function InventoryService.Stop()
	if not lifecycle:Stop() then
		return
	end
	InventoryRemotes.Stop()
	table.clear(sessionsByUserId)
end

-- Mythling inventory API used by claiming, base placement, and production.
function InventoryService.SaveWonMythling(
	player: Player,
	params: { typeId: string, variantId: string }
): string?
	return Mythlings.SaveWon(player, params)
end

function InventoryService.GetMythling(player: Player, mythlingId: string): Types.MythlingEntry?
	return Mythlings.Get(player, mythlingId)
end

-- Material API for production and future crafting services.
function InventoryService.AddMaterial(player: Player, materialId: string, amount: number)
	Materials.Add(player, materialId, amount)
end

-- Production and base placement can mutate an owned Mythling entry directly. Keep their
-- persistence signal at the InventoryService boundary instead of exposing DataService.
function InventoryService.MarkDirty(player: Player): boolean
	return DataService.MarkDirty(player)
end

return InventoryService
