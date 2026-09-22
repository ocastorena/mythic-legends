--!strict
-- ServerScriptService/Services/DataService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local ServerStorage = game:GetService("ServerStorage")

local infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(infrastructure:WaitForChild("LogUtil"))
local RateLimiter = require(infrastructure:WaitForChild("RateLimiter"))
local ProfileStore =
	require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))
local PlayerDataTemplate =
	require(ServerStorage:WaitForChild("Databases"):WaitForChild("PlayerDataTemplate"))
local Migrations = require(script.Migrations)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Domain.Types)
local ServiceLifecycle = require(ServerScriptService.Infrastructure.ServiceLifecycle)
local Trove = require(ReplicatedStorage.Packages.Trove)
local lifecycle = ServiceLifecycle.new("DataService")

local log = LogUtil.For("DataService")

local STORE_NAME = "MythicLegends_PlayerData_v2"
local PROFILE_KEY_PREFIX = "Player_"

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
local MythlingsData: { [string]: Types.MythlingDef }

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

local function buildProjection(data: PlayerData): { [string]: any }
	-- Explicit allowlist: no dynamic indexing into the complete player document.
	return deepClone({
		currency = data.currency,
		materials = data.materials,
		consumables = data.consumables,
		equipment = data.equipment,
		combatLoadout = data.combatLoadout,
		mythlings = data.mythlings,
		base = data.base,
	})
end

local function makeSnapshot(player: Player): StatePacket?
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return nil
	end
	local projection = buildProjection(profile.Data)
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
	local current = buildProjection(profile.Data)
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
	MythlingsData = serviceContext.Configurations.Mythlings
end

function DataService.Start()
	if not lifecycle:Start() then
		return
	end
	-- The vendor's recursive JSONAcceptable intersection cannot infer this valid nested template.
	-- Isolate that constructor adaptation; all loaded documents retain their canonical type.
	local liveStore: ProfileStore.ProfileStore<PlayerData> =
		ProfileStore.New(STORE_NAME, PlayerDataTemplate :: any)
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
		return loadSession(PROFILE_KEY_PREFIX .. player.UserId, {
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
	local migrationOk, migrated, migrationError =
		pcall(Migrations.Apply, profile.Data, MythlingsData, os.time())
	if not migrationOk or not migrated then
		log.error(`Profile migration failed for userId {player.UserId}`, migrationError or migrated)
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
	publishChanges(player)
	return true
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
