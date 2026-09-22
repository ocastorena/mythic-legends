--!strict
-- ServerScriptService/Services/MythlingSpawnService
local MythlingSpawnService = {}

-- Services
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("MythlingSpawnService")
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local ServerTypes = require(ServerScriptService.Domain.Types)
local Trove = require(game:GetService("ReplicatedStorage").Packages.Trove)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local ClaimEscort = require(script.ClaimEscort)
local lifecycle = ServiceLifecycle.new("MythlingSpawnService")
local encounterTroves: { [string]: Trove.Trove } = {}

--// Module State --------------------------------------------------------------

-- Context passed from Bootstrap (holds Config, Instances, Remotes, etc.)
local serviceContext: ServerTypes.Context

local MythlingsData: { [string]: Types.MythlingDef }

-- Service run flag and background threads

-- Active mythlings by id
-- entry = {
--   id: string,
--   model: Model,
--   zone: BasePart?,
--   typeId: string,
--   variantId: string,
--   rarity: string,
--   radius: number,
--   fillRate: number,
--   drainRate: number,
--   expireAt: number,
--   state: "SPAWNED" | "CONTEST" | "CLAIMED" | "ESCORT" | "DESPAWNED",
--   ownerUserId: number?,
-- }
local activeMythlings: { [string]: ServerTypes.SpawnEntry } = {}

-- Absolute unix time of the next permitted spawn. Kept distinct from the interval used to
-- pace the loop: these were previously the same variable, so the deadline check compared
-- an os.time() value against a 10-15 second interval and was always true.
local nextSpawnAt = 0

-- Rarity weights filtered to those that actually have mythlings defined (built in Init).
local spawnableWeights: { [string]: number } = {}

-- rarity -> {typeId, ...} (built in Init from MythlingsData + Spawn.rarityWeights)
local typesByRarity: { [string]: { string } } = {}

--// Small Utils ---------------------------------------------------------------

--- Returns current unix time.
local function timeNow(): number
	return os.time()
end

--- Returns a GUID without braces.
local function guid(): string
	return HttpService:GenerateGUID(false)
end

--- Picks a key from a weighted table at random.
--- Example: { common = 100, rare = 25, epic = 5 }
local function pickWeighted(weights: { [string]: number }): string?
	-- Calculate total weight
	local total = 0
	for _, weight in pairs(weights) do
		total += weight
	end
	if total <= 0 then
		return nil
	end

	-- Roll once in [0, total)
	local roll = math.random() * total
	for key, weight in pairs(weights) do
		roll -= weight
		if roll <= 0 then
			return key
		end
	end

	-- Shouldn't reach here, but acts as safety fallback
	return nil
end

--- Treats Arena as a flat circle: uses the larger of X/Z as diameter.
local function arenaInfo(arenaPart: BasePart): (CFrame, number)
	local size = arenaPart.Size
	local radius = math.max(size.X, size.Z) * 0.5
	return arenaPart.CFrame, radius
end

--- Returns the distance between two Vector3 points, ignoring Y (XZ-plane only).
local function distXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	local distanceSquared = dx * dx + dz * dz
	return math.sqrt(distanceSquared)
end

--- True if `point` would overlap any active zone, with padding.
local function overlapsExisting(point: Vector3, radius: number, padding: number): boolean
	for _, e in pairs(activeMythlings) do
		if e.state ~= "DESPAWNED" then
			local center = e.model:GetPivot().Position
			if distXZ(point, center) < (radius + e.radius + padding) then
				return true
			end
		end
	end
	return false
end

--- World-space random point uniformly within arena disc radius usableR.
local function randomPointInArena(arena: BasePart, usableR: number): Vector3?
	local center = arena.CFrame.Position
	local r2 = usableR * usableR
	for _ = 1, 64 do
		local dx = (math.random() * 2 - 1) * usableR
		local dz = (math.random() * 2 - 1) * usableR
		if dx * dx + dz * dz <= r2 then
			return Vector3.new(center.X + dx, center.Y, center.Z + dz)
		end
	end
	return nil
end

--// Zone ---------------------------------------------------------------
-- The ring is generated in code so runtime capture does not depend on a mutable Studio template.
local ZONE_SURFACE_LIFT = 0.05
local ZONE_RING_COLOR = Color3.fromRGB(103, 255, 158)

local function makeZone(radius: number, pivot: CFrame): BasePart
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Transparency = 1
	zone.Size = Vector3.new(radius * 2, 0.05, radius * 2)
	zone.CFrame = pivot + Vector3.new(0, ZONE_SURFACE_LIFT, 0)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "RingSurface"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.LightInfluence = 0
	surface.Parent = zone

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Parent = surface

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = ZONE_RING_COLOR
	stroke.Thickness = 5
	stroke.Transparency = 0.1
	stroke.Parent = ring

	CollectionService:AddTag(zone, "MythlingZone")

	return zone
