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
local standRequested: BindableEvent
local getStatus: RemoteFunction
local collect: RemoteFunction
local placeMythling: RemoteFunction
local removeMythling: RemoteFunction

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

	promptConnection = ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if not CollectionService:HasTag(prompt, "StandPrompt") then
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

function StandController.GetProductionStatus(mythlingId: string): Types.ProductionStatus
	assert(initialized, "[StandController] Init must run before GetProductionStatus")
	if not validMythlingId(mythlingId) then
		return { production = 0, rate = 0, capacity = 0 }
	end
	local ok, response = pcall(getStatus.InvokeServer, getStatus, mythlingId)
	if not ok then
		warn("[StandController] Production status request failed")
		return { production = 0, rate = 0, capacity = 0 }
	end
	if type(response) ~= "table" or response.ok ~= true or type(response.value) ~= "table" then
		return { production = 0, rate = 0, capacity = 0 }
	end
	local value = response.value
	return {
		production = if type(value.production) == "number" then math.max(value.production, 0) else 0,
		rate = if type(value.rate) == "number" then math.max(value.rate, 0) else 0,
		capacity = if type(value.capacity) == "number" then math.max(value.capacity, 0) else 0,
	}
end

function StandController.Collect(mythlingId: string): boolean
	assert(initialized, "[StandController] Init must run before Collect")
	if not validMythlingId(mythlingId) then
		return false
	end
	return invokeAction(collect, mythlingId, "Collect")
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
end

return StandController
