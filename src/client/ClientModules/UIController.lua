-- StarterPlayer/StarterPlayerScripts/ClientModules/UIController

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalData = require(script.Parent:WaitForChild("LocalData"))

local UIController = {}

local MAX_SYNC_ATTEMPTS = 5
local updateConnection: RBXScriptConnection?
local syncing = false
local initialized = false
local updateState: RemoteEvent
local requestState: RemoteFunction

local function requestSnapshot()
	if syncing then
		return
	end
	syncing = true
	for attempt = 1, MAX_SYNC_ATTEMPTS do
		local ok, packet = pcall(function()
			return requestState:InvokeServer()
		end)
		if ok and type(packet) == "table" then
			packet.full = true
			local ingested = LocalData.IngestPayload(packet)
			if ingested then
				syncing = false
				return
			end
		end
		task.wait(math.min(0.25 * (2 ^ (attempt - 1)), 2))
	end
	syncing = false
	warn("[UIController] Could not synchronize private player state")
end

function UIController.Init()
	if initialized then
		return
	end
	initialized = true
	local network = ReplicatedStorage:WaitForChild("Network")
	updateState = network:WaitForChild("UpdateState") :: RemoteEvent
	requestState = network:WaitForChild("RequestState") :: RemoteFunction
	updateConnection = updateState.OnClientEvent:Connect(function(packet)
		local ok, reason = LocalData.IngestPayload(packet)
		if not ok and reason == "RevisionGap" then
			requestSnapshot()
		end
	end)
end

function UIController.Start()
	assert(initialized, "[UIController] Init must run before Start")
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

function UIController.Destroy()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
	initialized = false
end

return UIController
