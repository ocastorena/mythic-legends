--!strict
-- ServerScriptService/MainServer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")

local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local RemoteUtil = require(infrastructure:WaitForChild("RemoteUtil"))
local PlayerUtil = require(infrastructure:WaitForChild("PlayerUtil"))
local Trove = require(ReplicatedStorage.Packages.Trove)
local MaterialCatalogUtil = require(ServerScriptService.Shared.MaterialCatalogUtil)
local MythlingCatalogUtil = require(ServerScriptService.Shared.MythlingCatalogUtil)
local EquipmentCatalogUtil = require(ServerScriptService.Shared.EquipmentCatalogUtil)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local MythlingProgression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local Equipment = require(ReplicatedStorage.Shared.Configurations.Equipment)
local EquipmentRecipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local ElementalSwordEffects = require(ReplicatedStorage.Shared.Configurations.ElementalSwordEffects)
local CraftingStations = require(ReplicatedStorage.Shared.Configurations.CraftingStations)

local validMaterials, materialProblem =
	MaterialCatalogUtil.Validate(Materials, Shrines, Inventory.materialStackLimit)
assert(validMaterials, `[MainServer] Invalid Material catalogue: {materialProblem}`)

-- Validate business definitions without exposing unfinished forms to the prototype spawner/UI.
local validForms, formProblem =
	MythlingCatalogUtil.ValidateLaunch(MythlingForms, MythlingProgression.levelCap)
assert(validForms, `[MainServer] Invalid Mythling catalogue: {formProblem}`)

local validEquipment, equipmentProblem = EquipmentCatalogUtil.ValidateLaunch(
	Equipment,
	EquipmentRecipes,
	ElementalSwordEffects,
	Materials,
	CraftingStations
)
assert(validEquipment, `[MainServer] Invalid Equipment catalogue: {equipmentProblem}`)

