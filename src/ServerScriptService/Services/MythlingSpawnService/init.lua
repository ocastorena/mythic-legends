--!strict
-- ServerScriptService/Services/MythlingSpawnService
-- Availability is independent of model presentation and ClaimService owns contest expiry.

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Domain.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)
local LogUtil = require(ServerScriptService.Infrastructure.LogUtil)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local ClaimEscort = require(script.ClaimEscort)
local SpawnPlacement = require(script.SpawnPlacement)
local SpawnPopulation = require(script.SpawnPopulation)

local MythlingSpawnService = {}
local log = LogUtil.For("MythlingSpawnService")
local lifecycle = ServiceLifecycle.new("MythlingSpawnService")
local random = Random.new()
local serviceContext: ServerTypes.Context
local population: SpawnPopulation.State
local contests: { [string]: ServerTypes.SpawnEntry } = {}
local encounterTroves: { [string]: Trove.Trove } = {}
local typesByRarity: { [string]: { string } } = {}
local weightedRarities: { { rarity: string, weight: number } } = {}
local totalWeight = 0
local pumpQueued = false
local freedPositions: { Vector3 } = {}
local maxRefillSeconds = 0
local deadlineMisses = 0

local function timeNow(): number
	return workspace:GetServerTimeNow()
end

local function isPositive(value: number): boolean
	return value > 0 and value < math.huge
end

