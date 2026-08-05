-- StarterPlayer/StarterPlayerScripts/Controllers/UIController

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local LocalData = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("LocalData"))
local App = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("App"))
local InventoryController = require(script.Parent:WaitForChild("InventoryController"))

local UIController = {}

local INITIAL_WARNING_ATTEMPT = 5
local MAX_RETRY_DELAY_SECONDS = 5
local updateConnection: RBXScriptConnection?
local syncing = false
local running = false
local syncGeneration = 0
local initialized = false
local context: Types.ClientContext?
local uiScope: any
local updateState: RemoteEvent
local requestState: RemoteFunction

local function synchronize(generation: number)
	local attempt = 0
	while running and generation == syncGeneration do
		attempt += 1
		local ok, packet = pcall(function()
			return requestState:InvokeServer()
		end)
		if not running or generation ~= syncGeneration then
			break
		end
		if ok and type(packet) == "table" then
			packet.full = true
			local ingested = LocalData.IngestPayload(packet)
			if ingested then
				syncing = false
				return
			end
		end
		if attempt == INITIAL_WARNING_ATTEMPT then
			warn("[UIController] Private player state is not ready; synchronization will continue")
		end
		task.wait(math.min(0.25 * (2 ^ math.min(attempt - 1, 5)), MAX_RETRY_DELAY_SECONDS))
	end
	if generation == syncGeneration then
		syncing = false
	end
end

local function requestSnapshot()
	if not running or syncing then
		return
	end
	syncing = true
	syncGeneration += 1
	task.spawn(synchronize, syncGeneration)
end

function UIController.Init(clientContext: Types.ClientContext)
	if initialized then
		return
	end
	initialized = true
	context = clientContext
	local stateNetwork = ReplicatedStorage:WaitForChild("Network"):WaitForChild("State")
	updateState = stateNetwork:WaitForChild("Update") :: RemoteEvent
	requestState = stateNetwork:WaitForChild("Request") :: RemoteFunction
end

function UIController.Start()
	assert(initialized, "[UIController] Init must run before Start")
	if updateConnection then
		return
	end
	running = true
	if not uiScope then
		uiScope = Fusion.scoped(Fusion)
		App(uiScope, {
			localData = (context :: Types.ClientContext).LocalData,
			inventoryController = InventoryController,
		})
	end
	updateConnection = updateState.OnClientEvent:Connect(function(packet)
		local ok, reason = LocalData.IngestPayload(packet)
		if not ok and reason == "RevisionGap" then
			requestSnapshot()
		end
	end)
	requestSnapshot()
end

-- Feature controllers register focused mappings here. The shared router filters the state
-- signal; it does not own feature-specific visual rules.
function UIController.Register(key: string, handler: (any, any) -> ()): RBXScriptConnection
	local connection = LocalData.OnStateChanged:Connect(function(changedKey, value, oldValue)
		if changedKey == key then
			handler(value, oldValue)
		end
	end)
	local current = LocalData.Peek(key)
	if current ~= nil then
		task.defer(handler, current, nil)
	end
	return connection
end

function UIController.Stop()
	running = false
	syncGeneration += 1
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	syncing = false
	if uiScope then
		Fusion.doCleanup(uiScope)
		uiScope = nil
	end
end

return UIController
