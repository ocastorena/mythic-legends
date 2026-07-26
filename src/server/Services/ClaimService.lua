-- ServerScriptService/Services/ClaimService

local ClaimService = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = ReplicatedStorage:WaitForChild("Util")
local PlayerUtil = require(Util:WaitForChild("PlayerUtil"))
local LogUtil = require(Util:WaitForChild("LogUtil"))

local log = LogUtil.For("ClaimService")

local ClaimEvent: RemoteEvent
local SpawnService
local MythlingService
local MythlingsData

-- PlayersState[userId] = {
--   mythlingId: string?;              -- nil = not contesting
--   mode: "Idle" | "Filling" | "Draining";
--   progress: number;                 -- 0..100
--   lastUpdateTime: number;           -- os.clock()
-- }
local PlayersState: { [number]: any } = {}

-- how often we run server-side claim checks
local TICK_INTERVAL = 0.1

-- Slack on the zone edge, in studs, to absorb the round trip between the client noticing
-- it crossed the boundary and the server checking. Without it, a player walking the rim
-- flickers between filling and draining purely from latency.
local ZONE_TOLERANCE_STUDS = 4

-- Helpers

--- Horizontal distance only: the player stands above the zone disc, so including Y would
--- shrink the effective radius by the player's height.
local function distXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--- True when the player is physically standing in this mythling's zone, per the server's
--- own copy of the character. This is the authority for filling; client messages only
--- prompt an earlier re-check.
local function isPlayerInZone(player: Player, mythlingData): boolean
	local zone = mythlingData and mythlingData.zone
	if not zone then
		return false
	end
	local pos = PlayerUtil.GetPosition(player)
	if not pos then
		return false
	end
	return distXZ(pos, zone.Position) <= (zone.Size.X * 0.5 + ZONE_TOLERANCE_STUDS)
end

local function ensurePlayerState(player)
	local userId = player.UserId
	local state = PlayersState[userId]
	if not state then
		state = {
			mythlingId = nil,
			mode = "Idle",
			progress = 0,
			lastUpdateTime = os.clock(),
		}
		PlayersState[userId] = state
	end
	return state
end

local function resetPlayerClaimState(state)
	state.mythlingId = nil
	state.mode = "Idle"
	state.progress = 0
	state.lastUpdateTime = os.clock()
end

local function sendStateUpdate(userId, state, extra)
	-- One player’s state snapshot to all clients
	ClaimEvent:FireAllClients("StateUpdate", {
		userId = userId,
		mythlingId = state.mythlingId,
		mode = state.mode,
		progress = state.progress,
		fillRate = extra and extra.fillRate or nil,
		drainRate = extra and extra.drainRate or nil,
	})
end

local function sendClear(userId)
	ClaimEvent:FireAllClients("StateUpdate", {
		userId = userId,
		mythlingId = nil,
		mode = "Idle",
		progress = 0,
	})
end

local function handleClaimWin(player, mythlingId, mythlingData)
	if not mythlingData or mythlingData.claimed then
		return
	end
	mythlingData.claimed = true

	-- Notify SpawnService (reward, despawn, etc)
	if SpawnService and SpawnService.OnClaimed then
		SpawnService.OnClaimed(mythlingId, player)
	end

	-- Tell everyone who won
	ClaimEvent:FireAllClients("Claimed", {
		mythlingId = mythlingId,
		winnerId = player.UserId,
	})

	-- Reset any players tracking this mythling
	for userId, state in pairs(PlayersState) do
		if state.mythlingId == mythlingId then
			resetPlayerClaimState(state)
			sendClear(userId)
		end
	end
	-- send to Inventory Service to save mythling
	-- params:
	--   mythlingId (spawn id)  - optional, for analytics/backrefs
	--   typeId / typeName      - identify the Mythling kind
	--   rarity / variantId     - optional extra tags
	--   model                  - optional live model instance (to read traits/seed)
	MythlingService.SaveWonMythling(player, {
		typeId = mythlingData.typeId,
		variantId = "regular",
	})
end

