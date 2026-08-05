-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController

local Input = require(script.Input)
local PresentationBus = require(script.PresentationBus)
local Stamina = require(script.Stamina)
local VFX = require(script.VFX)

local CombatController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

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
	PresentationBus.Start()
	VFX.Start()
	Input.Start()
	Stamina.Start()
end

function CombatController.Stop()
	Stamina.Stop()
	Input.Stop()
	VFX.Stop()
	PresentationBus.Stop()
end

return CombatController
