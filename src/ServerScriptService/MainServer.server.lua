-- ServerScriptService/MainServer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local ServicesFolder = ServerScriptService:WaitForChild("Services")

local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local RemoteUtil = require(Infrastructure:WaitForChild("RemoteUtil"))

local log = LogUtil.For("MainServer")
local SERVICE_ORDER = {
	"DataService",
	"CharacterService",
	"InventoryService",
	"ProductionService",
	"BaseService",
	"MythlingSpawnService",
	"ClaimService",
	"CombatService",
}

local map = workspace:WaitForChild("Map")
local visuals = workspace:WaitForChild("Visuals")
local runtime = workspace:WaitForChild("Runtime")
local assets = ReplicatedStorage:WaitForChild("Assets")
local shared = ReplicatedStorage:WaitForChild("Shared")
local configurations = shared:WaitForChild("Configurations")
local serverAssets = ServerStorage:WaitForChild("ServerAssets")

local context = {
	Instances = {
		Runtime = runtime,
		Arena = map:WaitForChild("Arena"),
		Mythlings = runtime:WaitForChild("Mythlings"),
		Bases = runtime:WaitForChild("Bases"),
		BaseIslands = map:WaitForChild("BaseIslands"),
		Visuals = visuals,
		MythlingAssets = serverAssets:WaitForChild("Mythlings"),
		BaseAssets = serverAssets:WaitForChild("Bases"),
		EquipmentAssets = assets:WaitForChild("Equipment"),
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
	Services = {},
}

local services = {}
local ordered = {}
for _, name in ipairs(SERVICE_ORDER) do
	local service = require(ServicesFolder:WaitForChild(name))
	services[name] = service
	table.insert(ordered, { name = name, service = service })
end
context.Services = services
local DataService = services.DataService

for _, entry in ipairs(ordered) do
	entry.service.Init(context)
end
for _, entry in ipairs(ordered) do
	entry.service.Start()
end

local function onPlayerAdded(player: Player)
	DataService.Load(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(DataService.Release)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	for index = #ordered, 1, -1 do
		local service = ordered[index].service
		local ok, err = pcall(service.Stop)
		if not ok then
			log.error(`Service stop failed for {ordered[index].name}`, err)
		end
	end
end)
