-- ServerScriptService/MainServer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ServerModules = ServerScriptService:WaitForChild("ServerModules")
local Infrastructure = ServerModules:WaitForChild("Infrastructure")
local ServicesFolder = ServerModules:WaitForChild("Services")

local DataManager = require(ServerModules:WaitForChild("DataManager"))
local EquipmentStateService = require(ServerModules:WaitForChild("EquipmentStateService"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local RemoteUtil = require(Infrastructure:WaitForChild("RemoteUtil"))

local log = LogUtil.For("MainServer")
local SERVICE_ORDER = {
	"InventoryService",
	"ProductionService",
	"BaseService",
	"SpawnService",
	"ClaimService",
	"MythlingPreviewService",
}

local map = workspace:WaitForChild("Map")
local visuals = workspace:WaitForChild("Visuals")
local runtime = workspace:WaitForChild("Runtime")
local assets = ReplicatedStorage:WaitForChild("Assets")
local sharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local metadata = sharedModules:WaitForChild("Metadata")
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
		MythlingPreviews = assets:WaitForChild("MythlingPreviews"),
	},
	Metadata = {
		Mythlings = require(metadata:WaitForChild("Mythlings")),
		Materials = require(metadata:WaitForChild("Materials")),
		Consumables = require(metadata:WaitForChild("Consumables")),
		Spawns = require(metadata:WaitForChild("Spawns")),
		Equipment = require(metadata:WaitForChild("Equipment")),
	},
	Remotes = RemoteUtil.Resolve(ReplicatedStorage),
	Services = {},
}

local services = {
	DataManager = DataManager,
	EquipmentStateService = EquipmentStateService,
}
for _, name in ipairs(SERVICE_ORDER) do
	services[name] = require(ServicesFolder:WaitForChild(name))
end
context.Services = services

local ordered = {
	{ name = "DataManager", service = DataManager },
}
for _, name in ipairs(SERVICE_ORDER) do
	table.insert(ordered, { name = name, service = services[name] })
end
table.insert(ordered, { name = "EquipmentStateService", service = EquipmentStateService })

for _, entry in ipairs(ordered) do
	entry.service.Init(context)
end
for _, entry in ipairs(ordered) do
	entry.service.Start()
end

local function guardHumanoid(humanoid: Humanoid)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
end

local function onCharacterAdded(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		guardHumanoid(humanoid)
		return
	end
	local connection: RBXScriptConnection?
	connection = character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			guardHumanoid(child)
			if connection then
				connection:Disconnect()
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		task.defer(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	DataManager.Load(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(DataManager.Release)
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
