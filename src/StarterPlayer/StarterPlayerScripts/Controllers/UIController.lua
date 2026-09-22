--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/UIController

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Trove = require(ReplicatedStorage.Packages.Trove)
local Types = require(script.Parent.Parent.Types)
local LocalData = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("LocalData"))
local App = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("App"))
local InventoryController = require(script.Parent:WaitForChild("InventoryController"))
local StandController = require(script.Parent:WaitForChild("StandController"))
local HotbarController = require(script.Parent:WaitForChild("HotbarController"))
local CombatController = require(script.Parent:WaitForChild("CombatController"))

local UIController = {}

local INITIAL_WARNING_ATTEMPT = 5
local MAX_RETRY_DELAY_SECONDS = 5
local lifetime = Trove.new()
local isSyncing = false
local hasStopped = false
local isRunning = false
local syncGeneration = 0
local isInitialized = false
local context: Types.ClientContext?
local uiScope: Fusion.Scope<typeof(Fusion)>?
local updateState: RemoteEvent
local requestState: RemoteFunction

local function synchronize(generation: number)
	local attempt = 0
	while isRunning and generation == syncGeneration do
		attempt += 1
		local ok, packet = pcall(function()
			return requestState:InvokeServer()
		end)
		if not isRunning or generation ~= syncGeneration then
			break
		end
		if ok and type(packet) == "table" then
			packet.full = true
			local ingested = LocalData.IngestPayload(packet)
			if ingested then
				isSyncing = false
				return
			end
		end
		if attempt == INITIAL_WARNING_ATTEMPT then
			warn("[UIController] Private player state is not ready; synchronization will continue")
		end
		task.wait(math.min(0.25 * (2 ^ math.min(attempt - 1, 5)), MAX_RETRY_DELAY_SECONDS))
	end
	if generation == syncGeneration then
		isSyncing = false
	end
end

local function requestSnapshot()
	if not isRunning or isSyncing then
		return
	end
	isSyncing = true
	syncGeneration += 1
	local generation = syncGeneration
	lifetime:Add(task.defer(function()
		synchronize(generation)
		lifetime:Pop(coroutine.running())
	end))
end

function UIController.Init(clientContext: Types.ClientContext)
	if isInitialized then
		return
	end
	isInitialized = true
	context = clientContext
	local stateNetwork = ReplicatedStorage:WaitForChild("Network"):WaitForChild("State")
	updateState = stateNetwork:WaitForChild("Update") :: RemoteEvent
	requestState = stateNetwork:WaitForChild("Request") :: RemoteFunction
end

function UIController.Start()
	assert(isInitialized, "[UIController] Init must run before Start")
	assert(not hasStopped, "[UIController] Stop ends the application lifetime")
	if isRunning then
		return
	end
	isRunning = true
	if not uiScope then
		local scope = Fusion.scoped(Fusion)
		uiScope = scope
		App(scope, {
			localData = (context :: Types.ClientContext).LocalData,
			inventoryController = InventoryController,
			standController = StandController,
			hotbarController = HotbarController,
			combatController = CombatController,
		})
	end
	lifetime:Connect(updateState.OnClientEvent, function(packet)
		local ok, reason = LocalData.IngestPayload(packet)
		if not ok and reason == "RevisionGap" then
			requestSnapshot()
		end
	end)
	requestSnapshot()
end

function UIController.Stop()
	if hasStopped then
		return
	end
	hasStopped = true
	isRunning = false
	syncGeneration += 1
	lifetime:Destroy()
	isSyncing = false
	if uiScope then
		Fusion.doCleanup(uiScope)
		uiScope = nil
	end
end

return UIController
