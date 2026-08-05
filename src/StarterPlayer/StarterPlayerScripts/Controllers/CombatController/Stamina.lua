-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/Stamina

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
type TroveInstance = typeof(Trove.new())

local Stamina = {}

local initialized = false
local running = false
local view: Types.StaminaView?
local lifecycleTrove: TroveInstance?
local characterTrove: TroveInstance?

local function update()
	if not running or not view then
		return
	end
	local player = Players.LocalPlayer
	local character = player.Character
	view.container.Visible = character ~= nil and character:GetAttribute("CombatReady") == true
	local stamina = player:GetAttribute("CombatStamina")
	local maximum = player:GetAttribute("MaxCombatStamina")
	if type(stamina) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
		view.fill.Size = UDim2.fromScale(1, 1)
		return
	end
	view.fill.Size = UDim2.fromScale(math.clamp(stamina / maximum, 0, 1), 1)
end

local function bindCharacter(character: Model)
	local currentCharacterTrove = characterTrove
	if not currentCharacterTrove then
		return
	end
	currentCharacterTrove:Clean()
	currentCharacterTrove:Connect(character:GetAttributeChangedSignal("CombatReady"), update)
	task.defer(update)
end

function Stamina.Init(_context: Types.ClientContext)
	initialized = true
end

function Stamina.BindView(newView: Types.StaminaView): () -> ()
	assert(initialized, "[CombatController.Stamina] Init must run before BindView")
	assert(view == nil or view == newView, "[CombatController.Stamina] A Stamina view is already bound")
	view = newView
	return function()
		if view == newView then
			view = nil
		end
	end
end

function Stamina.Start()
	assert(initialized, "[CombatController.Stamina] Init must run before Start")
	assert(view, "[CombatController.Stamina] Stamina view must be bound before Start")
	if running then
		return
	end
	running = true
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
	if not running then
		return
	end
	running = false
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
