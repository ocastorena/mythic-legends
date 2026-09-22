--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/StandController

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Parent.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)

local StandController = {}

local isInitialized = false
local isRunning = false
local lifetime = Trove.new()
local hasStopped = false
local generation = 0
local promptStates: { [ProximityPrompt]: boolean } = {}
local standRequested: BindableEvent
local getStatus: RemoteFunction
local collect: RemoteFunction
local placeMythling: RemoteFunction
local removeMythling: RemoteFunction
local TAG = "StandPrompt"

local function enableOwnedPrompt(instance: Instance)
	if
		instance:IsA("ProximityPrompt")
		and instance:GetAttribute("OwnerId") == Players.LocalPlayer.UserId
	then
		if promptStates[instance] == nil then
			promptStates[instance] = instance.Enabled
		end
		instance.Enabled = true
	end
end

local function releasePrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local wasEnabled = promptStates[instance]
	if wasEnabled == nil then
		return
	end
	promptStates[instance] = nil
	if instance.Enabled then
		instance.Enabled = wasEnabled
	end
end

local function validStandId(value: unknown): boolean
	return type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 128
end

local function validMythlingId(value: unknown): boolean
	return type(value) == "string" and value ~= "" and #value <= 128
end

local function invokeAction(remote: RemoteFunction, payload: unknown, actionName: string): boolean
	local requestGeneration = generation
	local ok, response = pcall(remote.InvokeServer, remote, payload)
	if hasStopped or requestGeneration ~= generation then
		return false
	end
	if not ok then
		warn(`[StandController] {actionName} request failed`)
		return false
	end
	return type(response) == "table" and response.ok == true
end

function StandController.Init(_context: Types.ClientContext)
	if isInitialized then
		return
	end
	isInitialized = true
	standRequested = Instance.new("BindableEvent")
	StandController.OnStandRequested = standRequested.Event

	local network = ReplicatedStorage:WaitForChild("Network")
	local production = network:WaitForChild("Production")
	local base = network:WaitForChild("Base")
	getStatus = production:WaitForChild("GetStatus") :: RemoteFunction
	collect = production:WaitForChild("Collect") :: RemoteFunction
	placeMythling = base:WaitForChild("PlaceMythling") :: RemoteFunction
	removeMythling = base:WaitForChild("RemoveMythling") :: RemoteFunction
end

function StandController.Start()
	assert(isInitialized, "[StandController] Init must run before Start")
	assert(not hasStopped, "[StandController] Stop ends this controller's signal lifetime")
	if isRunning then
		return
	end
	isRunning = true
	for _, instance in CollectionService:GetTagged(TAG) do
		enableOwnedPrompt(instance)
	end
	lifetime:Connect(CollectionService:GetInstanceAddedSignal(TAG), enableOwnedPrompt)
	lifetime:Connect(CollectionService:GetInstanceRemovedSignal(TAG), releasePrompt)

	lifetime:Connect(ProximityPromptService.PromptTriggered, function(prompt: ProximityPrompt)
		if not CollectionService:HasTag(prompt, TAG) then
			return
		end
		local ownerId = prompt:GetAttribute("OwnerId")
		if type(ownerId) == "number" and ownerId ~= Players.LocalPlayer.UserId then
			return
		end
		local parent = prompt.Parent
		local stand = parent and parent.Parent
		local standId = stand and stand:GetAttribute("Id")
		if validStandId(standId) then
			standRequested:Fire(standId)
		end
	end)
end

function StandController.GetProductionStatus(standId: number): Types.ProductionStatus?
	assert(isInitialized, "[StandController] Init must run before GetProductionStatus")
	if not validStandId(standId) then
		return nil
	end
	local requestGeneration = generation
	local ok, response = pcall(getStatus.InvokeServer, getStatus, standId)
	if hasStopped or requestGeneration ~= generation then
		return nil
	end
	if not ok then
		warn("[StandController] Production status request failed")
		return nil
	end
	if type(response) ~= "table" or response.ok ~= true or type(response.value) ~= "table" then
		return nil
	end
	local value = response.value
	if
		type(value.production) ~= "number"
		or type(value.rate) ~= "number"
		or type(value.capacity) ~= "number"
		or type(value.progress) ~= "number"
		or type(value.materials) ~= "table"
		or type(value.active) ~= "boolean"
		or type(value.sampledAt) ~= "number"
	then
		return nil
	end
	return value
end

function StandController.Collect(standId: number): Types.ProductionCollection?
	assert(isInitialized, "[StandController] Init must run before Collect")
	if not validStandId(standId) then
		return nil
	end
	local requestGeneration = generation
	local ok, response = pcall(collect.InvokeServer, collect, standId)
	if hasStopped or requestGeneration ~= generation then
		return nil
	end
	if not ok then
		warn("[StandController] Collect request failed")
		return nil
	end
	if type(response) ~= "table" or response.ok ~= true or type(response.value) ~= "table" then
		return nil
	end
	local value = response.value
	if
		type(value.collected) ~= "number"
		or type(value.remaining) ~= "number"
		or type(value.materials) ~= "table"
	then
		return nil
	end
	return value
