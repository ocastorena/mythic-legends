-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController

local Input = require(script.Input)
local PresentationBus = require(script.PresentationBus)
local VFX = require(script.VFX)

local CombatController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

function CombatController.Init(context: Types.ClientContext)
	PresentationBus.Init(context)
	VFX.Init(context)
	Input.Init(context)
end

function CombatController.Start()
	PresentationBus.Start()
	VFX.Start()
	Input.Start()
end

function CombatController.Stop()
	Input.Stop()
	VFX.Stop()
	PresentationBus.Stop()
end

return CombatController
