--!strict
-- ServerScriptService/Services/DataService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))
local ProfileStore =
	require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))
local PlayerDataTemplate =
	require(ServerStorage:WaitForChild("Databases"):WaitForChild("PlayerDataTemplate"))
local Transactions = require(script.Transactions)
local Projection = require(script.Projection)
local ProfileSchema = require(script.ProfileSchema)
local ProfileSettlements = require(script.ProfileSettlements)
local MutationPreparations = require(script.MutationPreparations)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local Trove = require(ReplicatedStorage.Packages.Trove)
local lifecycle = ServiceLifecycle.new("DataService")

local log = LogUtil.For("DataService")

export type PlayerData = Types.PlayerDoc
export type StatePacket = Types.StatePacket

type Profile = ProfileStore.Profile<PlayerData>
local startSession: ((string, { Cancel: () -> boolean, Steal: boolean? }) -> Profile?)?

local DataService = {}
local settlements = ProfileSettlements.new()
local preparations = MutationPreparations.new()
local stopping = false

local profiles: { [Player]: Profile } = {}
local profileTroves: { [Profile]: Trove.Trove } = {}
local loading: { [Player]: boolean } = {}
local releasing: { [Player]: Profile } = {}
local closingProfiles: { [Profile]: boolean } = {}
local revisions: { [Player]: number } = {}
local projections: { [Player]: { [string]: any } } = {}
local loadedBindable = Instance.new("BindableEvent")
local releasedBindable = Instance.new("BindableEvent")
lifecycle.trove:Add(loadedBindable)
lifecycle.trove:Add(releasedBindable)

DataService.OnLoaded = loadedBindable.Event
DataService.OnReleased = releasedBindable.Event

local updateState: RemoteEvent?
local requestState: RemoteFunction?
local stateRequestLimiter = RateLimiter.new(6, 1)

local function isRunning(): boolean
	return not stopping and lifecycle:IsRunning()
end

local function asSettlementProfile(profile: Profile): ProfileSettlements.Profile
	-- ProfileStore intersects Data with its recursive JSON schema and uses a dynamic method self.
	-- Adapt that vendor type once, retaining the exact profile identity and canonical document.
	return (profile :: unknown) :: ProfileSettlements.Profile
end

local function finalizeProfile(player: Player, profile: Profile)
	-- External/shutdown final saves are closing boundaries too, but are not intentional
	-- player releases. Keep that distinction so an external session loss still kicks.
	closingProfiles[profile] = true
	local result = settlements.Finalize(asSettlementProfile(profile))
	if not result.ok then
		-- Retain the last valid cursor for recovery; a failed boundary must not advance it.
		log.error(`Profile release settlement failed for userId {player.UserId}`, result.code)
	end
end

local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local clone = {}
	for key, child in pairs(value) do
		clone[deepClone(key)] = deepClone(child)
	end
	return clone
end

