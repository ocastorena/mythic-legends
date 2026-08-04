-- StarterPlayer/StarterPlayerScripts/Controllers/StandPromptController

local StandPromptController = {}
local connection: RBXScriptConnection?

function StandPromptController.Init(_context: unknown)
end

function StandPromptController.Start()
-- Enables local player's stand prompts only for local player

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local TAG = "StandPrompt"

local function enablePrompt(prompt: ProximityPrompt)
	if prompt:GetAttribute("OwnerId") == LocalPlayer.UserId then
		prompt.Enabled = true
	end
end

connection = CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	if inst:IsA("ProximityPrompt") then enablePrompt(inst) end
end)
end

function StandPromptController.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return StandPromptController
