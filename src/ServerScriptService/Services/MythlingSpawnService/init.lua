-- ServerScriptService/Services/MythlingSpawnService
local MythlingSpawnService = {}

-- Services
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("MythlingSpawnService")

--// Module State --------------------------------------------------------------

-- Context passed from Bootstrap (holds Config, Instances, Remotes, etc.)
local Context = nil

local MythlingsData = nil

-- Service run flag and background threads
local running = false
local threads = {
	spawn = nil,
	expire = nil,
}

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
local Active: { [string]: any } = {}

-- Absolute unix time of the next permitted spawn. Kept distinct from the interval used to
-- pace the loop: these were previously the same variable, so the deadline check compared
-- an os.time() value against a 10-15 second interval and was always true.
local nextSpawnAt = 0

-- Rarity weights filtered to those that actually have mythlings defined (built in Init).
local SpawnableWeights: { [string]: number } = {}

-- rarity -> {typeId, ...} (built in Init from MythlingsData + Spawn.RarityWeights)
local TypesByRarity: { [string]: { string } } = {}

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
	for _, e in pairs(Active) do
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
local function sendAll(action: string, payload: any)
	local evt = Context.Remotes and Context.Remotes.World.Spawned
	if evt then
		evt:FireAllClients(action, payload)
	end
end

local function sendTo(player: Player, action: string, payload: any)
	local evt = Context.Remotes and Context.Remotes.World.Spawned
	if evt then
		evt:FireClient(player, action, payload)
	end
end

--// Mythling Creation / Destruction ------------------------------------------

--- Spawns a mythling model for typeId at world `position`, adds zone, and clones expire timer GUI.
--- Returns (model, zone) or (nil, nil) on failure.
local function createMythlingModel(typeId: string, position: Vector3, zoneRadius: number): (Model?, BasePart?)
	local mythlings = Context.Instances.MythlingAssets
	local template = mythlings and mythlings:FindFirstChild(MythlingsData[typeId].variants["regular"].model)
	if not (template and template:IsA("Model")) then
		log.warn(`Missing base model for typeId: {typeId}`)
		return nil, nil
	end

	local model = template:Clone()

	local angle = math.rad(math.random(0, 359)) -- random rotation in degrees
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, angle, 0))
	model.Parent = Context.Instances.Mythlings

	-- Visual zone under the model
	local zone = makeZone(zoneRadius, model:GetPivot())
	zone.Parent = model

	-- Attach expire timer GUI if template exists
	local guiRoot = Context.Instances.Templates
	local billboards = guiRoot and guiRoot:FindFirstChild("Billboards")
	local timerTemplate = billboards and billboards:FindFirstChild("MythlingExpireTimer")
	if timerTemplate and model.PrimaryPart then
		local timer = timerTemplate:Clone()
		timer.Name = "MythlingExpireTimer"
		timer.Adornee = model.PrimaryPart
		timer.Parent = model
	end

	return model, zone
end

--- Destroys a mythling entry and its model safely.
local function destroyEntry(e)
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
	local vtab = Context.Configurations.Mythlings[typeId].variants
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
local function chooseSpawnDef(cfg)
	-- 1) roll rarity (only those with mythlings behind them; see Init)
	local rarity = pickWeighted(SpawnableWeights)
	if not rarity then
		return nil
	end

	-- 2) pick a typeId within that rarity
	local list = TypesByRarity[rarity]
	if not (list and #list > 0) then
		log.warn(`No typeIds for rarity: {rarity}`)
		return nil
	end
	local typeId = list[math.random(1, #list)]

	-- 3) read stats for that type
	local stats = Context.Configurations.Mythlings[typeId]
	if not stats then
		return nil
	end

	-- 4) compute expire seconds for this rarity
	local expireSec = (cfg.ExpireSeconds and cfg.ExpireSeconds[rarity]) or cfg.DefaultExpireSeconds

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
local function findSpawnPosition(zoneRadius: number, padding: number, tries: number)
	local arena = Context.Instances.Arena
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
local function registerMythling(model: Model, zone: BasePart, def, expireAt: number)
	local id = guid()
	local entry = {
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
	Active[id] = entry

	-- attributes for client/UI
	model:SetAttribute("ExpireAt", expireAt)
	model:SetAttribute("Id", id)

	return id, entry
end

-- Helper: notify clients a spawn occurred
local function announceSpawn(id: string, def, model: Model, expireAt: number)
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
	local cfg = Context.Configurations.MythlingSpawns

	-- Step 1) choose rarity/type and stats
	local def = chooseSpawnDef(cfg)
	if not def then
		return false
	end

	-- Step 2) find a valid position
	local pos = findSpawnPosition(def.zoneRadius, cfg.ZonePadding, cfg.MaxPlacementTries)
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
	for id, e in pairs(Active) do
		if e.state ~= "DESPAWNED" and (e.state == "SPAWNED" or e.state == "CONTEST") then
			if t >= e.expireAt then
				-- send event to clients for expired mythlings
				sendAll("Expired", { mythling = id })
				if
					Context.Services
					and Context.Services.ClaimService
					and Context.Services.ClaimService.OnMythlingRemoved
				then
					Context.Services.ClaimService.OnMythlingRemoved(id)
				end
				if e.model and e.model.Parent then
					e.model:Destroy()
				end
				Active[id] = nil
			end
		end
	end
