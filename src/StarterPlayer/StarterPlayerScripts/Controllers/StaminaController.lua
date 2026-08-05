-- StarterPlayer/StarterPlayerScripts/Controllers/StaminaController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local StaminaController = {}

local initialized = false
local running = false
local view: Types.StaminaView?
local connections: { RBXScriptConnection } = {}
local combatReadyConnection: RBXScriptConnection?

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
	if combatReadyConnection then
		combatReadyConnection:Disconnect()
	end
	combatReadyConnection = character:GetAttributeChangedSignal("CombatReady"):Connect(update)
	task.defer(update)
end

function StaminaController.Init(_context: Types.ClientContext)
	initialized = true
end

function StaminaController.BindView(newView: Types.StaminaView): () -> ()
	assert(initialized, "[StaminaController] Init must run before BindView")
	assert(view == nil or view == newView, "[StaminaController] A Stamina view is already bound")
	view = newView
	return function()
		if view == newView then
			view = nil
		end
	end
end

function StaminaController.Start()
	assert(initialized, "[StaminaController] Init must run before Start")
	assert(view, "[StaminaController] Stamina view must be bound before Start")
	if running then
		return
	end
	running = true
	local player = Players.LocalPlayer
	table.insert(connections, player:GetAttributeChangedSignal("CombatStamina"):Connect(update))
	table.insert(connections, player:GetAttributeChangedSignal("MaxCombatStamina"):Connect(update))
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))
	if player.Character then
		bindCharacter(player.Character)
	end
	update()
end

function StaminaController.Stop()
	if not running then
		return
	end
	running = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if combatReadyConnection then
		combatReadyConnection:Disconnect()
		combatReadyConnection = nil
	end
	if view then
		view.container.Visible = false
	end
end

return StaminaController
