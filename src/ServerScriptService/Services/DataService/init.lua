-- ServerScriptService/Services/DataService

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local RateLimitUtil = require(Infrastructure:WaitForChild("RateLimitUtil"))
local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))
local PlayerDataTemplate = require(ServerStorage:WaitForChild("Databases"):WaitForChild("PlayerDataTemplate"))

local log = LogUtil.For("DataService")

local STORE_NAME = "MythicLegends_PlayerData_v1"
local PROFILE_KEY_PREFIX = "Player_"
local CLIENT_STATE_KEYS = {
	"currency",
	"materials",
	"consumables",
	"equipment",
	"combatLoadout",
	"mythlings",
	"base",
}

export type PlayerData = typeof(PlayerDataTemplate)
export type StatePacket = {
	revision: number,
	values: { [string]: any },
	removed: { string }?,
	full: boolean?,
}

local liveStore = ProfileStore.New(STORE_NAME, PlayerDataTemplate)
local playerStore = if RunService:IsStudio() then liveStore.Mock else liveStore

local DataService = {}

local profiles: { [Player]: any } = {}
local loading: { [Player]: boolean } = {}
local releasing: { [Player]: any } = {}
local revisions: { [Player]: number } = {}
local projections: { [Player]: { [string]: any } } = {}
local loadedBindable = Instance.new("BindableEvent")
local releasedBindable = Instance.new("BindableEvent")

DataService.OnLoaded = loadedBindable.Event
DataService.OnReleased = releasedBindable.Event

local updateState: RemoteEvent?
local requestState: RemoteFunction?
local stateRequestLimiter = RateLimitUtil.new(6, 1)

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
	local projection = {}
	for _, key in ipairs(CLIENT_STATE_KEYS) do
		local value = data[key]
		if value ~= nil then
			projection[key] = deepClone(value)
		end
	end
	return projection
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

function DataService.Init(context: any)
	updateState = context.Remotes.State.Update
	requestState = context.Remotes.State.Request
end

function DataService.Start()
	if requestState then
		requestState.OnServerInvoke = function(player: Player)
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
	local existing = profiles[player]
	if existing and existing:IsActive() then
		return true
	end

	if loading[player] then
		repeat
			task.wait()
		until not loading[player] or player.Parent ~= Players
		local loaded = profiles[player]
		return loaded ~= nil and loaded:IsActive()
	end

	if player.Parent ~= Players then
		return false
	end

	loading[player] = true
	local ok, result = pcall(function()
		return playerStore:StartSessionAsync(PROFILE_KEY_PREFIX .. player.UserId, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end)
	loading[player] = nil

	if not ok then
		log.error(`Profile load threw for userId {player.UserId}`, result)
		if player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return false
	end

	local profile = result
	if not profile then
		if player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return false
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		local endedIntentionally = releasing[player] == profile
		releasing[player] = nil
		profiles[player] = nil
		projections[player] = nil
		revisions[player] = nil
		releasedBindable:Fire(player)
		if not endedIntentionally and player.Parent == Players then
			player:Kick("Your data session ended on another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players or not profile:IsActive() then
		profile:EndSession()
		return false
	end

	profiles[player] = profile
	revisions[player] = 0
	local playerData = profile.Data :: PlayerData
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

function DataService.GetSection(player: Player, sectionName: string): { [any]: any }
	assert(sectionName ~= "", "[DataService.GetSection] sectionName must not be empty")
	assert(DataService.Load(player), "[DataService.GetSection] player profile is unavailable")
	local profile = profiles[player]
	assert(profile and profile:IsActive(), "[DataService.GetSection] profile session is inactive")
	local section = profile.Data[sectionName]
	if type(section) ~= "table" then
		section = {}
		profile.Data[sectionName] = section
		publishChanges(player)
	end
	return section
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
	if requestState then
		requestState.OnServerInvoke = nil
	end
	stateRequestLimiter:Clear()
	if ProfileStore.IsClosing then
		return
	end
	for player in pairs(profiles) do
		DataService.Release(player)
	end
end

return DataService
