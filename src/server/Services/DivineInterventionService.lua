-- ServerScriptService/Services/DivineInterventionService
--
-- Owns the server-authoritative lifecycle for Divine Intervention events. The first event
-- is a safe visual test: Blockstorm makes non-colliding blocks fall through the Arena
-- without changing combat, rewards, or player state.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local DivineInterventionService = {
	Priority = 140,
}

local context
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
	return folder
end

local function spawnBlock(random: Random)
	local halfX = arena.Size.X * 0.45
	local halfZ = arena.Size.Z * 0.45
	local x = random:NextNumber(-halfX, halfX)
	local z = random:NextNumber(-halfZ, halfZ)
	local size = random:NextInteger(2, 5)
	local startPosition = arena.CFrame:PointToWorldSpace(Vector3.new(x, BLOCKSTORM.spawnHeight, z))
	local endPosition = arena.CFrame:PointToWorldSpace(Vector3.new(x, arena.Size.Y / 2 + BLOCKSTORM.landingOffset, z))

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

	local tween = TweenService:Create(block, TweenInfo.new(BLOCKSTORM.fallSeconds, Enum.EasingStyle.Linear), {
		Position = endPosition,
	})
	tween:Play()
	Debris:AddItem(block, BLOCKSTORM.fallSeconds + 0.25)
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

	task.spawn(function()
		while activeEventId == BLOCKSTORM.id and eventGeneration == generation and os.clock() < endAt do
			spawnBlock(random)
			task.wait(1 / BLOCKSTORM.dropsPerSecond)
		end

		if eventGeneration == generation then
			activeEventId = nil
		end
	end)

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
		local started, message = startBlockstorm()
		print("[DivineIntervention]", message)
		if not started then
			warn("[DivineIntervention]", message)
		end
		return
	end

	print("[DivineIntervention] Usage: /admin blockstorm")
end

function DivineInterventionService.Init(serviceContext)
	context = serviceContext
	arena = context.Instances.Arena
	effectsFolder = getOrCreateEffectsFolder(context.Instances.Runtime)
end

function DivineInterventionService.Start()
	local command = TextChatService:FindFirstChild("AdminCommand")
	if not command or not command:IsA("TextChatCommand") then
		warn("[DivineIntervention] AdminCommand is missing from TextChatService.")
		return
	end

	command.Triggered:Connect(handleCommand)
end

return DivineInterventionService
