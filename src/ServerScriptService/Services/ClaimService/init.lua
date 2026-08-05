-- ServerScriptService/Services/ClaimService

local ClaimService = {}
local connections: { RBXScriptConnection } = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))

local ClaimEvent: RemoteEvent
local MythlingSpawnService
local InventoryService
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

-- Slack on the zone edge, in studs. Character positions replicate to the server with some
-- lag, so without a margin a player walking the rim flickers between filling and draining.
local ZONE_TOLERANCE_STUDS = 4

-- Helpers

--- Horizontal distance only: the player stands above the zone disc, so including Y would
--- shrink the effective radius by the player's height.
local function distXZ(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
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

	-- Notify MythlingSpawnService (reward, despawn, etc.)
	if MythlingSpawnService and MythlingSpawnService.OnClaimed then
		MythlingSpawnService.OnClaimed(mythlingId, player)
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
	-- Add the claimed mythling to the player's inventory.
	-- params:
	--   mythlingId (spawn id)  - optional, for analytics/backrefs
	--   typeId / typeName      - identify the Mythling kind
	--   rarity / variantId     - optional extra tags
	--   model                  - optional live model instance (to read traits/seed)
	InventoryService.SaveWonMythling(player, {
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

--- The id of whichever active mythling's zone the player is standing in, or nil.
local function findZoneUnderPlayer(player: Player, activeMythlings): string?
	local pos = PlayerUtil.GetPosition(player)
	if not pos then
		return nil
	end
	for mythlingId, data in pairs(activeMythlings) do
		if not data.claimed and data.zone then
			if distXZ(pos, data.zone.Position) <= (data.zone.Size.X * 0.5 + ZONE_TOLERANCE_STUDS) then
				return mythlingId
			end
		end
	end
	return nil
end

--- Derives mode and target purely from where the player is standing.
---
--- This is the authority. Entry used to rely on a single client "InZone" message sent on
--- the transition -- if the server rejected that one message (for example the character
--- had just respawned and its position had not replicated yet) the client never re-sent,
--- and the player could stand in a zone indefinitely with nothing happening.
local function resolveState(player: Player, state, now: number, activeMythlings)
	local userId = player.UserId
	local zoneMythlingId = findZoneUnderPlayer(player, activeMythlings)

	-- Standing in a zone that is not the one we were tracking: switch to it.
	if zoneMythlingId and state.mythlingId ~= zoneMythlingId then
		integrateProgress(player, state, now, activeMythlings)
		state.mythlingId = zoneMythlingId
		state.progress = 0
		state.mode = "Filling"
		state.lastUpdateTime = now
		local data = activeMythlings[zoneMythlingId]
		sendStateUpdate(userId, state, MythlingsData[data.typeId])
		return
	end

	if not state.mythlingId then
		return
	end

	local expected = zoneMythlingId and "Filling" or "Draining"
	if state.mode == expected or state.mode == "Idle" then
		return
	end

	integrateProgress(player, state, now, activeMythlings)
	if not state.mythlingId then
		return -- integrateProgress cleared the claim
	end

	state.mode = expected
	state.lastUpdateTime = now
	local data = activeMythlings[state.mythlingId]
	if data then
		sendStateUpdate(userId, state, MythlingsData[data.typeId])
	end
end

-- Zone entry and exit are derived from the character's position in the tick above, so
-- there are no client verbs to handle. ClaimEvent is server -> client only.

-- Public

function ClaimService.Init(context)
	ClaimEvent = context.Remotes.World.ClaimState
	MythlingSpawnService = context.Services.MythlingSpawnService
	InventoryService = context.Services.InventoryService
	MythlingsData = context.Configurations.Mythlings
end

function ClaimService.Start()
	table.insert(
		connections,
		PlayerUtil.OnPlayer(function(player)
			ensurePlayerState(player)
		end)
	)

	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			PlayersState[player.UserId] = nil
		end)
	)

	local acc = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < TICK_INTERVAL then
				return
			end
			acc = 0

			local now = os.clock()
			local activeMythlings = MythlingSpawnService.GetActiveMythlings()

			for userId, state in pairs(PlayersState) do
				local player = Players:GetPlayerByUserId(userId)
				if not player then
					PlayersState[userId] = nil
				else
					resolveState(player, state, now, activeMythlings)
					integrateProgress(player, state, now, activeMythlings)
				end
			end
		end)
	)
end

function ClaimService.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(PlayersState)
end

return ClaimService
