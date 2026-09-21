-- StarterPlayer/StarterPlayerScripts/Controllers/StandController

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local StandController = {}

local initialized = false
local running = false
local promptConnection: RBXScriptConnection?
local promptAddedConnection: RBXScriptConnection?
local standRequested: BindableEvent
local getStatus: RemoteFunction
local collect: RemoteFunction
local placeMythling: RemoteFunction
local removeMythling: RemoteFunction
local TAG = "StandPrompt"

local function enableOwnedPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("OwnerId") == Players.LocalPlayer.UserId then
		instance.Enabled = true
	end
end

local function validStandId(value: unknown): boolean
	return type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 128
end

local function validMythlingId(value: unknown): boolean
	return type(value) == "string" and value ~= "" and #value <= 128
end

local function invokeAction(remote: RemoteFunction, payload: unknown, actionName: string): boolean
	local ok, response = pcall(remote.InvokeServer, remote, payload)
	if not ok then
		warn(`[StandController] {actionName} request failed`)
		return false
	end
	return type(response) == "table" and response.ok == true
end

function StandController.Init(_context: Types.ClientContext)
	if initialized then
		return
	end
	initialized = true
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
	assert(initialized, "[StandController] Init must run before Start")
	if running then
		return
	end
	running = true
	for _, instance in CollectionService:GetTagged(TAG) do
		enableOwnedPrompt(instance)
	end
	promptAddedConnection = CollectionService:GetInstanceAddedSignal(TAG):Connect(enableOwnedPrompt)

	promptConnection = ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
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
	assert(initialized, "[StandController] Init must run before GetProductionStatus")
	if not validStandId(standId) then
		return nil
	end
	local ok, response = pcall(getStatus.InvokeServer, getStatus, standId)
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
	assert(initialized, "[StandController] Init must run before Collect")
	if not validStandId(standId) then
		return nil
	end
	local ok, response = pcall(collect.InvokeServer, collect, standId)
	if not ok then
		warn("[StandController] Collect request failed")
		return nil
	end
	if type(response) ~= "table" or response.ok ~= true or type(response.value) ~= "table" then
		return nil
	end
	local value = response.value
	if type(value.collected) ~= "number" or type(value.remaining) ~= "number" or type(value.materials) ~= "table" then
		return nil
	end
	return value
end

function StandController.Place(standId: number, mythlingId: string): boolean
	assert(initialized, "[StandController] Init must run before Place")
	if not validStandId(standId) or not validMythlingId(mythlingId) then
		return false
	end
	return invokeAction(placeMythling, { standId = standId, mythlingId = mythlingId }, "Place")
end

function StandController.Remove(standId: number, mythlingId: string): boolean
	assert(initialized, "[StandController] Init must run before Remove")
	if not validStandId(standId) or not validMythlingId(mythlingId) then
		return false
	end
	return invokeAction(removeMythling, { standId = standId, mythlingId = mythlingId }, "Remove")
end

function StandController.Stop()
	running = false
	if promptConnection then
		promptConnection:Disconnect()
		promptConnection = nil
	end
	if promptAddedConnection then
		promptAddedConnection:Disconnect()
		promptAddedConnection = nil
	end
end

return StandController
