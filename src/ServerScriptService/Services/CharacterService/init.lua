-- ServerScriptService/Services/CharacterService

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerUtil = require(ServerScriptService:WaitForChild("Infrastructure"):WaitForChild("PlayerUtil"))

local CharacterService = {}

local connections: { RBXScriptConnection } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local initialized = false
local running = false

local function disableClimbing(humanoid: Humanoid)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
end

local function onCharacterAdded(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		disableClimbing(humanoid)
		return
	end

	local connection: RBXScriptConnection?
	connection = character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			disableClimbing(child)
			if connection then
				connection:Disconnect()
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	local existing = characterConnections[player]
	if existing then
		existing:Disconnect()
	end
	characterConnections[player] = player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.defer(onCharacterAdded, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local connection = characterConnections[player]
	if connection then
		connection:Disconnect()
		characterConnections[player] = nil
	end
end

function CharacterService.Init(_context: unknown)
	initialized = true
end

function CharacterService.Start()
	assert(initialized, "[CharacterService] Init must run before Start")
	if running then
		return
	end
	running = true
	table.insert(connections, PlayerUtil.OnPlayer(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function CharacterService.Stop()
	if not running then
		return
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player, connection in characterConnections do
		connection:Disconnect()
		characterConnections[player] = nil
	end
end

return CharacterService
