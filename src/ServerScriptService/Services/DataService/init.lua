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

local profiles: { [Player]: Profile } = {}
local profileTroves: { [Profile]: Trove.Trove } = {}
local loading: { [Player]: boolean } = {}
local releasing: { [Player]: Profile } = {}
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

function DataService.Start()
	if not lifecycle:Start() then
		return
	end
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
	if not lifecycle:IsRunning() then
		return false
	end
	local existing = profiles[player]
	if existing and existing:IsActive() then
		return true
	end

	if loading[player] then
		repeat
			task.wait()
		until not loading[player] or player.Parent ~= Players or not lifecycle:IsRunning()
		local loaded = profiles[player]
		return lifecycle:IsRunning()
			and player.Parent == Players
			and loaded ~= nil
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
				return player.Parent ~= Players or not lifecycle:IsRunning()
			end,
		})
	end)
	loading[player] = nil

	if not ok then
		log.error(`Profile load threw for userId {player.UserId}`, result)
		if lifecycle:IsRunning() and player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return false
	end

	local profile = result
	if not profile then
		if lifecycle:IsRunning() and player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return false
	end
	if not lifecycle:IsRunning() or player.Parent ~= Players or not profile:IsActive() then
		profile:EndSession()
		return false
	end

	profile:AddUserId(player.UserId)
	-- Forward-only MVP additions run before reconciliation and before any consumer sees the data.
	local prepared, schemaError = ProfileSchema.Prepare(profile.Data, function()
		return HttpService:GenerateGUID(false)
	end)
	if not prepared then
		log.error(`Profile schema preparation failed for userId {player.UserId}`, schemaError)
		profile:EndSession()
		if lifecycle:IsRunning() and player.Parent == Players then
			player:Kick("Your data could not be updated safely. Please rejoin.")
		end
		return false
	end
	profile:Reconcile()
	local profileTrove = lifecycle.trove:Extend()
	profileTroves[profile] = profileTrove
	local endedConnection = profile.OnSessionEnd:Connect(function()
		local endedIntentionally = releasing[player] == profile
		releasing[player] = nil
		profiles[player] = nil
		projections[player] = nil
		revisions[player] = nil
		if lifecycle:IsRunning() then
			releasedBindable:Fire(player)
		end
		if lifecycle:IsRunning() and not endedIntentionally and player.Parent == Players then
			player:Kick("Your data session ended on another server. Please rejoin.")
		end
		profileTroves[profile] = nil
		lifecycle.trove:Remove(profileTrove)
	end)
	profileTrove:Add(function()
		endedConnection:Disconnect()
	end)

	if not lifecycle:IsRunning() or player.Parent ~= Players or not profile:IsActive() then
		profile:EndSession()
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
end

function DataService.Release(player: Player)
	loading[player] = nil
	stateRequestLimiter:Forget(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	releasing[player] = profile
	profiles[player] = nil
	if profile:IsActive() then
		profile:EndSession()
	end
	projections[player] = nil
	revisions[player] = nil
end

function DataService.GetLoadedData(player: Player): PlayerData?
	local profile = profiles[player]
	return if lifecycle:IsRunning() and profile and profile:IsActive() then profile.Data else nil
end

function DataService.GetData(player: Player): PlayerData
	assert(DataService.Load(player), "[DataService] Player profile is unavailable")
	local data = DataService.GetLoadedData(player)
	assert(data, "[DataService] Player profile is inactive")
	return data
end

function DataService.MarkDirty(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	Transactions.Invalidate(profile.Data)
	publishChanges(player)
	return true
end

function DataService.Transact(
	player: Player,
	request: Types.TransactionRequest,
	mutate: Transactions.Mutator
): Types.TransactionResult
	local profile = profiles[player]
	if not lifecycle:IsRunning() or not profile or not profile:IsActive() then
		return { ok = false, code = "DataUnavailable", revision = 0 }
	end
	local result = Transactions.Run(profile.Data, request, mutate, function()
		return lifecycle:IsRunning() and profiles[player] == profile and profile:IsActive()
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
	mutate: Transactions.Mutator
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

function DataService.SaveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	publishChanges(player)
	local ok, err = pcall(function()
		profile:Save()
	end)
	if not ok then
		log.error(`Manual save failed for userId {player.UserId}`, err)
	end
	return ok
end

function DataService.Stop()
	if not lifecycle:Stop() then
		return
	end
	table.clear(loading)
	if requestState then
		RemoteUtil.ClearServerHandler(requestState)
	end
	stateRequestLimiter:Clear()
	if ProfileStore.IsClosing then
		table.clear(profiles)
		table.clear(releasing)
		table.clear(projections)
		table.clear(revisions)
		table.clear(profileTroves)
		return
	end
	for player in pairs(profiles) do
		DataService.Release(player)
	end
	table.clear(releasing)
	table.clear(profileTroves)
	startSession = nil
end

return DataService
