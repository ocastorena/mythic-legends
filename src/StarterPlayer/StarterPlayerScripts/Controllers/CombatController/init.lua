--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController

local Input = require(script.Input)
local PresentationBus = require(script.PresentationBus)
local Stamina = require(script.Stamina)
local VFX = require(script.VFX)

local CombatController = {}
local isRunning = false
local generation = 0
local Types = require(script.Parent.Parent.Types)

function CombatController.BindView(view: Types.CombatActionView): () -> ()
	return Input.BindView(view)
end

function CombatController.BindStaminaView(view: Types.StaminaView): () -> ()
	return Stamina.BindView(view)
end

function CombatController.Init(context: Types.ClientContext)
	PresentationBus.Init(context)
	VFX.Init(context)
	Input.Init(context)
	Stamina.Init(context)
end

function CombatController.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	PresentationBus.Start()
	VFX.Start()
	if not isRunning or generation ~= currentGeneration then
		return
	end
	Input.Start()
	if not isRunning or generation ~= currentGeneration then
		return
	end
	Stamina.Start()
end

function CombatController.Stop()
	isRunning = false
	generation += 1
	Stamina.Stop()
	Input.Stop()
	VFX.Stop()
	PresentationBus.Stop()
end

return CombatController
