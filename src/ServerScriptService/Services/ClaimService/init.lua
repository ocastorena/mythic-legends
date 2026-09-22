--!strict
-- ServerScriptService/Services/ClaimService

local ClaimService = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local PlayerUtil = require(infrastructure:WaitForChild("PlayerUtil"))
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local ServerTypes = require(ServerScriptService.Domain.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local lifecycle = ServiceLifecycle.new("ClaimService")

local claimEvent: RemoteEvent
local MythlingSpawnService: ServerTypes.SpawnApi
local InventoryService: ServerTypes.InventoryApi
local MythlingsData: { [string]: Types.MythlingDef }

-- PlayersState[userId] = {
--   mythlingId: string?;              -- nil = not contesting
--   mode: "Idle" | "Filling" | "Draining";
--   progress: number;                 -- 0..100
--   lastUpdateTime: number;           -- os.clock()
-- }
type ClaimState = {
	mythlingId: string?,
	mode: "Idle" | "Filling" | "Draining",
	progress: number,
	lastUpdateTime: number,
}
type ActiveMythlings = { [string]: ServerTypes.SpawnEntry }
local playersState: { [number]: ClaimState } = {}

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

local function ensurePlayerState(player: Player): ClaimState
	local existing = playersState[player.UserId]
	if existing then
		return existing
	end
	local created: ClaimState = {
		mythlingId = nil,
		mode = "Idle",
		progress = 0,
		lastUpdateTime = os.clock(),
	}
	playersState[player.UserId] = created
	return created
end

local function resetPlayerClaimState(state: ClaimState)
	state.mythlingId = nil
	state.mode = "Idle"
	state.progress = 0
	state.lastUpdateTime = os.clock()
end

local function sendStateUpdate(userId: number, state: ClaimState, extra: Types.MythlingDef?)
	-- One player’s state snapshot to all clients
	claimEvent:FireAllClients("StateUpdate", {
		userId = userId,
		mythlingId = state.mythlingId,
		mode = state.mode,
		progress = state.progress,
		fillRate = extra and extra.fillRate or nil,
		drainRate = extra and extra.drainRate or nil,
	})
end

local function sendClear(userId: number)
	claimEvent:FireAllClients("StateUpdate", {
		userId = userId,
		mythlingId = nil,
		mode = "Idle",
		progress = 0,
	})
end

local function handleClaimWin(
	player: Player,
	mythlingId: string,
	mythlingData: ServerTypes.SpawnEntry
)
	if not mythlingData or mythlingData.claimed or mythlingData.claiming then
		return
	end
	mythlingData.claiming = true

	-- Commit ownership before removing the contest. The guard protects this transaction if
	-- persistence later gains a yielding step; the current mutation and save request do not yield.
	local ownedMythlingId = InventoryService.SaveWonMythling(player, {
		typeId = mythlingData.typeId,
		variantId = mythlingData.variantId or "regular",
	})
	if not ownedMythlingId then
		mythlingData.claiming = nil
		return
	end
	mythlingData.claiming = nil
	mythlingData.claimed = true

	-- Notify MythlingSpawnService (reward, despawn, etc.)
	if MythlingSpawnService and MythlingSpawnService.OnClaimed then
		MythlingSpawnService.OnClaimed(mythlingId, player)
	end

	-- Tell everyone who won
	claimEvent:FireAllClients("Claimed", {
		mythlingId = mythlingId,
		winnerId = player.UserId,
	})

	-- Reset any players tracking this mythling
	for userId, state in pairs(playersState) do
		if state.mythlingId == mythlingId then
			resetPlayerClaimState(state)
			sendClear(userId)
		end
	end
end

local function integrateProgress(
	player: Player,
	state: ClaimState,
	now: number,
	activeMythlings: ActiveMythlings
)
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
local function findZoneUnderPlayer(player: Player, activeMythlings: ActiveMythlings): string?
	local pos = PlayerUtil.GetPosition(player)
	if not pos then
		return nil
	end
	for mythlingId, data in pairs(activeMythlings) do
		if not data.claimed and data.zone then
			if
				distXZ(pos, data.zone.Position) <= (data.zone.Size.X * 0.5 + ZONE_TOLERANCE_STUDS)
			then
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
local function resolveState(
	player: Player,
	state: ClaimState,
	now: number,
	activeMythlings: ActiveMythlings
)
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

	local expected: "Filling" | "Draining" = if zoneMythlingId then "Filling" else "Draining"
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

function ClaimService.Init(serviceContext: ServerTypes.Context)
	claimEvent = serviceContext.Remotes.World.ClaimState
	MythlingSpawnService = serviceContext.Services.MythlingSpawnService
	InventoryService = serviceContext.Services.InventoryService
	MythlingsData = serviceContext.Configurations.Mythlings
end

function ClaimService.Start()
	if not lifecycle:Start() then
		return
	end
	PlayerUtil.OnPlayer(function(player: Player)
		ensurePlayerState(player)
	end, lifecycle.trove)
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player: Player)
		playersState[player.UserId] = nil
	end)
	local accumulatedSeconds = 0
	lifecycle.trove:Connect(RunService.Heartbeat, function(deltaSeconds: number)
		accumulatedSeconds += deltaSeconds
		if accumulatedSeconds < TICK_INTERVAL then
			return
		end
		accumulatedSeconds = 0
		local now = os.clock()
		local activeMythlings = MythlingSpawnService.GetActiveMythlings()
		for userId, state in playersState do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				resolveState(player, state, now, activeMythlings)
				integrateProgress(player, state, now, activeMythlings)
			else
				playersState[userId] = nil
			end
		end
	end)
end

function ClaimService.Stop()
	if lifecycle:Stop() then
		table.clear(playersState)
	end
end

return ClaimService