end

function StandController.Place(standId: number, mythlingId: string): boolean
	assert(isInitialized, "[StandController] Init must run before Place")
	if not validStandId(standId) or not validMythlingId(mythlingId) then
		return false
	end
	return invokeAction(placeMythling, { standId = standId, mythlingId = mythlingId }, "Place")
end

function StandController.Remove(standId: number, mythlingId: string): boolean
	assert(isInitialized, "[StandController] Init must run before Remove")
	if not validStandId(standId) or not validMythlingId(mythlingId) then
		return false
	end
	return invokeAction(removeMythling, { standId = standId, mythlingId = mythlingId }, "Remove")
end

function StandController.BindSession(props: Types.StandSessionProps): Types.StandSession
	assert(isInitialized and not hasStopped, "[StandController] A live controller is required")
	local sessionLifetime = lifetime:Extend()
	local requests = sessionLifetime:Extend()
	local selectedStand: number? = nil
	local sessionGeneration = 0
	local isDestroyed = false
	local isPending = false
	local isRequesting = false
	local isQueued = false
	local needsRefresh = false
	local function isCurrent(expected: number, standId: number): boolean
		return not isDestroyed and expected == sessionGeneration and selectedStand == standId
	end
	local function close()
		sessionGeneration += 1
		selectedStand = nil
		requests:Clean()
		isPending = false
		isRequesting = false
		isQueued = false
		needsRefresh = false
	end
	local function refresh()
		local standId = selectedStand
		if isDestroyed or standId == nil then
			return
		end
		if isPending or isRequesting then
			needsRefresh = true
			return
		end
		if isQueued then
			return
		end
		isQueued = true
		local expected = sessionGeneration
		requests:Add(task.defer(function()
			isQueued = false
			if not isCurrent(expected, standId) then
				return
			end
			isRequesting = true
			local status = StandController.GetProductionStatus(standId)
			if not isCurrent(expected, standId) then
				return
			end
			isRequesting = false
			props.onStatus(status)
			if needsRefresh then
				needsRefresh = false
				refresh()
			end
			requests:Pop(coroutine.running())
		end))
	end
	local function perform(action: (number, () -> boolean) -> ())
		local standId = selectedStand
		if isDestroyed or standId == nil or isPending then
			return
		end
		-- Replies started before a mutation cannot describe its new state.
		sessionGeneration += 1
		requests:Clean()
		isRequesting = false
		isQueued = false
		needsRefresh = false
		isPending = true
		props.onPending(true)
		local expected = sessionGeneration
		requests:Add(task.defer(function()
			local function current(): boolean
				return isCurrent(expected, standId)
			end
			if not current() then
				return
			end
			action(standId, current)
			if not current() then
				return
			end
			isPending = false
			props.onPending(false)
			refresh()
			requests:Pop(coroutine.running())
		end))
	end
	sessionLifetime:Add(function()
		isDestroyed = true
		sessionGeneration += 1
	end)
	return {
		Open = function(standId: number)
			if isDestroyed then
				return
			end
			close()
			selectedStand = standId
			props.onPending(false)
			refresh()
		end,
		Close = close,
		Refresh = refresh,
		Collect = function()
			perform(function(standId, current)
				local result = StandController.Collect(standId)
				if current() then
					props.onCollection(result)
				end
			end)
		end,
		Assign = function(selectedId: string, activeId: string?)
			perform(function(standId, current)
				if activeId then
					local removed = StandController.Remove(standId, activeId)
					if not current() or not removed then
						return
					end
					props.onAssigned(nil)
				end
				local placed = StandController.Place(standId, selectedId)
				if current() and placed then
					props.onAssigned(selectedId)
				end
			end)
		end,
		Remove = function(activeId: string)
			perform(function(standId, current)
				local removed = StandController.Remove(standId, activeId)
				if current() and removed then
					props.onAssigned(nil)
				end
			end)
		end,
		Destroy = function()
			if isDestroyed then
				return
			end
			close()
			isDestroyed = true
			lifetime:Remove(sessionLifetime)
		end,
	}
end

-- Stop is terminal: UI consumers hold the one signal created during Init.
function StandController.Stop()
	if hasStopped then
		return
	end
	hasStopped = true
	isRunning = false
	generation += 1
	lifetime:Destroy()
	for prompt in promptStates do
		releasePrompt(prompt)
	end
	table.clear(promptStates)
	if isInitialized then
		standRequested:Destroy()
	end
end

return StandController
