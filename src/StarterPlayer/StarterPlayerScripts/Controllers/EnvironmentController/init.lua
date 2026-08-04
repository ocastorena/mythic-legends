-- StarterPlayer/StarterPlayerScripts/Controllers/EnvironmentController

local Quality = require(script.Quality)
local Motion = require(script.Motion)
local Audio = require(script.Audio)

local EnvironmentController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

function EnvironmentController.Init(context: Types.ClientContext)
	Quality.Init(context)
	Motion.Init(context)
	Audio.Init(context)
end

function EnvironmentController.Start()
	Quality.Start()
	Motion.Start()
	Audio.Start()
end

function EnvironmentController.Stop()
	Audio.Stop()
	Motion.Stop()
	Quality.Stop()
end

return EnvironmentController
