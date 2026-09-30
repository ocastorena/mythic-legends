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
local MythlingEvolutionCommand = require(script.MythlingEvolutionCommand)
local MythlingSaleCommand = require(script.MythlingSaleCommand)
local EquipmentSaleCommand = require(script.EquipmentSaleCommand)
local CapacityUpgradePurchase = require(script.CapacityUpgradePurchase)
local MaterialDisposalCommand = require(script.MaterialDisposalCommand)

local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("InventoryService")

local InventoryService = {}
local DataService: ServerTypes.DataApi
local mythlingEvolution: MythlingEvolutionCommand.MythlingEvolutionCommand?
local mythlingSale: MythlingSaleCommand.MythlingSaleCommand?
local equipmentSale: EquipmentSaleCommand.EquipmentSaleCommand?
local capacityUpgrade: CapacityUpgradePurchase.CapacityUpgradePurchase?
local materialDisposal: MaterialDisposalCommand.MaterialDisposalCommand?

-- userId -> { mythlings = table, materials = table, consumables = table }
local sessionsByUserId: ServerTypes.InventorySessions = {}

function InventoryService.Init(serviceContext: ServerTypes.Context)
	DataService = serviceContext.Services.DataService
	mythlingEvolution = MythlingEvolutionCommand.new(DataService)
	mythlingSale = MythlingSaleCommand.new(DataService)
	equipmentSale = EquipmentSaleCommand.new(DataService)
	capacityUpgrade = CapacityUpgradePurchase.new(DataService)
	materialDisposal = MaterialDisposalCommand.new(DataService)
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
	mythlingEvolution = nil
	mythlingSale = nil
	equipmentSale = nil
	capacityUpgrade = nil
	materialDisposal = nil
	table.clear(sessionsByUserId)
end

-- Canonical command; InventoryRemotes owns admission, while GUI integration remains separate.
function InventoryService.EvolveMythling(
	player: Player,
	request: Types.EvolveMythlingRequest
): Types.TransactionResult
	local evolution = mythlingEvolution
	if
		not lifecycle:IsRunning()
		or not evolution
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return evolution.Evolve(player, request)
end

function InventoryService.SellMythling(
	player: Player,
	request: Types.SellMythlingRequest
): Types.TransactionResult
	local sale = mythlingSale
	if
		not lifecycle:IsRunning()
		or not sale
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return sale.Sell(player, request)
end

function InventoryService.SellEquipment(
	player: Player,
	request: Types.SellEquipmentRequest
): Types.TransactionResult
	local sale = equipmentSale
	if
		not lifecycle:IsRunning()
		or not sale
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return sale.Sell(player, request)
end

function InventoryService.UpgradeCapacity(
	player: Player,
	request: Types.UpgradeInventoryCapacityRequest
): Types.TransactionResult
	local purchase = capacityUpgrade
	if
		not lifecycle:IsRunning()
		or not purchase
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return purchase.Upgrade(player, request)
end

function InventoryService.SellMaterial(
	player: Player,
	request: Types.SellMaterialRequest
): Types.TransactionResult
	local disposal = materialDisposal
	if
		not lifecycle:IsRunning()
		or not disposal
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return disposal.Sell(player, request)
end

function InventoryService.DiscardMaterial(
	player: Player,
	request: Types.DiscardMaterialRequest
): Types.TransactionResult
	local disposal = materialDisposal
	if
		not lifecycle:IsRunning()
		or not disposal
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	return disposal.Discard(player, request)
end

-- Mythling inventory API used by claiming, base placement, and production.
function InventoryService.GetMythlingCapacity(player: Player): Types.InventoryCapacity?
	if
		not lifecycle:IsRunning()
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return nil
	end
	return Mythlings.GetCapacity(player)
end

function InventoryService.SaveWonMythling(
	player: Player,
	params: { typeId: string, variantId: string }
): string?
	if
		not lifecycle:IsRunning()
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return nil
	end
	return Mythlings.SaveWon(player, params)
end

function InventoryService.GetMythling(player: Player, mythlingId: string): Types.MythlingEntry?
	return Mythlings.Get(player, mythlingId)
end

-- Material API for production and future crafting services.
function InventoryService.AddMaterial(player: Player, materialId: string, amount: number): boolean
	return Materials.Add(player, materialId, amount)
end

-- Production and base placement can mutate an owned Mythling entry directly. Keep their
-- persistence signal at the InventoryService boundary instead of exposing DataService.
function InventoryService.MarkDirty(player: Player): boolean
	return DataService.MarkDirty(player)
end

return InventoryService