local function deepEqual(left: any, right: any): boolean
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	for key, value in pairs(left) do
		if not deepEqual(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function makeSnapshot(player: Player): StatePacket?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local projection = Projection.Build(profile.Data)
	projections[player] = projection
	return {
		revision = revisions[player] or 0,
		values = deepClone(projection),
		full = true,
	}
end

local function publishChanges(player: Player, forceFull: boolean?)
	local profile = profiles[player]
	if not profile or not profile:IsActive() or player.Parent ~= Players then
		return
	end

	local previous = projections[player] or {}
	local current = Projection.Build(profile.Data)
	local values = {}
	local removed = {}

	for key, value in pairs(current) do
		if forceFull or not deepEqual(value, previous[key]) then
			values[key] = deepClone(value)
		end
	end
	for key in pairs(previous) do
		if current[key] == nil then
			table.insert(removed, key)
		end
	end

	projections[player] = current
	if next(values) == nil and #removed == 0 then
		return
	end

	revisions[player] = (revisions[player] or 0) + 1
	local packet: StatePacket = {
		revision = revisions[player],
		values = values,
		removed = if #removed > 0 then removed else nil,
	}
	local remote = updateState
	if remote then
		remote:FireClient(player, packet)
	end
end

function DataService.Init(serviceContext: ServerTypes.Context)
	updateState = serviceContext.Remotes.State.Update
	requestState = serviceContext.Remotes.State.Request
end

function DataService.RegisterProfileSettlement(owner: string, settle: ServerTypes.ProfileSettlement)
	assert(not stopping and not lifecycle:IsRunning(), "[DataService] Register before Start")
	settlements.Register(owner, settle)
end

function DataService.RegisterMutationPreparation(
	owner: string,
	prepare: ServerTypes.MutationPreparation
)
	assert(not stopping and not lifecycle:IsRunning(), "[DataService] Register before Start")
	preparations.Register(owner, prepare)
end

function DataService.Start()
	if not lifecycle:Start() then
		return
	end
	settlements.Seal()
	preparations.Seal()
	-- The vendor's recursive JSONAcceptable intersection cannot infer this valid nested template.
	-- Isolate that constructor adaptation; all loaded documents retain their canonical type.
	local liveStore: ProfileStore.ProfileStore<PlayerData> =
		ProfileStore.New(Configuration.storeName, PlayerDataTemplate :: any)
	local playerStore = if RunService:IsStudio() then liveStore.Mock else liveStore
	startSession = function(
		key: string,
		parameters: { Cancel: () -> boolean, Steal: boolean? }
	): Profile?
		return playerStore:StartSessionAsync(key, parameters)
	end
	if requestState then
		requestState.OnServerInvoke = function(player: Player): StatePacket?
			if not stateRequestLimiter:Allow(player) then
				return nil
			end
			if not DataService.Load(player) then
				return nil
			end
			return makeSnapshot(player)
		end
	end
end

function DataService.Load(player: Player): boolean
	if not isRunning() then
		return false
	end
	local existing = profiles[player]
	if existing and closingProfiles[existing] then
		return false
	end
	if existing and existing:IsActive() then
		return true
	end

	if loading[player] then
		repeat
			task.wait()
		until not loading[player] or player.Parent ~= Players or not isRunning()
		local loaded = profiles[player]
		return isRunning()
			and player.Parent == Players
			and loaded ~= nil
			and not closingProfiles[loaded]
			and loaded:IsActive()
	end

	if player.Parent ~= Players then
		return false
	end

	loading[player] = true
	local loadSession = startSession
	assert(loadSession, "[DataService] Profile store is not started")
	local ok, result = pcall(function()
		return loadSession(Configuration.profileKeyPrefix .. player.UserId, {
			Cancel = function()
				return player.Parent ~= Players or not isRunning()
			end,
		})
	end)
	if not ok then
		loading[player] = nil
		log.error(`Profile load threw for userId {player.UserId}`, result)
		if isRunning() and player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return false
	end

	local profile = result
	if not profile then
		loading[player] = nil
		if isRunning() and player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return false
	end
	if not isRunning() or player.Parent ~= Players or not profile:IsActive() then
		loading[player] = nil
		profile:EndSession()
		return false
	end

	-- Keep admission serialized through preparation and Ready settlement. No consumer can obtain
	-- the profile until every registered rule has accepted the same detached document.
	local admitted, admissionError = pcall(function(): boolean
		profile:AddUserId(player.UserId)
		local prepared, schemaError = ProfileSchema.Prepare(profile.Data, function()
			return HttpService:GenerateGUID(false)
		end, workspace:GetServerTimeNow())
		if not prepared then
			log.error(`Profile schema preparation failed for userId {player.UserId}`, schemaError)
			return false
		end
		profile:Reconcile()
		local ready = settlements.Run(asSettlementProfile(profile), "Ready", function()
			return isRunning() and player.Parent == Players and profiles[player] == nil
		end)
		if not ready.ok then
			log.error(`Profile ready settlement failed for userId {player.UserId}`, ready.code)
			return false
		end

		local profileTrove = lifecycle.trove:Extend()
		profileTroves[profile] = profileTrove
		-- ProfileStore fires this before removing active ownership and before its final save.
		-- Its signal starts listeners synchronously until their first yield; our coordinator
		-- rejects yielding callbacks. Finalize also suppresses a preceding manual Release.
		local lastSaveConnection = profile.OnLastSave:Connect(function()
			finalizeProfile(player, profile)
		end)
		profileTrove:Add(function()
			lastSaveConnection:Disconnect()
		end)
		local endedConnection = profile.OnSessionEnd:Connect(function()
			local endedIntentionally = releasing[player] == profile
			if endedIntentionally then
				releasing[player] = nil
			end
			-- A late end notification from an older profile must not erase a replacement.
			if profiles[player] == profile then
				profiles[player] = nil
				projections[player] = nil
				revisions[player] = nil
				if isRunning() then
					releasedBindable:Fire(player)
				end
				if isRunning() and not endedIntentionally and player.Parent == Players then
					player:Kick("Your data session ended on another server. Please rejoin.")
				end
			end
			closingProfiles[profile] = nil
			profileTroves[profile] = nil
			lifecycle.trove:Remove(profileTrove)
		end)
		profileTrove:Add(function()
			endedConnection:Disconnect()
		end)

		if not isRunning() or player.Parent ~= Players or not profile:IsActive() then
			return false
		end
		profiles[player] = profile
		revisions[player] = 0
		local playerData: PlayerData = profile.Data
		playerData.profile.userId = player.UserId
		if playerData.profile.createdAt == 0 then
			playerData.profile.createdAt = os.time()
		end
		playerData.profile.lastLoginAt = os.time()
		projections[player] = {}
		publishChanges(player, true)
		loadedBindable:Fire(player, playerData)
		return true
	end)
	loading[player] = nil
	if admitted and admissionError then
		return true
	end
	if not admitted then
		log.error(`Profile preparation threw for userId {player.UserId}`, admissionError)
	end
	if profile:IsActive() then
		profile:EndSession()
	end
	if isRunning() and player.Parent == Players then
		player:Kick("Your data could not be updated safely. Please rejoin.")
	end
	return false
end

function DataService.Release(player: Player)
	stateRequestLimiter:Forget(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	releasing[player] = profile
	if profile:IsActive() then
		finalizeProfile(player, profile)
		profile:EndSession()
	end
	if profiles[player] == profile then
		profiles[player] = nil
		projections[player] = nil
		revisions[player] = nil
	end
end

function DataService.GetLoadedData(player: Player): PlayerData?
	local profile = profiles[player]
	return if isRunning()
			and profile
			and not closingProfiles[profile]
			and profile:IsActive()
		then profile.Data
		else nil
end

function DataService.GetData(player: Player): PlayerData
	assert(DataService.Load(player), "[DataService] Player profile is unavailable")
	local data = DataService.GetLoadedData(player)
	assert(data, "[DataService] Player profile is inactive")
	return data
end

function DataService.MarkDirty(player: Player): boolean
	local profile = profiles[player]
	if not isRunning() or not profile or closingProfiles[profile] or not profile:IsActive() then
		return false
	end
	Transactions.Invalidate(profile.Data)
	publishChanges(player)
	return true
end

function DataService.Transact(
	player: Player,
	request: Types.TransactionRequest,
	mutate: ServerTypes.ProfileMutation
): Types.TransactionResult
	local profile = profiles[player]
	if not isRunning() or not profile or closingProfiles[profile] or not profile:IsActive() then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = Transactions.Run(profile.Data, request, function(draft)
		-- Sample once after replay/revision admission. Preparation and action share one time,
		-- one detached draft, and one commit; a rejected action rolls preparation back too.
		local now = workspace:GetServerTimeNow()
		local prepared = preparations.ApplyToDraft(draft, now)
		if not prepared.ok then
			return prepared
		end
		return mutate(draft, now)
	end, function()
		return isRunning()
			and profiles[player] == profile
			and not closingProfiles[profile]
			and profile:IsActive()
	end)
	if result.code ~= "DataUnavailable" then
		publishChanges(player)
	end
	return result
end

-- For server-authored state transitions whose source already prevents duplicate events.
-- Retryable feature commands use Transact with their original revision-bound request ID.
function DataService.Update(
	player: Player,
	operation: string,
	mutate: ServerTypes.ProfileMutation
): Types.TransactionResult
	local data = DataService.GetLoadedData(player)
	if not data then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local revision = Transactions.GetRevision(data)
	return DataService.Transact(player, {
		id = `{revision}:{HttpService:GenerateGUID(false)}`,
		expectedRevision = revision,
		operation = operation,
		signature = "",
	}, mutate)
end

function DataService.Checkpoint(player: Player): Types.TransactionResult
	local profile = profiles[player]
	if not isRunning() or not profile or not profile:IsActive() or closingProfiles[profile] then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = settlements.Run(asSettlementProfile(profile), "Checkpoint", function()
		return isRunning() and profiles[player] == profile and not closingProfiles[profile]
	end)
	if result.code ~= "DataUnavailable" then
		publishChanges(player)
	end
	return result
end

function DataService.SaveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or not DataService.Checkpoint(player).ok then
		return false
	end
	-- Save schedules the vendor's asynchronous write; success is not durable acknowledgement.
	local ok, err = pcall(function()
		profile:Save()
	end)
	if not ok then
		log.error(`Manual save failed for userId {player.UserId}`, err)
	end
	return ok
end

function DataService.Stop()
	if stopping then
		return
	end
	-- Reject new admissions/public mutations first, but retain active profile listeners until
	-- their release settlement has run. Other feature services may already have stopped.
	stopping = true
	if requestState then
		RemoteUtil.ClearServerHandler(requestState)
	end
	stateRequestLimiter:Clear()
	for player in pairs(table.clone(profiles)) do
		DataService.Release(player)
	end
	lifecycle:Stop()
	table.clear(loading)
	table.clear(profiles)
	table.clear(releasing)
	table.clear(closingProfiles)
	table.clear(projections)
	table.clear(revisions)
	table.clear(profileTroves)
	startSession = nil
end

return DataService
