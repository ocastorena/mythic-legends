--!strict
-- ServerScriptService/Services/AdminCommandService
-- Public, server-validated chat commands. Only the invoking character can teleport.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local RateLimiter = require(Infrastructure:WaitForChild("RateLimiter"))
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local CommandParser = require(script.CommandParser)
local Teleportation = require(script.Teleportation)
local ServerTypes = require(ServerScriptService.Domain.Types)

local log = LogUtil.For("AdminCommandService")
local AdminCommandService = {}
local context: ServerTypes.Context
local limiter: RateLimiter.RateLimiter
local running = false
local connections: { RBXScriptConnection } = {}
local pending: { [Player]: {} } = {}

local function reply(player: Player, message: string)
	if running and player.Parent == Players then
		context.Remotes.Admin.Feedback:FireClient(player, message)
	end
end

local function resolveMarker(player: Player, destination: string): (BasePart?, string)
	local baseSpawn = if destination == "base"
		then context.Services.BaseService.GetSpawnPoint(player)
		else nil
	return Teleportation.ResolveMarker(
		destination,
		context.Instances.World,
		baseSpawn,
		context.Configurations.AdminCommands
	)
end

local function teleport(player: Player, destination: string, request: {}): string
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then
		return "Your character is not ready to teleport."
	end
	local marker, destinationName = resolveMarker(player, destination)
	if not marker then
		return destinationName
	end
	if not marker:IsDescendantOf(workspace) then
		return "The destination is not ready yet."
	end
	local config = context.Configurations.AdminCommands
	local arrival, arrivalError = Teleportation.GetArrival(character, marker, workspace, config)
	if not arrival then
		return arrivalError or "The landing point is not ready."
	end

	local markerCFrame = marker.CFrame
	local markerSize = marker.Size
	if workspace.StreamingEnabled then
		local streamed = pcall(function()
			player:RequestStreamAroundAsync(marker.Position, config.streamTimeoutSeconds)
		end)
		if not streamed then
			return "The destination could not load. Please try again."
		end
	end

	-- Streaming yields: reset, disconnect, service shutdown, or authoring edits cancel this move.
	if
		not running
		or pending[player] ~= request
		or player.Parent ~= Players
		or player.Character ~= character
		or not character:IsDescendantOf(workspace)
	then
		return "Teleport cancelled because your character changed."
	end
	local currentMarker = resolveMarker(player, destination)
	if
		currentMarker ~= marker
		or not marker:IsDescendantOf(workspace)
		or marker.CFrame ~= markerCFrame
		or marker.Size ~= markerSize
	then
		return "The destination changed. Please try again."
	end
	arrival, arrivalError = Teleportation.GetArrival(character, marker, workspace, config)
	if not arrival then
		return arrivalError or "The landing point is not ready."
	end
	Teleportation.MoveCharacter(character, arrival)
	return `Teleported to {destinationName}.`
end

local function handleCommand(originTextSource: TextSource, text: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if not running or not player or not limiter:Allow(player) then
		return
	end
	local command, parseError = CommandParser.Parse(text)
	if not command then
		reply(player, parseError or "Invalid admin command.")
		return
	end
	if command.name == "event" then
		local _, message = context.Services.DivineInterventionService.StartEvent(command.argument)
		reply(player, message)
		return
	end
	if pending[player] then
		reply(player, "A teleport is already in progress.")
		return
	end
	local request = {}
	pending[player] = request
	local ok, message = pcall(teleport, player, command.argument, request)
	if pending[player] ~= request then
		return
	end
	pending[player] = nil
	if not ok then
		log.warn(`Teleport failed for userId={player.UserId}`, message)
		message = "Teleport failed. Please try again."
	end
	reply(player, message)
end

function AdminCommandService.Init(serviceContext: ServerTypes.Context)
	context = serviceContext
	local config = context.Configurations.AdminCommands
	limiter = RateLimiter.new(config.commandBurst, config.commandRefillPerSecond)
end

function AdminCommandService.Start()
	if running then
		return
	end
	local command = TextChatService:FindFirstChild("AdminCommand")
	assert(
		command and command:IsA("TextChatCommand"),
		"[AdminCommandService] AdminCommand is missing"
	)
	running = true
	table.insert(connections, command.Triggered:Connect(handleCommand))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			pending[player] = nil
			limiter:Forget(player)
		end)
	)
end

function AdminCommandService.Stop()
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(pending)
	limiter:Clear()
end

return AdminCommandService