end

--// Remote dispatch (centralized) ---------------------------------------------
local function sendAll(action: string, payload: { [string]: unknown })
	local evt = serviceContext.Remotes and serviceContext.Remotes.World.Spawned
	if evt then
		evt:FireAllClients(action, payload)
	end
end

local function sendTo(player: Player, action: string, payload: { [string]: unknown })
	local evt = serviceContext.Remotes and serviceContext.Remotes.World.Spawned
	if evt then
		evt:FireClient(player, action, payload)
	end
end

--// Mythling Creation / Destruction ------------------------------------------

--- Spawns a mythling model for typeId at world `position`, adds zone, and clones expire timer GUI.
--- Returns (model, zone) or (nil, nil) on failure.
local function createMythlingModel(
	typeId: string,
	position: Vector3,
	zoneRadius: number
): (Model?, BasePart?)
	local mythlings = serviceContext.Instances.MythlingAssets
	local template = mythlings
		and mythlings:FindFirstChild(MythlingsData[typeId].variants["regular"].model)
	if not (template and template:IsA("Model")) then
		log.warn(`Missing base model for typeId: {typeId}`)
		return nil, nil
	end

	local model = template:Clone()

	local angle = math.rad(math.random(0, 359)) -- random rotation in degrees
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, angle, 0))
	model.Parent = serviceContext.Instances.Mythlings

	-- Visual zone under the model
	local zone = makeZone(zoneRadius, model:GetPivot())
	zone.Parent = model

	-- Attach expire timer GUI if template exists
	local guiRoot = serviceContext.Instances.Templates
	local billboards = guiRoot and guiRoot:FindFirstChild("Billboards")
	local timerTemplate = billboards and billboards:FindFirstChild("MythlingExpireTimer")
	if timerTemplate and timerTemplate:IsA("BillboardGui") and model.PrimaryPart then
		local timer = timerTemplate:Clone()
		timer.Name = "MythlingExpireTimer"
		timer.Adornee = model.PrimaryPart
		timer.Parent = model
	end

	return model, zone
end

--- Destroys a mythling entry and its model safely.
local function destroyEntry(e: ServerTypes.SpawnEntry)
	local owner = encounterTroves[e.id]
	if owner then
		encounterTroves[e.id] = nil
		lifecycle.trove:Remove(owner)
	end
	if not e then
		return
	end
	e.state = "DESPAWNED"
	if e.model and e.model.Parent then
		e.model:Destroy()
	end
end

--- Applies a visual variant by swapping SurfaceAppearance maps if present.
local function applyVariant(model: Model, typeId: string, variantId: string)
	local vtab = serviceContext.Configurations.Mythlings[typeId].variants
	local def = vtab and vtab[variantId]
	if not def then
		return
	end

	local variantsFolder = model:FindFirstChild("Variants")
	local surface = variantsFolder and variantsFolder:FindFirstChild("regular")
	if not surface then
		return
	end
	local surf = surface:Clone()
	surf.Parent = model:FindFirstChildWhichIsA("MeshPart")
end

--// Spawn & Expire Pumps ------------------------------------------------------

