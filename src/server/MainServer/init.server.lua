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
local DEFAULT_PRIORITY = 100

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
	Remotes = RemoteUtil.Ensure(ReplicatedStorage),
	Services = {},
}

local services = {
	DataManager = DataManager,
	EquipmentStateService = EquipmentStateService,
}
for _, child in ipairs(ServicesFolder:GetChildren()) do
	if child:IsA("ModuleScript") then
		services[child.Name] = require(child)
	end
end
context.Services = services

local ordered = {}
for name, service in pairs(services) do
	table.insert(ordered, {
		name = name,
		service = service,
		priority = service.Priority or DEFAULT_PRIORITY,
	})
end
table.sort(ordered, function(left, right)
	if left.priority ~= right.priority then
		return left.priority < right.priority
	end
	return left.name < right.name
end)

for _, entry in ipairs(ordered) do
	if type(entry.service.Init) == "function" then
		entry.service.Init(context)
	end
end
for _, entry in ipairs(ordered) do
	if type(entry.service.Start) == "function" then
		entry.service.Start()
	end
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
		if type(service.Stop) == "function" then
			local ok, err = pcall(service.Stop)
			if not ok then
				log.error(`Service stop failed for {ordered[index].name}`, err)
			end
		end
	end
end)

log.info(`Started {#ordered} services`)
