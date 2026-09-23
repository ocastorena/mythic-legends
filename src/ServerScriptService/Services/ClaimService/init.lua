--!strict
-- ServerScriptService/Services/ClaimService
-- One ordered lifecycle owns membership, independent meters, expiry, and capture awards.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerTypes = require(ServerScriptService.Domain.Types)
local PlayerUtil = require(ServerScriptService.Infrastructure.PlayerUtil)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local ContestState = require(script.ContestState)

type Contest = { entry: ServerTypes.SpawnEntry, accounting: ContestState.State }
type Snapshot = { character: Model, position: Vector3, eligible: boolean }
type PendingAward = { contestId: string, candidate: ContestState.Candidate }
type PlayerLifetime = { trove: Trove.Trove, characterTrove: Trove.Trove }

local ClaimService = {}
local lifecycle = ServiceLifecycle.new("ClaimService")
local claimEvent: RemoteEvent
local SpawnService: ServerTypes.SpawnApi
local InventoryService: ServerTypes.InventoryApi
local config: Types.MythlingSpawnConfiguration
local contests: { [string]: Contest } = {}
local playerLifetimes: { [Player]: PlayerLifetime } = {}
local characters: { [number]: Model } = {}
local lastFocused: { [number]: string } = {}
local lastSent: { [number]: Types.ClaimUpdate } = {}
local PROJECTION_INTERVAL = 1

local function sendProjection(packet: Types.ClaimUpdate, force: boolean?)
	local previous = lastSent[packet.userId]
	if
		not force
		and previous
		and previous.mythlingId == packet.mythlingId
		and previous.mode == packet.mode
		and previous.character == packet.character
		and (packet.mode == "Idle" or packet.sampledAt - previous.sampledAt < PROJECTION_INTERVAL)
	then
		return
	end
	lastSent[packet.userId] = packet
	claimEvent:FireAllClients("StateUpdate", packet)
end

local function clearProjection(userId: number, now: number)
	lastFocused[userId] = nil
	local player = Players:GetPlayerByUserId(userId)
	sendProjection({
		userId = userId,
		mode = "Idle",
		progress = 0,
		character = player and player.Character,
		sampledAt = now,
	}, true)
end

local function aliveCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character or not character.Parent or characters[player.UserId] ~= character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

local function clearIneligibleMeters(userId: number)
	for _, contest in contests do
		ContestState.RejectCandidate(contest.accounting, userId)
	end
end

local function resolveAwards(pending: { PendingAward })
	local active = SpawnService.GetActiveMythlings()
	table.sort(pending, function(left: PendingAward, right: PendingAward)
		if left.candidate.completionAt ~= right.candidate.completionAt then
			return left.candidate.completionAt < right.candidate.completionAt
		end
		if left.contestId ~= right.contestId then
			return left.contestId < right.contestId
		end
		if left.candidate.visitOrder ~= right.candidate.visitOrder then
			return left.candidate.visitOrder < right.candidate.visitOrder
		end
		return left.candidate.userId < right.candidate.userId
	end)
	for _, pendingAward in pending do
		local contest = contests[pendingAward.contestId]
		local candidate = pendingAward.candidate
		if not contest or contest.accounting.phase == "ENDED" then
			continue
		end
		local entry = contest.entry
		if active[pendingAward.contestId] ~= entry then
			SpawnService.EndContest(pendingAward.contestId, "Expired")
			contests[pendingAward.contestId] = nil
			continue
		end
		if
			entry.claimed
			or entry.claiming
			or not contest.accounting.pendingCandidates[candidate.userId]
		then
			continue
		end
		local player = Players:GetPlayerByUserId(candidate.userId)
		local character = player and aliveCharacter(player)
		local capacity = player and InventoryService.GetMythlingCapacity(player)
		if not player or not character or not capacity or capacity.used >= capacity.limit then
			clearIneligibleMeters(candidate.userId)
			continue
		end
		-- Final eligibility, inventory mutation, and contest closure do not yield.
		-- The inventory boundary repeats capacity/profile checks before its existing save request.
		entry.claiming = true
		local ownedId = InventoryService.SaveWonMythling(player, {
			typeId = entry.typeId,
			variantId = entry.variantId,
		})
		entry.claiming = nil
		if not ownedId then
			clearIneligibleMeters(candidate.userId)
			continue
		end
		assert(
			ContestState.AcceptWinner(contest.accounting, candidate.userId),
			"[ClaimService] Lost winning candidate"
		)
		entry.claimed = true
		SpawnService.OnClaimed(pendingAward.contestId, player)
		claimEvent:FireAllClients("Claimed", {
			mythlingId = pendingAward.contestId,
			winnerId = candidate.userId,
		})
		local remaining = InventoryService.GetMythlingCapacity(player)
		if not remaining or remaining.used >= remaining.limit then
			clearIneligibleMeters(candidate.userId)
		end
	end
