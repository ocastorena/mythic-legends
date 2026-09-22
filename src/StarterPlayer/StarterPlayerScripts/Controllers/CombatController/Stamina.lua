--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/Stamina

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(script.Parent.Parent.Parent.Types)
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
type TroveInstance = Trove.Trove

local Stamina = {}

local isInitialized = false
local isRunning = false
local view: Types.StaminaView?
local lifecycleTrove: TroveInstance?
local characterTrove: TroveInstance?

local function update()
	local currentView = view
	if not isRunning or not currentView then
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	currentView.container.Visible = character ~= nil
		and character:GetAttribute("CombatReady") == true
	local stamina = player:GetAttribute("CombatStamina")
	local maximum = player:GetAttribute("MaxCombatStamina")
	if type(stamina) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
		currentView.fill.Size = UDim2.fromScale(1, 1)
		return
	end
	currentView.fill.Size = UDim2.fromScale(math.clamp(stamina / maximum, 0, 1), 1)
end

local function bindCharacter(character: Model)
	local currentCharacterTrove = characterTrove
	if not currentCharacterTrove then
		return
	end
	currentCharacterTrove:Clean()
	currentCharacterTrove:Connect(character:GetAttributeChangedSignal("CombatReady"), update)
	currentCharacterTrove:Add(task.defer(update))
end

function Stamina.Init(_context: Types.ClientContext)
	isInitialized = true
end

function Stamina.BindView(newView: Types.StaminaView): () -> ()
	assert(isInitialized, "[CombatController.Stamina] Init must run before BindView")
	assert(
		view == nil or view == newView,
		"[CombatController.Stamina] A Stamina view is already bound"
	)
	view = newView
	return function()
		if view == newView then
			view = nil
		end
	end
end

function Stamina.Start()
	assert(isInitialized, "[CombatController.Stamina] Init must run before Start")
	assert(view, "[CombatController.Stamina] Stamina view must be bound before Start")
	if isRunning then
		return
	end
	isRunning = true
	local player = Players.LocalPlayer
	local trove = Trove.new()
	lifecycleTrove = trove
	characterTrove = trove:Extend()
	trove:Connect(player:GetAttributeChangedSignal("CombatStamina"), update)
	trove:Connect(player:GetAttributeChangedSignal("MaxCombatStamina"), update)
	trove:Connect(player.CharacterAdded, bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
	update()
end

function Stamina.Stop()
	if not isRunning then
		return
	end
	isRunning = false
	if lifecycleTrove then
		lifecycleTrove:Destroy()
		lifecycleTrove = nil
		characterTrove = nil
	end
	if view then
		view.container.Visible = false
	end
end

return Stamina