end

-- Helpers for OnClaimed -------------------------------------------------------

--- Mark entry as claimed and set basic attributes/owner.
local function markClaimed(e, winner: Player)
	e.state = "CLAIMED"
	e.model:SetAttribute("State", "CLAIMED")
	e.ownerUserId = winner.UserId
end

--- Remove the capture zone if present.
local function removeZoneIfAny(e)
	if e.zone and e.zone.Parent then
		local timer = e.model and e.model:FindFirstChild("MythlingExpireTimer")
		if timer then
			timer:Destroy()
		end
		e.zone:Destroy()
		e.zone = nil
	end
end

-- Tries to create or find an Animator on the model (Humanoid or AnimationController).
local function getAnimator(model: Model): Animator?
	if not model then
		return nil
	end

	-- Prefer an existing Humanoid
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildWhichIsA("Animator")
		if animator then
			return animator
		end
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		return newAnimator
	end

	-- Fallback to an AnimationController
	local controller = model:FindFirstChildWhichIsA("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "AnimationController"
		controller.Parent = model
	end
	local animator = controller:FindFirstChildWhichIsA("Animator")
	if animator then
		return animator
	end
	local newAnimator = Instance.new("Animator")
	newAnimator.Parent = controller
	return newAnimator
end

-- Plays a looping Walking animation if present; returns a cleanup callback.
local function playWalkingAnimation(model: Model): (() -> ())?
	local animationsFolder = model:FindFirstChild("Animations") or model:FindFirstChild("Animation")
	if not animationsFolder then
		return nil
	end

	local walking = animationsFolder:FindFirstChild("Walking")
	if not (walking and walking:IsA("Animation")) then
		return nil
	end

	local animator = getAnimator(model)
	if not animator then
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(walking)
	end)
	if not ok or not track then
		return nil
	end

	track.Looped = true
	track:Play()

	local destroyingConn
	destroyingConn = model.Destroying:Connect(function()
		if destroyingConn then
			destroyingConn:Disconnect()
		end
		if track then
			pcall(function()
				track:Stop()
			end)
		end
	end)

	return function()
		if destroyingConn then
			destroyingConn:Disconnect()
			destroyingConn = nil
		end
		if track then
			pcall(function()
				track:Stop()
			end)
		end
	end
end

--- Find the winner's base anchor (by UserId) or return nil.
local function findBaseAnchor(winner: Player): BasePart?
	local bases = Context.Instances.Bases
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

--- Tween the model to the player's base and cleanup afterward.
local function escortThenCleanup(e, winner: Player, mythlingId: string, baseAnchor: BasePart)
	e.state = "ESCORT"
	e.model:SetAttribute("State", "ESCORT")

	sendTo(winner, "EscortStart", {
		mythlingId = mythlingId,
		baseCFrame = baseAnchor.CFrame,
	})

	local root = e.model.PrimaryPart

	local path =
		PathfindingService:CreatePath({ AgentRadius = 4, AgentHeight = 6, AgentCanJump = false, WaypointSpacing = 4 })

	local success, errorMessage = pcall(function()
		local dest = Vector3.new(baseAnchor.Position.X, root.Position.Y, baseAnchor.Position.Z)
		path:ComputeAsync(root.Position, dest)
	end)

	if success then
		local stopWalk = playWalkingAnimation(e.model)
		for _, waypoint in pairs(path:GetWaypoints()) do
			-------------------
			-- local part = Instance.new("Part")
			-- part.Material = "Neon"
			-- part.Anchored = true
			-- part.CanCollide = false
			-- part.Shape = "Ball"
			-- part.Position = waypoint.Position
			-- part.Parent = game.Workspace
			-------------------
			local target = Vector3.new(waypoint.Position.X, root.Position.Y, waypoint.Position.Z)
			local lookAt = Vector3.new(target.X, root.Position.Y, target.Z)
			local faceCF = CFrame.lookAt(root.Position, lookAt)
			local moveCF = CFrame.new(target) * (faceCF - faceCF.Position) -- apply orientation at destination
			local dist = (target - root.Position).Magnitude
			local t = math.max(dist / 4, 0.05)
			local tween = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = moveCF })
			tween:Play()
			tween.Completed:Wait()
		end
		-- playWalkingAnimation returns nil when the model has no animator or no Walking
		-- clip, so this must be guarded -- calling it unconditionally aborted the escort
		-- and leaked the mythling model.
		if stopWalk then
			stopWalk()
		end
		destroyEntry(e)
	else
		log.warn(`Escort pathfinding failed: {errorMessage}`)
		-- Still clean up, otherwise a failed path leaves the mythling stranded forever.
		destroyEntry(e)
	end

	-- local tween = TweenService:Create(
	-- 	root,
	-- 	TweenInfo.new(10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 2),
	-- 	{ CFrame = CFrame.new(baseAnchor.Position + Vector3.new(0, 2, 0)) }
	-- )
	-- tween:Play()

	-- tween.Completed:Connect(function()
	-- 	if stopWalk then
	-- 		stopWalk()
	-- 	end
	-- end)

	-- task.delay(10.1, function()
	-- 	if stopWalk then
	-- 		stopWalk()
	-- 	end
	-- 	sendTo(winner, "EscortArrived", { mythlingId = mythlingId })
	-- 	destroyEntry(e)
	-- 	Active[mythlingId] = nil
	-- 	if Context.Services and Context.Services.ClaimService and Context.Services.ClaimService.OnMythlingRemoved then
	-- 		Context.Services.ClaimService.OnMythlingRemoved(mythlingId)
	-- 	end
	-- end)
