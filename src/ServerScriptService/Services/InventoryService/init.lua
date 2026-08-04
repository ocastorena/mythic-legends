-- ServerScriptService/Services/InventoryService
-- Owns the player's collectible inventory. Focused modules manage each inventory domain;
-- this service owns their shared session state and exposes the feature-level API.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))

local Mythlings = require(script.Mythlings)
local Materials = require(script.Materials)
local Consumables = require(script.Consumables)
local InventoryRemotes = require(script.InventoryRemotes)

local log = LogUtil.For("InventoryService")
local InventoryService = {}
local DataService: any

-- userId -> { mythlings = table, materials = table, consumables = table }
local sessionsByUserId: { [number]: any } = {}
local connections: { RBXScriptConnection } = {}

function InventoryService.Init(context)
	DataService = context.Services.DataService
	Mythlings.Init(context, sessionsByUserId)
	Materials.Init(context, sessionsByUserId)
	Consumables.Init(context, sessionsByUserId)
	InventoryRemotes.Init(context, Mythlings)

end

function InventoryService.Stop()
	InventoryRemotes.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(sessionsByUserId)
end

function InventoryService.Start()
	table.insert(connections, PlayerUtil.OnPlayer(function(player: Player)
		sessionsByUserId[player.UserId] = {}
		Mythlings.LoadPlayer(player)
		Materials.LoadPlayer(player)
		Consumables.LoadPlayer(player)
	end))

	table.insert(connections, Players.PlayerRemoving:Connect(function(player: Player)
		sessionsByUserId[player.UserId] = nil
	end))

	InventoryRemotes.Start()
end

-- Mythling inventory API used by claiming, base placement, and production.
function InventoryService.SaveWonMythling(player: Player, params: any): string?
	return Mythlings.SaveWon(player, params)
end

function InventoryService.GetMythling(player: Player, mythlingId: string): any?
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
