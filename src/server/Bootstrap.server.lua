-- ServerScriptService/Bootstrap
-- Builds the shared Context, then initialises and starts every service in a declared
-- order. This is the only script that knows about all services at once.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = ReplicatedStorage:WaitForChild("Util")
local RemoteUtil = require(Util:WaitForChild("RemoteUtil"))
local PlayerUtil = require(Util:WaitForChild("PlayerUtil"))
local LogUtil = require(Util:WaitForChild("LogUtil"))

local log = LogUtil.For("Bootstrap")
local ServicesFolder = script.Parent:WaitForChild("Services")

-- Services without an explicit Priority fall here. Lower numbers initialise first, so
-- anything others depend on during Init/Start must declare a lower value. Ordering used
-- to be alphabetical, which happened to work only because no service called another
-- during Init -- an invariant nothing enforced.
local DEFAULT_PRIORITY = 100

-- Context table for all services + configs & remotes + constants
local Context = {
	Instances = {
		Arena = workspace:WaitForChild("Arena"),
		Mythlings = workspace:WaitForChild("Mythlings"),
		Bases = workspace:WaitForChild("Bases"),
		BaseIslands = workspace:WaitForChild("BaseIslands"),
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

-- Create any remotes the source declares but the place is missing, then collect them all.
Context.Remotes = RemoteUtil.Ensure(ReplicatedStorage)

-- Load services
local services = {}
for _, child in ipairs(ServicesFolder:GetChildren()) do
	if child:IsA("ModuleScript") then
		services[child.Name] = require(child)
	end
end
Context.Services = services

-- Order by declared Priority, falling back to name so the sequence stays deterministic.
local ordered = {}
for name, mod in pairs(services) do
	table.insert(ordered, { name = name, mod = mod, priority = mod.Priority or DEFAULT_PRIORITY })
end
table.sort(ordered, function(a, b)
	if a.priority ~= b.priority then
		return a.priority < b.priority
	end
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

log.info("Services started:", #ordered)

--// Character rules -----------------------------------------------------------

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

--// Per-player profile --------------------------------------------------------

local DataService = services.DataService

PlayerUtil.OnPlayer(function(player)
	if player.Character then
		onCharacter(player.Character)
	end
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