end

--- Cleanup path when there's no base anchor available.
local function cleanupSoon(e, mythlingId: string)
	task.delay(1, function()
		destroyEntry(e)
		Active[mythlingId] = nil
	end)
end

--// Public API ----------------------------------------------------------------

--- Builds rarity->typeId lookup from Config and seeds RNG.
function MythlingSpawnService.Init(context)
	Context = context
	MythlingsData = context.Configurations.Mythlings

	math.randomseed(tick() % 1 * 1e7)

	local weights = Context.Configurations.MythlingSpawns.RarityWeights or {}

	for typeId, def in pairs(Context.Configurations.Mythlings) do
		local rarity = def.rarity
		if rarity and weights[rarity] ~= nil then
			TypesByRarity[rarity] = TypesByRarity[rarity] or {}
			table.insert(TypesByRarity[rarity], typeId)
		elseif rarity == nil then
			log.warn(`Mythling '{typeId}' is missing a rarity`)
		else
			log.warn(`Rarity '{rarity}' on '{typeId}' has no weight in MythlingSpawns.RarityWeights`)
		end
	end

	-- Only roll rarities that can actually produce a mythling. MythlingSpawns.RarityWeights lists
	-- Epic and Secret, but no mythling declares them, so those rolls used to pick a rarity
	-- and then fail with "No typeIds for rarity" -- silently wasting spawn attempts.
	table.clear(SpawnableWeights)
	for rarity, weight in pairs(weights) do
		if TypesByRarity[rarity] and #TypesByRarity[rarity] > 0 then
			SpawnableWeights[rarity] = weight
		end
	end

	if next(SpawnableWeights) == nil then
		log.error("No spawnable rarities; nothing will spawn")
	end
end

--- Starts the spawn/expire pumps. Spawns at most one mythling per tick (no prefill).
function MythlingSpawnService.Start()
	if running then
		return
	end
	running = true

	local cfg = Context.Configurations.MythlingSpawns

	local function rollInterval(): number
		return math.random(cfg.SpawnIntervalMin, cfg.SpawnIntervalMax)
	end

	nextSpawnAt = timeNow() + rollInterval()

	-- Spawn pump. Polls on a short fixed tick and gates on the deadline, so the interval
	-- only advances when a spawn actually happens.
	threads.spawn = task.spawn(function()
		while running do
			task.wait(0.5)

			if timeNow() >= nextSpawnAt then
				-- Count current live
				local live = 0
				for _, e in pairs(Active) do
					if e.state ~= "DESPAWNED" then
						live += 1
					end
				end

				if live < cfg.TargetActive and spawnOne() then
					nextSpawnAt = timeNow() + rollInterval()
				end
			end
		end
	end)

	-- Expire pump: check every 0.5s
	threads.expire = task.spawn(function()
		while running do
			task.wait(0.5)
			despawnExpired(timeNow())
		end
	end)
end

--- Stops pumps and clears all active mythlings.
function MythlingSpawnService.Stop()
	running = false
	for key, th in pairs(threads) do
		pcall(task.cancel, th)
		threads[key] = nil
	end
	for _, e in pairs(Active) do
		destroyEntry(e)
	end
	table.clear(Active)
end

--- Called after a mythling is claimed and saved (winner decided).
function MythlingSpawnService.OnClaimed(mythlingId: string, winner: Player)
	local e = Active[mythlingId]
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
		escortThenCleanup(e, winner, mythlingId, baseAnchor)
	else
		cleanupSoon(e, mythlingId)
	end
end

--- Returns the Active table (read-only by convention).
function MythlingSpawnService.GetActiveMythlings()
	return Active
end

return MythlingSpawnService