local function chooseForm(): string?
	if totalWeight <= 0 then
		return nil
	end
	local roll = random:NextNumber(0, totalWeight)
	for _, option in weightedRarities do
		roll -= option.weight
		if roll <= 0 then
			local forms = typesByRarity[option.rarity]
			return forms[random:NextInteger(1, #forms)]
		end
	end
	return nil
end

local function countContests(): number
	local count = 0
	for _ in contests do
		count += 1
	end
	return count
end

local function queueDeficits()
	SpawnPopulation.QueueDeficits(population, countContests(), timeNow(), chooseForm)
end

local function sendAll(action: string, payload: { [string]: unknown })
	serviceContext.Remotes.World.Spawned:FireAllClients(action, payload)
end

local function setState(
	entry: ServerTypes.SpawnEntry,
	state: typeof(({} :: ServerTypes.SpawnEntry).state)
)
	entry.state = state
	entry.model:SetAttribute("State", state)
end

local function isValidEntry(entry: ServerTypes.SpawnEntry): boolean
	local zone = entry.zone
	return entry.model:IsDescendantOf(serviceContext.Instances.Mythlings)
		and zone ~= nil
		and zone:IsDescendantOf(entry.model)
end

local function destroyEntry(entry: ServerTypes.SpawnEntry)
	local owner = encounterTroves[entry.id]
	encounterTroves[entry.id] = nil
	entry.state = "DESPAWNED"
	if owner then
		lifecycle.trove:Remove(owner)
	end
end

local function arenaBounds(): SpawnPlacement.Bounds
	local arena = serviceContext.Instances.Arena
	local bounds: SpawnPlacement.Bounds = { radius = math.max(arena.Size.X, arena.Size.Z) / 2 }
	local sides = arena:GetAttribute("BoundarySides")
	local apothem = arena:GetAttribute("BoundaryApothem")
	if
		type(sides) == "number"
		and sides >= 3
		and sides < math.huge
		and type(apothem) == "number"
		and isPositive(apothem)
	then
		bounds.sides = math.floor(sides)
		bounds.apothem = apothem
		bounds.radius = apothem / math.cos(math.pi / math.floor(sides))
	end
	return bounds
end

local function findPosition(radius: number): Vector3?
	local arena = serviceContext.Instances.Arena
	local cfg = serviceContext.Configurations.MythlingSpawns
	local bounds = arenaBounds()
	local occupied: { SpawnPlacement.Ring } = {}
	for _, entry in contests do
		local zone = entry.zone
		if zone then
			local point = arena.CFrame:PointToObjectSpace(zone.Position)
			table.insert(occupied, { x = point.X, z = point.Z, radius = entry.radius })
		end
	end
	local function valid(x: number, z: number): boolean
		return SpawnPlacement.IsValid(
			x,
			z,
			radius,
			bounds,
			occupied,
			cfg.zonePadding,
			cfg.boundaryClearance
		)
	end
	local function worldPoint(x: number, z: number): Vector3
		return (arena.CFrame:PointToWorldSpace(Vector3.new(x, arena.Size.Y / 2, z)))
	end
	for _ = 1, cfg.maxPlacementTries do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = math.sqrt(random:NextNumber()) * bounds.radius
		local x, z = math.cos(angle) * distance, math.sin(angle) * distance
		if valid(x, z) then
			return worldPoint(x, z)
		end
	end
	-- Reusing a vacated center also recovers narrow valid gaps between existing rings.
	for _, position in freedPositions do
		local point = arena.CFrame:PointToObjectSpace(position)
		if valid(point.X, point.Z) then
			return worldPoint(point.X, point.Z)
		end
	end
	local x, z = SpawnPlacement.FindFallback(
		radius,
		bounds,
		occupied,
		cfg.zonePadding,
		cfg.boundaryClearance,
		cfg.fallbackStepStuds
	)
	if x and z then
		return worldPoint(x, z)
	end
	return nil
end

local function makeZone(radius: number, position: Vector3): BasePart
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Transparency = 1
	zone.Size = Vector3.new(radius * 2, 0.05, radius * 2)
	zone.CFrame = CFrame.new(position + Vector3.new(0, 0.05, 0))
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
	stroke.Color = Color3.fromRGB(103, 255, 158)
	stroke.Thickness = 5
	stroke.Transparency = 0.1
	stroke.Parent = ring
	CollectionService:AddTag(zone, "MythlingZone")
	return zone
end

local function resolveLifetime(typeId: string, definition: Types.MythlingDef): number
	local cfg = serviceContext.Configurations.MythlingSpawns
	return cfg.formExpireSeconds[typeId]
		or cfg.expireSeconds[definition.rarity]
		or cfg.defaultExpireSeconds
end

local function activate(entry: ServerTypes.SpawnEntry, now: number)
	local lifetime =
		resolveLifetime(entry.typeId, serviceContext.Configurations.Mythlings[entry.typeId])
	entry.startedAt = now
	entry.lifetimeSeconds = lifetime
	entry.expireAt = now + lifetime
	setState(entry, "SPAWNED")
	entry.model:SetAttribute("CaptureReady", true)
	entry.model:SetAttribute("StartedAt", now)
	entry.model:SetAttribute("ExpireAt", entry.expireAt)
	local timer = entry.model:FindFirstChild("MythlingExpireTimer")
	if timer and timer:IsA("BillboardGui") then
		timer.Enabled = true
	end
	sendAll("Spawned", {
		mythlingId = entry.id,
		typeId = entry.typeId,
		rarity = entry.rarity,
		variantId = entry.variantId,
		expireAt = entry.expireAt,
		zoneRadius = entry.radius,
		position = entry.model:GetPivot().Position,
	})
end

local function spawnAttempt(attempt: SpawnPopulation.Attempt): (boolean, string)
	local typeId = attempt.typeId
	if not typeId then
		return false, "no weighted form is available"
	end
	local definition = serviceContext.Configurations.Mythlings[typeId]
	if
		not definition
		or not isPositive(definition.zoneRadius)
		or not isPositive(definition.fillRate)
		or not (definition.drainRate >= 0 and definition.drainRate < math.huge)
		or not isPositive(resolveLifetime(typeId, definition))
		or resolveLifetime(typeId, definition) <= 100 / definition.fillRate
	then
		return false, "invalid form radius/capture rates, or lifetime leaves no arrival time"
	end
	local regular = definition.variants.regular
	local template = regular
		and serviceContext.Instances.MythlingAssets:FindFirstChild(regular.model)
	if
		not template
		or not template:IsA("Model")
		or not template.PrimaryPart
		or not template.Archivable
	then
		return false, "missing/non-cloneable model or PrimaryPart for configured regular variant"
	end
	local position = findPosition(definition.zoneRadius)
	if not position then
		return false, "no ring position meets boundary clearance and non-overlap"
	end
	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	local primary = model.PrimaryPart
	if not primary then
		model:Destroy()
		return false, "configured model PrimaryPart was not cloned; check Archivable"
	end
	primary.Anchored = true
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0))
	local zone = makeZone(definition.zoneRadius, position)
	zone.Parent = model
	local variants = model:FindFirstChild("Variants")
	local surface = variants and variants:FindFirstChild("regular")
	local mesh = model:FindFirstChildWhichIsA("MeshPart")
	if surface and surface.Archivable and mesh then
		surface:Clone().Parent = mesh
	end
	local billboards = serviceContext.Instances.Templates:FindFirstChild("Billboards")
	local timerTemplate = billboards and billboards:FindFirstChild("MythlingExpireTimer")
	if timerTemplate and timerTemplate:IsA("BillboardGui") and timerTemplate.Archivable then
		local timer = timerTemplate:Clone()
		timer.Name = "MythlingExpireTimer"
		timer.Adornee = primary
		timer.Enabled = false
		timer.Parent = model
	end
	local id = HttpService:GenerateGUID(false)
	local entry: ServerTypes.SpawnEntry = {
		id = id,
		displayName = definition.displayName,
		model = model,
		zone = zone,
		typeId = typeId,
		variantId = "regular",
		rarity = definition.rarity,
		radius = definition.zoneRadius,
		fillRate = definition.fillRate,
		drainRate = definition.drainRate,
		startedAt = 0,
		lifetimeSeconds = 0,
		expireAt = 0,
		state = "PREFILL",
	}
	model:SetAttribute("Id", id)
	model:SetAttribute("State", "PREFILL")
	model:SetAttribute("CaptureReady", false)
	model:SetAttribute("ExpireAt", nil)
	local owner = lifecycle.trove:Extend()
	encounterTroves[id] = owner
	owner:Add(model)
	contests[id] = entry
	model.Parent = serviceContext.Instances.Mythlings
	SpawnPopulation.Complete(population, attempt.id)
	if population.ready then
		activate(entry, timeNow())
	end
	return true, ""