--- Attempts to spawn exactly ONE mythling (random rarity/type) if a valid spot is found.
--- Returns true on success, false otherwise. (No side effects beyond one spawn.)
-- Helper: roll rarity → pick typeId → fetch per-type stats + expire seconds
type SpawnDefinition = {
	rarity: string,
	typeId: string,
	zoneRadius: number,
	fillRate: number,
	drainRate: number,
	displayName: string,
	expireSec: number,
}
local function chooseSpawnDef(
	cfg: typeof(serviceContext.Configurations.MythlingSpawns)
): SpawnDefinition?
	-- 1) roll rarity (only those with mythlings behind them; see Init)
	local rarity = pickWeighted(spawnableWeights)
	if not rarity then
		return nil
	end

	-- 2) pick a typeId within that rarity
	local list = typesByRarity[rarity]
	if not (list and #list > 0) then
		log.warn(`No typeIds for rarity: {rarity}`)
		return nil
	end
	local typeId = list[math.random(1, #list)]

	-- 3) read stats for that type
	local stats = serviceContext.Configurations.Mythlings[typeId]
	if not stats then
		return nil
	end

	-- 4) compute expire seconds for this rarity
	local expireSec = (cfg.expireSeconds and cfg.expireSeconds[rarity]) or cfg.defaultExpireSeconds

	return {
		rarity = rarity,
		typeId = typeId,
		zoneRadius = stats.zoneRadius,
		fillRate = stats.fillRate,
		drainRate = stats.drainRate,
		displayName = stats.displayName,
		expireSec = expireSec,
	}
end

-- Helper: find a valid non-overlapping world position inside the arena disc
local function findSpawnPosition(zoneRadius: number, padding: number, tries: number): Vector3?
	local arena = serviceContext.Instances.Arena
	local _, arenaR = arenaInfo(arena)
	local usableR = math.max(0, arenaR - zoneRadius - padding)

	-- randomPointInArena returns points at the arena's centre height, so lift to its top
	-- face. This is the arena's thickness (Size.Y) -- not Size.X, which is its width.
	local surfaceLift = arena.Size.Y / 2

	for _ = 1, tries do
		local p = randomPointInArena(arena, usableR)
		if p and not overlapsExisting(p, zoneRadius, padding) then
			return p + Vector3.new(0, surfaceLift, 0)
		end
	end
	return nil
end

-- Helper: register new mythling entry and set model attributes
local function registerMythling(
	model: Model,
	zone: BasePart,
	def: SpawnDefinition,
	expireAt: number
): (string, ServerTypes.SpawnEntry)
	local id = guid()
	local entry: ServerTypes.SpawnEntry = {
		id = id,
		displayName = def.displayName,
		model = model,
		zone = zone,
		typeId = def.typeId,
		rarity = def.rarity,
		radius = def.zoneRadius,
		fillRate = def.fillRate,
		drainRate = def.drainRate,
		expireAt = expireAt,
		state = "SPAWNED",
		ownerUserId = nil,
		variantId = "regular",
	}
	activeMythlings[id] = entry
	encounterTroves[id] = lifecycle.trove:Extend()

	-- attributes for client/UI
	model:SetAttribute("ExpireAt", expireAt)
	model:SetAttribute("Id", id)

	return id, entry
end

-- Helper: notify clients a spawn occurred
local function announceSpawn(id: string, def: SpawnDefinition, model: Model, expireAt: number)
	sendAll("Spawned", {
		mythlingId = id,
		typeId = def.typeId,
		rarity = def.rarity,
		variantId = "regular",
		expireAt = expireAt,
		zoneRadius = def.zoneRadius,
		position = model:GetPivot().Position,
	})
end

local function spawnOne(): boolean
	local cfg = serviceContext.Configurations.MythlingSpawns

	-- Step 1) choose rarity/type and stats
	local def = chooseSpawnDef(cfg)
	if not def then
		return false
	end

	-- Step 2) find a valid position
	local pos = findSpawnPosition(def.zoneRadius, cfg.zonePadding, cfg.maxPlacementTries)
	if not pos then
		return false
	end

	-- Step 3) create model + zone
	local model, zone = createMythlingModel(def.typeId, pos, def.zoneRadius)
	if not (model and zone) then
		return false
	end

	-- Step 4) apply variant (regular for now)
	applyVariant(model, def.typeId, "regular")

	-- Step 5) register + attributes
	local expireAt = timeNow() + def.expireSec
	local id = select(1, registerMythling(model, zone, def, expireAt))

	-- Step 6) announce to clients
	announceSpawn(id, def, model, expireAt)

	return true
end

--- Scans and despawns expired mythlings (no winner).
local function despawnExpired(t: number)
	for id, e in pairs(activeMythlings) do
		if e.state ~= "DESPAWNED" and (e.state == "SPAWNED" or e.state == "CONTEST") then
			if t >= e.expireAt then
				-- send event to clients for expired mythlings
				sendAll("Expired", { mythling = id })
				destroyEntry(e)
				activeMythlings[id] = nil
			end
		end
	end
end

-- Helpers for OnClaimed -------------------------------------------------------

--- Mark entry as claimed and set basic attributes/owner.
local function markClaimed(e: ServerTypes.SpawnEntry, winner: Player)
	e.state = "CLAIMED"
	e.model:SetAttribute("State", "CLAIMED")
	e.ownerUserId = winner.UserId
end

--- Remove the capture zone if present.
local function removeZoneIfAny(e: ServerTypes.SpawnEntry)
	if e.zone and e.zone.Parent then
		local timer = e.model and e.model:FindFirstChild("MythlingExpireTimer")
		if timer and timer:IsA("BillboardGui") then
			timer:Destroy()
		end
		e.zone:Destroy()
		e.zone = nil
	end
end

