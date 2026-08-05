-- StarterPlayer/StarterPlayerScripts/Controllers/StandPromptController

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local StandPromptController = {}

local TAG = "StandPrompt"
local initialized = false
local running = false
local addedConnection: RBXScriptConnection?

local function enableOwnedPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("OwnerId") == Players.LocalPlayer.UserId then
		instance.Enabled = true
	end
end

function StandPromptController.Init(_context: unknown)
	initialized = true
end

function StandPromptController.Start()
	assert(initialized, "[StandPromptController] Init must run before Start")
	if running then
		return
	end
	running = true

	for _, instance in CollectionService:GetTagged(TAG) do
		enableOwnedPrompt(instance)
	end
	addedConnection = CollectionService:GetInstanceAddedSignal(TAG):Connect(enableOwnedPrompt)
end

function StandPromptController.Stop()
	running = false
	if addedConnection then
		addedConnection:Disconnect()
		addedConnection = nil
	end
end

return StandPromptController