end

local function refill()
	if not lifecycle:IsRunning() then
		return
	end
	queueDeficits()
	for _, attempt in SpawnPopulation.GetPending(population) do
		local replacement = population.ready
		local ok, reason = spawnAttempt(attempt)
		local completedAt = timeNow()
		if ok and replacement then
			local duration = completedAt - attempt.missingSince
			maxRefillSeconds = math.max(maxRefillSeconds, duration)
			serviceContext.Instances.Mythlings:SetAttribute("LastRefillSeconds", duration)
			serviceContext.Instances.Mythlings:SetAttribute("MaxRefillSeconds", maxRefillSeconds)
		end
		if
			(not ok or completedAt > attempt.deadlineAt)
			and SpawnPopulation.ReportDeadline(attempt, completedAt)
		then
			if replacement then
				deadlineMisses += 1
				serviceContext.Instances.Mythlings:SetAttribute(
					"RefillDeadlineMisses",
					deadlineMisses
				)
			end
			local detail = if ok then "completed after its refill deadline" else reason
			log.error(
				`Refill deadline missed for {attempt.typeId or "unavailable form"}: {detail}. Check MythlingSpawns placement tuning and model assets; target {population.target}, present {countContests()}.`
			)
		end
	end
	if SpawnPopulation.OpenIfFilled(population, countContests()) then
		local startedAt = timeNow()
		for _, entry in contests do
			activate(entry, startedAt)
		end
		serviceContext.Instances.Mythlings:SetAttribute("CaptureReady", true)
	end
	local failed = false
	for _, attempt in population.pending do
		failed = failed or attempt.warned
	end
	serviceContext.Instances.Mythlings:SetAttribute("RefillFailed", failed)
	if next(population.pending) == nil then
		table.clear(freedPositions)
	end
end

local function scheduleRefill()
	if pumpQueued or not lifecycle:IsRunning() then
		return
	end
	pumpQueued = true
	lifecycle.trove:Add(task.defer(function()
		lifecycle.trove:Pop(coroutine.running())
		pumpQueued = false
		refill()
	end))
end

local function unregister(entry: ServerTypes.SpawnEntry)
	contests[entry.id] = nil
	local zone = entry.zone
	if zone then
		table.insert(freedPositions, zone.Position)
	end
	entry.model:SetAttribute("CaptureReady", false)
	queueDeficits()
	scheduleRefill()
end

function MythlingSpawnService.Init(context: ServerTypes.Context)
	serviceContext = context
	local cfg = context.Configurations.MythlingSpawns
	assert(isPositive(cfg.targetActive) and cfg.targetActive % 1 == 0, "Invalid spawn target")
	assert(
		isPositive(cfg.refillDeadlineSeconds) and isPositive(cfg.refillRetrySeconds),
		"Invalid refill timing"
	)
	assert(
		isPositive(cfg.fallbackStepStuds)
			and cfg.zonePadding >= 0
			and cfg.zonePadding < math.huge
			and cfg.boundaryClearance >= 0
			and cfg.boundaryClearance < math.huge,
		"Invalid placement tuning"
	)
	local sides = context.Instances.Arena:GetAttribute("BoundarySides")
	assert(
		type(sides) ~= "number" or (sides >= 3 and sides <= 128),
		"Arena boundary exceeds bounded placement work"
	)
	assert(
		math.ceil(arenaBounds().radius / cfg.fallbackStepStuds) <= 128,
		"Fallback grid exceeds bounded placement work"
	)
	assert(
		cfg.maxPlacementTries >= 0
			and cfg.maxPlacementTries <= 256
			and cfg.maxPlacementTries % 1 == 0,
		"Invalid random placement budget"
	)
	population = SpawnPopulation.New(cfg.targetActive, cfg.refillDeadlineSeconds)
	for typeId, definition in context.Configurations.Mythlings do
		local rarity = definition.rarity
		local forms = typesByRarity[rarity] or {}
		typesByRarity[rarity] = forms
		table.insert(forms, typeId)
	end
	for rarity, weight in cfg.rarityWeights do
		local forms = typesByRarity[rarity]
		if isPositive(weight) and forms and #forms > 0 then
			table.sort(forms)
			table.insert(weightedRarities, { rarity = rarity, weight = weight })
			totalWeight += weight
		elseif weight > 0 then
			log.error(`Configured spawn rarity {rarity} has no forms`)
		end
	end
	table.sort(
		weightedRarities,
		function(
			left: { rarity: string, weight: number },
			right: { rarity: string, weight: number }
		)
			return left.rarity < right.rarity
		end
	)
	context.Instances.Mythlings:SetAttribute("CaptureReady", false)
	context.Instances.Mythlings:SetAttribute("RefillFailed", false)
	context.Instances.Mythlings:SetAttribute("LastRefillSeconds", 0)
	context.Instances.Mythlings:SetAttribute("MaxRefillSeconds", 0)
	context.Instances.Mythlings:SetAttribute("RefillDeadlineMisses", 0)
