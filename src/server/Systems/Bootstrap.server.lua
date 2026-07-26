-- ServerScriptService/Systems/Bootstrap
-- Services
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local ServicesFolder = script.Parent.Parent:WaitForChild("Services")

-- Context table for all services + configs & remotes + constants
local Context = {
	Instances = {
		Arena = workspace:WaitForChild("Arena"),
		ArenaPlate = workspace:WaitForChild("ArenaPlate"),
		Mythlings = workspace:WaitForChild("Mythlings"),
		Bases = workspace:WaitForChild("Bases"),
		MythlingAssets = ServerStorage:WaitForChild("MythlingAssets"),
		BaseAssets = ServerStorage:WaitForChild("BaseAssets"),
		Templates = ReplicatedStorage:WaitForChild("Templates"),
	},
	Metadata = {
		Mythlings = require(ReplicatedStorage.Metadata:WaitForChild("Mythlings")),
		Resources = require(ReplicatedStorage.Metadata:WaitForChild("Resources")),
		Spawns = require(ReplicatedStorage.Metadata:WaitForChild("Spawns")),
		Weapons = require(ReplicatedStorage.Metadata:WaitForChild("Weapons")),
	},
	Remotes = {},
	Services = {},
}

-- Load remotes
local remotes = {}
for _, child in ipairs(RemotesFolder:GetChildren()) do
	if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
		local remote = child
		remotes[child.Name] = remote
	end
end
Context.Remotes = remotes

-- Load services
local services = {}
for _, child in ipairs(ServicesFolder:GetChildren()) do
	if child:IsA("ModuleScript") then
		local mod = require(child)
		services[child.Name] = mod
	end
end
Context.Services = services

-- === Disable climbing globally (server-side) ===
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService.Services.DataService)

local function guardHumanoid(hum: Humanoid)
	-- Do not allow entering the Climbing state at all
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false) -- server ok
end

local function onCharacter(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		guardHumanoid(hum)
	else
		-- For custom rigs that add Humanoid slightly later
		char.ChildAdded:Connect(function(ch)
			if ch:IsA("Humanoid") then
				guardHumanoid(ch)
			end
		end)
	end
end

-- Hook existing
for _, plr in ipairs(Players:GetPlayers()) do
	if plr.Character then
		onCharacter(plr.Character)
	end
	plr.CharacterAdded:Connect(onCharacter)
end

-- === end disable climbing ===

-- Initialize & start services
local ordered = {}
for name, mod in pairs(services) do
	table.insert(ordered, { name = name, mod = mod })
end
table.sort(ordered, function(a, b)
	return a.name < b.name
end)

for _, s in ipairs(ordered) do
	if type(s.mod.Init) == "function" then
		s.mod.Init(Context)
	end
end

for _, s in ipairs(ordered) do
	if type(s.mod.Start) == "function" then
		s.mod.Start()
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacter)
	local profile = DataService.GetSection(player, "profile")
	if not profile.userId then
		profile.userId = player.UserId
	end
	if not profile.createdAt then
		profile.createdAt = os.time()
	end

	profile.lastLoginAt = os.time()
end)

-- Cleanup on shutdown
game:BindToClose(function()
	for i = #ordered, 1, -1 do
		local s = ordered[i]
		if type(s.mod.Stop) == "function" then
			pcall(s.mod.Stop)
		end
	end
end)
