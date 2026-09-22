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

local log = LogUtil.For("MainServer")
local ServerTypes = require(ServerScriptService.Domain.Types)
local DataService = require(ServerScriptService.Services.DataService)
local CharacterService = require(ServerScriptService.Services.CharacterService)
local InventoryService = require(ServerScriptService.Services.InventoryService)
local ProductionService = require(ServerScriptService.Services.ProductionService)
local BaseService = require(ServerScriptService.Services.BaseService)
local MythlingSpawnService = require(ServerScriptService.Services.MythlingSpawnService)
local ClaimService = require(ServerScriptService.Services.ClaimService)
local CombatService = require(ServerScriptService.Services.CombatService)
local services: ServerTypes.Services = {
	DataService = {
		Load = DataService.Load,
		Release = DataService.Release,
		GetData = DataService.GetData,
		GetLoadedData = DataService.GetLoadedData,
		MarkDirty = DataService.MarkDirty,
		SaveNow = DataService.SaveNow,
	},
	InventoryService = {
		SaveWonMythling = InventoryService.SaveWonMythling,
		GetMythling = InventoryService.GetMythling,
		MarkDirty = InventoryService.MarkDirty,
		AddMaterial = InventoryService.AddMaterial,
	},
	ProductionService = {
		GetProduction = ProductionService.GetProduction,
		CollectProduction = ProductionService.CollectProduction,
		SettleProduction = ProductionService.SettleProduction,
	},
	BaseService = {
		HasStand = BaseService.HasStand,
		RemoveMythlingFromStand = BaseService.RemoveMythlingFromStand,
	},
	MythlingSpawnService = {
		GetActiveMythlings = MythlingSpawnService.GetActiveMythlings,
		OnClaimed = MythlingSpawnService.OnClaimed,
	},
}
local ordered: { { name: string, service: ServerTypes.Service } } = {
	{ name = "DataService", service = DataService },
	{ name = "CharacterService", service = CharacterService },
	{ name = "InventoryService", service = InventoryService },
	{ name = "ProductionService", service = ProductionService },
	{ name = "BaseService", service = BaseService },
	{ name = "MythlingSpawnService", service = MythlingSpawnService },
	{ name = "ClaimService", service = ClaimService },
	{ name = "CombatService", service = CombatService },
}

local function folder(parent: Instance, name: string): Folder
	local value = parent:WaitForChild(name)
	assert(value:IsA("Folder"), `[MainServer] {name} must be a Folder`)
	return value
end

local map = workspace:WaitForChild("Map")
local visuals = workspace:WaitForChild("Visuals")
local runtime = workspace:WaitForChild("Runtime")
local assets = ReplicatedStorage:WaitForChild("Assets")
local shared = ReplicatedStorage:WaitForChild("Shared")
local configurations = shared:WaitForChild("Configurations")
local serverAssets = ServerStorage:WaitForChild("ServerAssets")

local arena = map:WaitForChild("Arena")
assert(arena:IsA("BasePart"), "[MainServer] Arena must be a BasePart")
local serviceContext: ServerTypes.Context = {
	Instances = {
		Runtime = runtime,
		Arena = arena,
		Mythlings = runtime:WaitForChild("Mythlings"),
		Bases = folder(runtime, "Bases"),
		BaseIslands = folder(map, "BaseIslands"),
		Visuals = visuals,
		MythlingAssets = folder(serverAssets, "Mythlings"),
		BaseAssets = serverAssets:WaitForChild("Bases"),
		EquipmentAssets = folder(assets, "Equipment"),
		Templates = assets:WaitForChild("Templates"),
	},
	Configurations = {
		Mythlings = require(configurations:WaitForChild("Mythlings")),
		Materials = require(configurations:WaitForChild("Materials")),
		Consumables = require(configurations:WaitForChild("Consumables")),
		MythlingSpawns = require(configurations:WaitForChild("MythlingSpawns")),
		Equipment = require(configurations:WaitForChild("Equipment")),
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
