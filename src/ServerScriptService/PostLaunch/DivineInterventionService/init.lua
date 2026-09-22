--!strict
-- ServerScriptService/PostLaunch/DivineInterventionService
--
-- Owns the server-authoritative lifecycle for Divine Intervention events. The first event
-- is a safe visual test: Blockstorm makes non-colliding blocks fall through the Arena
-- without changing combat, rewards, or player state.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("DivineInterventionService")

local ServerTypes = require(ServerScriptService.Domain.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("DivineInterventionService")

local DivineInterventionService = {}

local serviceContext: ServerTypes.Context
local arena: BasePart
local effectsFolder: Folder
local activeEventId: string? = nil
local eventGeneration = 0

-- A short, low-density presentation test: at most 96 temporary, non-colliding parts.
local BLOCKSTORM = {
	id = "blockstorm",
	displayName = "Blockstorm",
	durationSeconds = 8,
	dropsPerSecond = 12,
	fallSeconds = 2.2,
	spawnHeight = 80,
	landingOffset = 4,
}

local function getOrCreateEffectsFolder(runtime: Instance): Folder
	local existing = runtime:FindFirstChild("EventEffects")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "EventEffects"
	folder.Parent = runtime
	lifecycle.trove:Add(folder)
	return folder
end

local function spawnBlock(random: Random)
	local lifetime = lifecycle.trove:Extend()
	local halfX = arena.Size.X * 0.45
	local halfZ = arena.Size.Z * 0.45
	local x = random:NextNumber(-halfX, halfX)
	local z = random:NextNumber(-halfZ, halfZ)
	local size = random:NextInteger(2, 5)
	local startPosition = arena.CFrame:PointToWorldSpace(Vector3.new(x, BLOCKSTORM.spawnHeight, z))
	local endPosition = arena.CFrame:PointToWorldSpace(
		Vector3.new(x, arena.Size.Y / 2 + BLOCKSTORM.landingOffset, z)
	)

	local block = Instance.new("Part")
	block.Name = "BlockstormDrop"
	block.Anchored = true
	block.CanCollide = false
	block.CanTouch = false
	block.CanQuery = false
	block.CastShadow = false
	block.Material = Enum.Material.Neon
	block.Color = Color3.fromRGB(100, 181, 246)
	block.Transparency = 0.15
	block.Size = Vector3.new(size, size, size)
	block.Position = startPosition
	block.Parent = effectsFolder
	lifetime:Add(block)

	local tween =
		TweenService:Create(block, TweenInfo.new(BLOCKSTORM.fallSeconds, Enum.EasingStyle.Linear), {
			Position = endPosition,
		})
	lifetime:Add(tween)
	tween:Play()
	lifetime:Add(task.delay(BLOCKSTORM.fallSeconds + 0.25, function()
		lifetime:Pop(coroutine.running())
		lifecycle.trove:Remove(lifetime)
	end))
end

local function startBlockstorm()
	if activeEventId then
		return false, "An event is already active."
	end

	activeEventId = BLOCKSTORM.id
	eventGeneration += 1
	local generation = eventGeneration
	local random = Random.new()
	local endAt = os.clock() + BLOCKSTORM.durationSeconds

	lifecycle.trove:Add(task.defer(function()
		while
			activeEventId == BLOCKSTORM.id
			and eventGeneration == generation
			and os.clock() < endAt
		do
			spawnBlock(random)
			task.wait(1 / BLOCKSTORM.dropsPerSecond)
		end

		if eventGeneration == generation then
			activeEventId = nil
		end
		lifecycle.trove:Pop(coroutine.running())
	end))

	return true, string.format("%s has begun.", BLOCKSTORM.displayName)
end

local function getRequestedEvent(unfilteredText: string): string?
	local command, eventId = string.match(string.lower(unfilteredText), "^%s*(/%S+)%s+(%S+)")
	if not command then
		return nil
	end
	return eventId
end

local function handleCommand(originTextSource: TextSource, unfilteredText: string)
	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if not player then
		return
	end

	local requestedEvent = getRequestedEvent(unfilteredText)
	if requestedEvent == BLOCKSTORM.id then
		startBlockstorm()
	end
end

function DivineInterventionService.Init(context: ServerTypes.Context)
	serviceContext = context
	arena = serviceContext.Instances.Arena
end

function DivineInterventionService.Start()
	if not lifecycle:Start() then
		return
	end
	effectsFolder = getOrCreateEffectsFolder(serviceContext.Instances.Runtime)
	local command = TextChatService:FindFirstChild("AdminCommand")
	if not command or not command:IsA("TextChatCommand") then
		log.warn("AdminCommand is missing from TextChatService")
		return
	end

	lifecycle.trove:Connect(command.Triggered, handleCommand)
end

function DivineInterventionService.Stop()
	if not lifecycle:Stop() then
		return
	end
	eventGeneration += 1
	activeEventId = nil
end

return DivineInterventionService