end

function MythlingSpawnService.Start()
	if not lifecycle:Start() then
		return
	end
	refill()
	lifecycle.trove:Add(task.defer(function()
		while lifecycle:IsRunning() do
			task.wait(serviceContext.Configurations.MythlingSpawns.refillRetrySeconds)
			-- External model/ring removal must release its slot as well.
			for id, entry in contests do
				if not isValidEntry(entry) then
					MythlingSpawnService.EndContest(id, "Removed")
				end
			end
			refill()
		end
	end))
end

function MythlingSpawnService.Stop()
	if not lifecycle:IsRunning() then
		return
	end
	table.clear(contests)
	lifecycle:Stop()
	table.clear(encounterTroves)
	table.clear(population.pending)
	table.clear(freedPositions)
	serviceContext.Instances.Mythlings:SetAttribute("CaptureReady", false)
end

function MythlingSpawnService.IsCaptureReady(): boolean
	return lifecycle:IsRunning() and population.ready
end

function MythlingSpawnService.EndContest(mythlingId: string, reason: string?)
	local entry = contests[mythlingId]
	if not entry then
		return
	end
	unregister(entry)
	setState(entry, "DESPAWNED")
	sendAll(
		"Expired",
		{ mythlingId = mythlingId, mythling = mythlingId, reason = reason or "Expired" }
	)
	destroyEntry(entry)
end

function MythlingSpawnService.SetOvertime(mythlingId: string)
	local entry = contests[mythlingId]
	if entry and entry.state == "SPAWNED" then
		setState(entry, "OVERTIME")
	end
end

function MythlingSpawnService.OnClaimed(mythlingId: string, winner: Player)
	local entry = contests[mythlingId]
	if not entry then
		return
	end
	unregister(entry)
	setState(entry, "CLAIMED")
	entry.ownerUserId = winner.UserId
	if entry.zone then
		entry.zone:Destroy()
		entry.zone = nil
	end
	local timer = entry.model:FindFirstChild("MythlingExpireTimer")
	if timer then
		timer:Destroy()
	end
	sendAll(
		"Claimed",
		{ mythlingId = mythlingId, winnerUserId = winner.UserId, displayName = entry.displayName }
	)
	local base = serviceContext.Instances.Bases:FindFirstChild(tostring(winner.UserId))
	local anchor = base and base:FindFirstChild("Front")
	local owner = encounterTroves[mythlingId]
	if anchor and anchor:IsA("BasePart") and entry.model.PrimaryPart and owner then
		setState(entry, "ESCORT")
		serviceContext.Remotes.World.Spawned:FireClient(
			winner,
			"EscortStart",
			{ mythlingId = mythlingId, baseCFrame = anchor.CFrame }
		)
		ClaimEscort.Start(entry, anchor, owner, function()
			destroyEntry(entry)
		end)
	else
		destroyEntry(entry)
	end
end

function MythlingSpawnService.GetActiveMythlings(): { [string]: ServerTypes.SpawnEntry }
	local active = {}
	if not MythlingSpawnService.IsCaptureReady() then
		return active
	end
	for id, entry in contests do
		if not isValidEntry(entry) then
			MythlingSpawnService.EndContest(id, "Removed")
		elseif entry.state == "SPAWNED" or entry.state == "OVERTIME" then
			active[id] = entry
		end
	end
	return active
end

return MythlingSpawnService
