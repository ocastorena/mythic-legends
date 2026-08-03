-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/EnvironmentController

local Quality = require(script.Quality)
local Motion = require(script.Motion)
local Audio = require(script.Audio)

local EnvironmentController = {}

function EnvironmentController.Init(context: any)
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