local function integrateProgress(player, state, now, activeMythlings)
	-- Advance this player’s progress based on elapsed time + mode
	if state.mode == "Idle" or not state.mythlingId then
		state.lastUpdateTime = now
		return
	end

	local mythlingId = state.mythlingId
	local mythlingData = activeMythlings[mythlingId]
	if not mythlingData or mythlingData.claimed then
		-- Mythling gone; clear locally
		resetPlayerClaimState(state)
		sendClear(player.UserId)
		return
	end

	local cfg = MythlingsData[mythlingData.typeId]
	if not cfg then
		return
	end

	local dt = now - (state.lastUpdateTime or now)
	if dt <= 0 then
		state.lastUpdateTime = now
		return
	end
	state.lastUpdateTime = now

	if state.mode == "Filling" then
		state.progress += cfg.fillRate * dt
		if state.progress >= 100 then
			state.progress = 100
			handleClaimWin(player, mythlingId, mythlingData)
			return
		end
	elseif state.mode == "Draining" then
		state.progress -= cfg.drainRate * dt
		if state.progress <= 0 then
			state.progress = 0
			-- Fully lost; go idle & clear UI
			resetPlayerClaimState(state)
			sendClear(player.UserId)
			return
		end
	end
end

-- Verb handlers

local function handleInZone(player, payload)
	local userId = player.UserId
	if type(payload) ~= "table" then
		return
	end
	-- Position comes from the server's own copy of the character. The client used to send
	-- its position and we validated against that, which let a modified client claim any
	-- mythling from anywhere on the map.
	local mythlingId = payload.mythlingId

	local activeMythlings = SpawnService.GetActiveMythlings()
	local mythlingData = activeMythlings[mythlingId]
	if not mythlingData then
		return
	end

	-- Validate the player really is inside, against the server's own geometry.
	if not isPlayerInZone(player, mythlingData) then
		return
	end

	local state = ensurePlayerState(player)

	-- Before switching mode/mythling, integrate existing progress to "now"
	integrateProgress(player, state, os.clock(), activeMythlings)

	-- If they switch to a different mythling, reset progress
	if state.mythlingId ~= mythlingId then
		state.mythlingId = mythlingId
		state.progress = 0
	end

	-- Now they’re actively filling
	state.mode = "Filling"
	state.lastUpdateTime = os.clock()

	local cfg = MythlingsData[mythlingData.typeId]
	sendStateUpdate(userId, state, {
		fillRate = cfg.fillRate,
		drainRate = cfg.drainRate,
	})
end

local function handleOutZone(player)
	local userId = player.UserId
	local state = PlayersState[userId]
	if not state then
		return
	end

	local activeMythlings = SpawnService.GetActiveMythlings()
	integrateProgress(player, state, os.clock(), activeMythlings)

	if not state.mythlingId or state.progress <= 0 then
		-- Nothing to drain; just go idle & clear bar
		resetPlayerClaimState(state)
		sendClear(userId)
		return
	end

	-- Start draining from current progress
	state.mode = "Draining"
	state.lastUpdateTime = os.clock()

	local mythlingData = activeMythlings[state.mythlingId]
	if not mythlingData then
		resetPlayerClaimState(state)
		sendClear(userId)
		return
	end

	local cfg = MythlingsData[mythlingData.typeId]
	sendStateUpdate(userId, state, {
		fillRate = cfg.fillRate,
		drainRate = cfg.drainRate,
	})
end

-- Public

function ClaimService.Init(context)
	ClaimEvent = context.Remotes.ClaimEvent
	SpawnService = context.Services.SpawnService
	MythlingService = context.Services.MythlingService
	MythlingsData = context.Metadata.Mythlings

	PlayerUtil.OnPlayer(function(player)
		ensurePlayerState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayersState[player.UserId] = nil
	end)

	ClaimEvent.OnServerEvent:Connect(function(player, verb, payload)
		if verb == "InZone" then
			handleInZone(player, payload)
		elseif verb == "OutZone" then
			handleOutZone(player)
		end
	end)

	log.info("Initialized")
end

function ClaimService.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TICK_INTERVAL then
			return
		end
		acc = 0

		local now = os.clock()
		local activeMythlings = SpawnService.GetActiveMythlings()

		for userId, state in pairs(PlayersState) do
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				PlayersState[userId] = nil
			else
				-- Re-derive the mode from where the player actually is before advancing
				-- progress. The client's InZone/OutZone messages are only hints; a client
				-- that simply never sends OutZone would otherwise fill forever.
				if state.mythlingId then
					local mythlingData = activeMythlings[state.mythlingId]
					local inZone = isPlayerInZone(player, mythlingData)
					local expected = inZone and "Filling" or "Draining"

					if state.mode ~= expected and state.mode ~= "Idle" then
						integrateProgress(player, state, now, activeMythlings)
						-- integrateProgress may have cleared the claim entirely
						if state.mythlingId then
							state.mode = expected
							state.lastUpdateTime = now
							local cfg = MythlingsData[mythlingData.typeId]
							sendStateUpdate(userId, state, cfg)
						end
					end
				end

				integrateProgress(player, state, now, activeMythlings)
			end
		end
	end)

	log.info("Started")
end

return ClaimService
