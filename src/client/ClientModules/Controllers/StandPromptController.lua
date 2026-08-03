-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/StandPromptController

local StandPromptController = {}

function StandPromptController.Start(_context: any)
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

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	if inst:IsA("ProximityPrompt") then enablePrompt(inst) end
end)
end

function StandPromptController.Destroy()
end

return StandPromptController
