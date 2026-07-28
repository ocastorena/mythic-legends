-- ServerScriptService/Services/InventoryService
-- Owns the player's collectible inventory. Focused modules manage each inventory domain;
-- this service owns their shared session state and exposes the feature-level API.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))

local Mythlings = require(script.Mythlings)
local Resources = require(script.Resources)
local Items = require(script.Items)
local InventoryRemotes = require(script.InventoryRemotes)

local log = LogUtil.For("InventoryService")
local InventoryService = {}
local DataService: any

-- userId -> { mythlings = table, resources = table }
local sessionsByUserId: { [number]: any } = {}

function InventoryService.Init(context)
	DataService = context.Services.DataService
	Mythlings.Init(context, sessionsByUserId)
	Resources.Init(context, sessionsByUserId)
	Items.Init(context, sessionsByUserId)
	InventoryRemotes.Init(context, Mythlings, Resources, Items)

	log.info("Initialized")
end

function InventoryService.Start()
	PlayerUtil.OnPlayer(function(player: Player)
		sessionsByUserId[player.UserId] = {}
		Mythlings.LoadPlayer(player)
		Resources.LoadPlayer(player)
		Items.LoadPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sessionsByUserId[player.UserId] = nil
	end)

	InventoryRemotes.Start()
	log.info("Started")
end

-- Mythling inventory API used by claiming, base placement, and production.
function InventoryService.SaveWonMythling(player: Player, params: any): string?
	return Mythlings.SaveWon(player, params)
end

function InventoryService.RemoveMythling(player: Player, mythlingId: string): boolean
	return Mythlings.Remove(player, mythlingId)
end

function InventoryService.ListMythlings(player: Player): { any }
	return Mythlings.List(player)
end

function InventoryService.GetMythling(player: Player, mythlingId: string): any?
	return Mythlings.Get(player, mythlingId)
end

-- Resource API for production and future crafting services.
function InventoryService.ListResources(player: Player): any?
	return Resources.List(player)
end

function InventoryService.ListItems(player: Player): any?
	return Items.List(player)
end

function InventoryService.AddResource(player: Player, resourceId: string, amount: number)
	Resources.Add(player, resourceId, amount)
end

-- Production and base placement can mutate an owned Mythling entry directly. Keep their
-- persistence signal at the InventoryService boundary instead of exposing DataService.
function InventoryService.MarkDirty(player: Player): boolean
	return DataService.MarkDirty(player)
end

return InventoryService