--- Find the winner's base anchor (by UserId) or return nil.
local function findBaseAnchor(winner: Player): BasePart?
	local bases = serviceContext.Instances.Bases
	if not bases then
		return nil
	end

	local baseModel = bases:FindFirstChild(tostring(winner.UserId))
	if not (baseModel and baseModel:IsA("Model")) then
		return nil
	end

	-- Preferred: a part named "Front"
	local front = baseModel:FindFirstChild("Front")
	if front and front:IsA("BasePart") then
		return front
	end
	return nil
end

--// Public API ----------------------------------------------------------------

--- Builds rarity->typeId lookup from Config and seeds RNG.
function MythlingSpawnService.Init(context: ServerTypes.Context)
	serviceContext = context
	MythlingsData = context.Configurations.Mythlings

	math.randomseed(tick() % 1 * 1e7)

	local weights = serviceContext.Configurations.MythlingSpawns.rarityWeights or {}

	for typeId, def in pairs(serviceContext.Configurations.Mythlings) do
		local rarity = def.rarity
		if rarity and weights[rarity] ~= nil then
			typesByRarity[rarity] = typesByRarity[rarity] or {}
			table.insert(typesByRarity[rarity], typeId)
		elseif rarity == nil then
			log.warn(`Mythling '{typeId}' is missing a rarity`)
		else
			log.warn(
				`Rarity '{rarity}' on '{typeId}' has no weight in MythlingSpawns.rarityWeights`
			)
		end
	end

	-- Filter configured rarities without a matching form so they cannot waste a spawn attempt.
	table.clear(spawnableWeights)
	for rarity, weight in pairs(weights) do
		if typesByRarity[rarity] and #typesByRarity[rarity] > 0 then
			spawnableWeights[rarity] = weight
		end
	end

	if next(spawnableWeights) == nil then
		log.error("No spawnable rarities; nothing will spawn")
	end
end

--- Starts the spawn/expire pumps. Spawns at most one mythling per tick (no prefill).
function MythlingSpawnService.Start()
	if not lifecycle:Start() then
		return
	end

	local cfg = serviceContext.Configurations.MythlingSpawns

	local function rollInterval(): number
		return math.random(cfg.spawnIntervalMin, cfg.spawnIntervalMax)
	end

	nextSpawnAt = timeNow() + rollInterval()

	-- Spawn pump. Polls on a short fixed tick and gates on the deadline, so the interval
	-- only advances when a spawn actually happens.
	lifecycle.trove:Add(task.defer(function()
		while lifecycle:IsRunning() do
			task.wait(0.5)

			if timeNow() >= nextSpawnAt then
				-- Count current live
				local live = 0
				for _, e in pairs(activeMythlings) do
					if e.state ~= "DESPAWNED" then
						live += 1
					end
				end

				if live < cfg.targetActive and spawnOne() then
					nextSpawnAt = timeNow() + rollInterval()
				end
			end
		end
	end))

	-- Expire pump: check every 0.5s
	lifecycle.trove:Add(task.defer(function()
		while lifecycle:IsRunning() do
			task.wait(0.5)
			despawnExpired(timeNow())
		end
	end))
end

--- Stops pumps and clears all active mythlings.
function MythlingSpawnService.Stop()
	if not lifecycle:Stop() then
		return
	end
	for _, e in pairs(activeMythlings) do
		destroyEntry(e)
	end
	table.clear(activeMythlings)
end

--- Called after a mythling is claimed and saved (winner decided).
function MythlingSpawnService.OnClaimed(mythlingId: string, winner: Player)
	local e = activeMythlings[mythlingId]
	if not e or e.state == "DESPAWNED" then
		return
	end

	-- 1) mark state/owner, remove zone
	markClaimed(e, winner)
	removeZoneIfAny(e)
	-- 2) notify all clients about the claim
	sendAll("Claimed", {
		mythlingId = mythlingId,
		winnerUserId = winner.UserId,
		displayName = e.displayName,
	})

	-- 3) escort to base if possible, otherwise cleanup shortly
	local baseAnchor = findBaseAnchor(winner)
	if baseAnchor and e.model.PrimaryPart then
		e.state = "ESCORT"
		e.model:SetAttribute("State", "ESCORT")
		sendTo(winner, "EscortStart", { mythlingId = mythlingId, baseCFrame = baseAnchor.CFrame })
		ClaimEscort.Start(e, baseAnchor, encounterTroves[mythlingId], function()
			destroyEntry(e)
		end)
	else
		local owner = encounterTroves[mythlingId]
		owner:Add(task.delay(1, function()
			owner:Pop(coroutine.running())
			destroyEntry(e)
			activeMythlings[mythlingId] = nil
		end))
	end
end

--- Returns the Active table (read-only by convention).
function MythlingSpawnService.GetActiveMythlings()
	return activeMythlings
end

return MythlingSpawnService