end

local function finishContests()
	for id, contest in contests do
		ContestState.Finalize(contest.accounting)
		if contest.accounting.phase == "ENDED" then
			if not contest.accounting.winnerUserId then
				SpawnService.EndContest(id, "Expired")
			end
			contests[id] = nil
		elseif contest.accounting.phase == "OVERTIME" then
			SpawnService.SetOvertime(id)
		end
	end
end

local function removePlayer(userId: number)
	characters[userId] = nil
	local now = workspace:GetServerTimeNow()
	local pending: { PendingAward } = {}
	for id, contest in contests do
		for _, candidate in ContestState.RemovePlayer(contest.accounting, now, userId) do
			table.insert(pending, { contestId = id, candidate = candidate })
		end
	end
	resolveAwards(pending)
	finishContests()
	clearProjection(userId, now)
end

local function collectSnapshots(): { [number]: Snapshot }
	local snapshots: { [number]: Snapshot } = {}
	for player in playerLifetimes do
		local character, root = aliveCharacter(player)
		if player.Parent ~= Players or not character or not root then
			continue
		end
		local capacity = InventoryService.GetMythlingCapacity(player)
		local eligible = capacity ~= nil and capacity.used < capacity.limit
		if not eligible then
			clearIneligibleMeters(player.UserId)
		end
		snapshots[player.UserId] = {
			character = character,
			position = root.Position,
			eligible = eligible,
		}
	end
	return snapshots
end

local function project(snapshots: { [number]: Snapshot }, now: number)
	for player in playerLifetimes do
		local userId = player.UserId
		local snapshot = snapshots[userId]
		local selectedId: string? = nil
		local highestProgress = -1
		for id, contest in contests do
			local state = contest.accounting
			if snapshot and state.occupants[userId] ~= nil then
				selectedId = id
				lastFocused[userId] = id
				break
			end
			local meter = state.meters[userId]
			if meter and meter.progress > 0 then
				if id == lastFocused[userId] then
					selectedId = id
					highestProgress = math.huge
				elseif meter.progress > highestProgress then
					selectedId = id
					highestProgress = meter.progress
				end
			end
		end
		local selected = selectedId and contests[selectedId]
		if not snapshot or not selected then
			sendProjection({
				userId = userId,
				mode = "Idle",
				progress = 0,
				character = player.Character,
				sampledAt = now,
			})
			continue
		end
		local state = selected.accounting
		local meter = state.meters[userId]
		local capacity = InventoryService.GetMythlingCapacity(player)
		local full = capacity ~= nil and capacity.used >= capacity.limit
		if not meter and not full then
			sendProjection({
				userId = userId,
				mode = "Idle",
				progress = 0,
				character = player.Character,
				sampledAt = now,
			})
			continue
		end
		local mode: Types.ClaimMode = if full
			then "Full"
			elseif meter and meter.inside then "Filling"
			else "Draining"
		sendProjection({
			userId = userId,
			mythlingId = selectedId,
			mode = mode,
			progress = if meter then meter.progress else 0,
			fillRate = state.fillRate,
			drainRate = state.drainRate,
			character = snapshot.character,
			sampledAt = now,
		})
	end
end

