--!strict
-- ServerScriptService/Services/AdminCommandService/Blockstorm
-- Owns the temporary, non-colliding visual effect for the admin Blockstorm command.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Trove = require(ReplicatedStorage.Packages.Trove)

local Blockstorm = {}
Blockstorm.__index = Blockstorm

type State = {
	arena: BasePart,
	effectsFolder: Folder,
	lifetime: Trove.Trove,
	isActive: boolean,
	isDestroyed: boolean,
	eventGeneration: number,
}
export type Blockstorm = typeof(setmetatable({} :: State, Blockstorm))

-- Preserve the existing eight-second visual prototype's tuning.
local BLOCKSTORM = {
	id = "blockstorm",
	displayName = "Blockstorm",
	durationSeconds = 8,
	dropsPerSecond = 12,
	fallSeconds = 2.2,
	spawnHeight = 80,
	landingOffset = 4,
}

local function getOrCreateEffectsFolder(runtime: Instance, lifetime: Trove.Trove): Folder
	local existing = runtime:FindFirstChild("EventEffects")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "EventEffects"
	folder.Parent = runtime
	lifetime:Add(folder)
	return folder
end

local function spawnBlock(self: Blockstorm, random: Random)
	local lifetime = self.lifetime:Extend()
	local arena = self.arena
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
	block.Parent = self.effectsFolder
	lifetime:Add(block)

	local tween =
		TweenService:Create(block, TweenInfo.new(BLOCKSTORM.fallSeconds, Enum.EasingStyle.Linear), {
			Position = endPosition,
		})
	lifetime:Add(tween)

	tween:Play()
	lifetime:Add(task.delay(BLOCKSTORM.fallSeconds + 0.25, function()
		lifetime:Pop(coroutine.running())
		self.lifetime:Remove(lifetime)
	end))
end

function Blockstorm.new(arena: BasePart, runtime: Instance): Blockstorm
	local lifetime = Trove.new()
	local state: State = {
		arena = arena,
		effectsFolder = getOrCreateEffectsFolder(runtime, lifetime),
		lifetime = lifetime,
		isActive = false,
		isDestroyed = false,
		eventGeneration = 0,
	}
	return setmetatable(state, Blockstorm)
end

function Blockstorm.StartEvent(self: Blockstorm, eventId: string): (boolean, string)
	if self.isDestroyed then
		return false, "Events are not ready yet."
	end
	if eventId ~= BLOCKSTORM.id then
		return false, "Use /admin event blockstorm."
	end
	if self.isActive then
		return false, "An event is already active."
	end

	self.isActive = true
	self.eventGeneration += 1
	local generation = self.eventGeneration
	local random = Random.new()
	local endAt = os.clock() + BLOCKSTORM.durationSeconds

	self.lifetime:Add(task.defer(function()
		while self.isActive and self.eventGeneration == generation and os.clock() < endAt do
			spawnBlock(self, random)
			task.wait(1 / BLOCKSTORM.dropsPerSecond)
		end

		if self.eventGeneration == generation then
			self.isActive = false
		end
		self.lifetime:Pop(coroutine.running())
	end))

	return true, string.format("%s has begun.", BLOCKSTORM.displayName)
end

function Blockstorm.Destroy(self: Blockstorm)
	if self.isDestroyed then
		return
	end
	self.isDestroyed = true
	self.eventGeneration += 1
	self.isActive = false
	self.lifetime:Destroy()
end

return Blockstorm