local log = LogUtil.For("MainServer")
local ServerTypes = require(ServerScriptService.Shared.Types)
local DataService = require(ServerScriptService.Services.DataService)
local CharacterService = require(ServerScriptService.Services.CharacterService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local ProductionService = require(ServerScriptService.Services.ProductionService)
local BaseService = require(ServerScriptService.Services.BaseService)
local MythlingSpawnService = require(ServerScriptService.Services.MythlingSpawnService)
local ClaimService = require(ServerScriptService.Services.ClaimService)
local CombatService = require(ServerScriptService.Services.CombatService)
local CraftingService = require(ServerScriptService.Services.CraftingService)
local AdminCommandService = require(ServerScriptService.Services.AdminCommandService)
local DivineInterventionService = require(ServerScriptService.PostLaunch.DivineInterventionService)
local services: ServerTypes.Services = {
	DataService = {
		RegisterProfileSettlement = DataService.RegisterProfileSettlement,
		RegisterMutationPreparation = DataService.RegisterMutationPreparation,
		Checkpoint = DataService.Checkpoint,
		Load = DataService.Load,
		Release = DataService.Release,
		GetData = DataService.GetData,
		GetLoadedData = DataService.GetLoadedData,
		Update = DataService.Update,
		Transact = DataService.Transact,
		MarkDirty = DataService.MarkDirty,
		SaveNow = DataService.SaveNow,
	},
	InventoryService = {
		EvolveMythling = InventoryService.EvolveMythling,
		SellMythling = InventoryService.SellMythling,
		SellEquipment = InventoryService.SellEquipment,
		SellMaterial = InventoryService.SellMaterial,
		DiscardMaterial = InventoryService.DiscardMaterial,
		UpgradeCapacity = InventoryService.UpgradeCapacity,
		GetMythlingCapacity = InventoryService.GetMythlingCapacity,
		SaveWonMythling = InventoryService.SaveWonMythling,
		GetMythling = InventoryService.GetMythling,
		MarkDirty = InventoryService.MarkDirty,
		AddMaterial = InventoryService.AddMaterial,
	},
	CraftingService = {
		StartJob = CraftingService.StartJob,
		CancelJob = CraftingService.CancelJob,
	},
	CombatService = {
		EquipEquipment = CombatService.EquipEquipment,
		UnequipEquipment = CombatService.UnequipEquipment,
	},
	ProductionService = {
		GetProduction = ProductionService.GetProduction,
		CollectProduction = ProductionService.CollectProduction,
		SettleProduction = ProductionService.SettleProduction,
		SettleShrines = ProductionService.SettleShrines,
		CollectShrine = ProductionService.CollectShrine,
	},
	BaseService = {
		ExpandBase = BaseService.ExpandBase,
		BuildShrine = BaseService.BuildShrine,
		UpgradeShrine = BaseService.UpgradeShrine,
		DismantleShrine = BaseService.DismantleShrine,
		AssignShrineWorker = BaseService.AssignShrineWorker,
		RemoveShrineWorker = BaseService.RemoveShrineWorker,
		GetSpawnPoint = BaseService.GetSpawnPoint,
		HasStand = BaseService.HasStand,
		RemoveMythlingFromStand = BaseService.RemoveMythlingFromStand,
	},
	MythlingSpawnService = {
		GetActiveMythlings = MythlingSpawnService.GetActiveMythlings,
		IsCaptureReady = MythlingSpawnService.IsCaptureReady,
		EndContest = MythlingSpawnService.EndContest,
		SetOvertime = MythlingSpawnService.SetOvertime,
		OnClaimed = MythlingSpawnService.OnClaimed,
	},
	DivineInterventionService = { StartEvent = DivineInterventionService.StartEvent },
}
local ordered: { { name: string, service: ServerTypes.Service } } = {
	{ name = "DivineInterventionService", service = DivineInterventionService },
	{ name = "DataService", service = DataService },
	{ name = "CraftingService", service = CraftingService },
	{ name = "CharacterService", service = CharacterService },
	{ name = "InventoryService", service = InventoryService },
	{ name = "ProductionService", service = ProductionService },
	{ name = "BaseService", service = BaseService },
	{ name = "MythlingSpawnService", service = MythlingSpawnService },
	{ name = "ClaimService", service = ClaimService },
	{ name = "CombatService", service = CombatService },
	{ name = "AdminCommandService", service = AdminCommandService },
}

local function folder(parent: Instance, name: string): Folder
	local value = parent:WaitForChild(name)
	assert(value:IsA("Folder"), `[MainServer] {name} must be a Folder`)
	return value
end

local world = folder(workspace, "World")
local runtime = workspace:WaitForChild("Runtime")
local assets = ReplicatedStorage:WaitForChild("Assets")
local shared = ReplicatedStorage:WaitForChild("Shared")
local configurations = shared:WaitForChild("Configurations")
local serverAssets = ServerStorage:WaitForChild("ServerAssets")

local arena = world:WaitForChild("Arena"):WaitForChild("Markers"):WaitForChild("Bounds")
assert(arena:IsA("BasePart"), "[MainServer] Arena.Markers.Bounds must be a BasePart")
local serviceContext: ServerTypes.Context = {
	Instances = {
		World = world,
		Runtime = runtime,
		Arena = arena,
		Mythlings = runtime:WaitForChild("Mythlings"),
		Bases = folder(runtime, "Bases"),
		BaseIslands = folder(world, "BaseIslands"),
		MythlingAssets = folder(serverAssets, "Mythlings"),
		BaseAssets = serverAssets:WaitForChild("Bases"),
		EquipmentAssets = folder(assets, "Equipment"),
		Templates = assets:WaitForChild("Templates"),
	},
	Configurations = {
		AdminCommands = require(configurations:WaitForChild("AdminCommands")),
		Mythlings = require(configurations:WaitForChild("Mythlings")),
		Materials = Materials,
		Consumables = require(configurations:WaitForChild("Consumables")),
		MythlingSpawns = require(configurations:WaitForChild("MythlingSpawns")),
		Equipment = Equipment,
	},
	Remotes = RemoteUtil.Resolve(ReplicatedStorage),
	Services = services,
}

for _, entry in ipairs(ordered) do
	entry.service.Init(serviceContext)
end
for _, entry in ipairs(ordered) do
	entry.service.Start()
end

local function onPlayerAdded(player: Player)
	DataService.Load(player)
end

local lifetime = Trove.new()
PlayerUtil.OnPlayer(onPlayerAdded, lifetime)
lifetime:Connect(Players.PlayerRemoving, DataService.Release)

game:BindToClose(function()
	lifetime:Destroy()
	for index = #ordered, 1, -1 do
		local service = ordered[index].service
		local ok, err = pcall(service.Stop)
		if not ok then
			log.error(`Service stop failed for {ordered[index].name}`, err)
		end
	end
end)
