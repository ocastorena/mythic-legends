--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/EnvironmentController

local Quality = require(script.Quality)
local Motion = require(script.Motion)
local Audio = require(script.Audio)

local EnvironmentController = {}
local isRunning = false
local generation = 0

local Types = require(script.Parent.Parent.Types)

function EnvironmentController.Init(context: Types.ClientContext)
	Quality.Init(context)
	Motion.Init(context)
	Audio.Init(context)
end

function EnvironmentController.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	Quality.Start()
	if not isRunning or generation ~= currentGeneration then
		return
	end
	Motion.Start()
	if not isRunning or generation ~= currentGeneration then
		return
	end
	Audio.Start()
end

function EnvironmentController.Stop()
	isRunning = false
	generation += 1
	Audio.Stop()
	Motion.Stop()
	Quality.Stop()
end

return EnvironmentController