local function step()
	local now = workspace:GetServerTimeNow()
	local active = SpawnService.GetActiveMythlings()
	for id in contests do
		if not active[id] then
			contests[id] = nil
		end
	end
	local snapshots = collectSnapshots()
	local pending: { PendingAward } = {}
	for id, entry in active do
		local zone = entry.zone
		if not zone or not zone.Parent or not entry.model.Parent then
			SpawnService.EndContest(id, "Expired")
			contests[id] = nil
			continue
		end
		local contest = contests[id]
		if not contest then
			local created: Contest = {
				entry = entry :: ServerTypes.SpawnEntry,
				accounting = ContestState.New(
					entry.startedAt,
					entry.expireAt,
					entry.fillRate,
					entry.drainRate
				),
			}
			contests[id] = created
			contest = created
		end
		local occupants: ContestState.Occupants = {}
		for userId, snapshot in snapshots do
			local position, center = snapshot.position, zone.Position
			if
				ContestState.Contains(
					position.X,
					position.Y,
					position.Z,
					center.X,
					center.Y,
					center.Z,
					entry.radius,
					config.ringVerticalAllowanceStuds
				)
			then
				occupants[userId] = snapshot.eligible
			end
		end
		for _, candidate in ContestState.SetOccupants(contest.accounting, now, occupants) do
			table.insert(pending, { contestId = id, candidate = candidate })
		end
	end
	resolveAwards(pending)
	finishContests()
	project(snapshots, now)
end

local function bindPlayer(player: Player)
	if playerLifetimes[player] then
		return
	end
	local owner = lifecycle.trove:Extend()
	local lifetime: PlayerLifetime = { trove = owner, characterTrove = owner:Extend() }
	playerLifetimes[player] = lifetime
	local function bindCharacter(character: Model)
		lifetime.characterTrove:Clean()
		removePlayer(player.UserId)
		characters[player.UserId] = character
		local boundHumanoid: Humanoid? = nil
		local function bindHumanoid()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid == boundHumanoid then
				return
			end
			boundHumanoid = humanoid
			lifetime.characterTrove:Connect(humanoid.Died, function()
				if characters[player.UserId] == character then
					removePlayer(player.UserId)
				end
			end)
		end
		lifetime.characterTrove:Connect(character.ChildAdded, bindHumanoid)
		bindHumanoid()
	end
	owner:Connect(player.CharacterAdded, bindCharacter)
	owner:Connect(player.CharacterRemoving, function(character)
		if characters[player.UserId] == character then
			removePlayer(player.UserId)
			lifetime.characterTrove:Clean()
		end
	end)
	if player.Character then
		bindCharacter(player.Character)
	end
end

function ClaimService.Init(context: ServerTypes.Context)
	claimEvent = context.Remotes.World.ClaimState
	SpawnService = context.Services.MythlingSpawnService
	InventoryService = context.Services.InventoryService
	config = context.Configurations.MythlingSpawns
end

function ClaimService.Start()
	if not lifecycle:Start() then
		return
	end
	PlayerUtil.OnPlayer(bindPlayer, lifecycle.trove)
	lifecycle.trove:Connect(Players.PlayerRemoving, function(player)
		removePlayer(player.UserId)
		local lifetime = playerLifetimes[player]
		if lifetime then
			playerLifetimes[player] = nil
			lifecycle.trove:Remove(lifetime.trove)
		end
		lastSent[player.UserId] = nil
	end)
	local elapsed = 0
	lifecycle.trove:Connect(RunService.Heartbeat, function(deltaSeconds)
		elapsed += deltaSeconds
		if elapsed < config.captureTickSeconds then
			return
		end
		elapsed = 0
		step()
	end)
end

function ClaimService.Stop()
	if not lifecycle:Stop() then
		return
	end
	for userId in lastSent do
		clearProjection(userId, workspace:GetServerTimeNow())
	end
	table.clear(contests)
	table.clear(playerLifetimes)
	table.clear(characters)
	table.clear(lastFocused)
	table.clear(lastSent)
end

return ClaimService
