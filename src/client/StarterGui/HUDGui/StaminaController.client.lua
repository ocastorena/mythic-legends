-- Arena-only Stamina meter. The server replicates authoritative values as attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThemeUtil = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Ui"):WaitForChild("ThemeUtil"))

local player = Players.LocalPlayer
local screenGui = script.Parent
local HOTBAR_WIDTH = 6 * ThemeUtil.Metric.hotbarSlot + 5 * ThemeUtil.Metric.hotbarGap

local container = Instance.new("Frame")
container.Name = "StaminaMeter"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -68)
container.Size = UDim2.fromOffset(HOTBAR_WIDTH, 8)
container.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
container.BackgroundTransparency = 0.75
container.BorderSizePixel = 0
container.ClipsDescendants = true
container.Visible = false
container.Parent = screenGui
ThemeUtil.corner(container, 4)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(0, 255, 90)
fill.BorderSizePixel = 0
fill.Parent = container
ThemeUtil.corner(fill, 4)

local combatReadyConnection: RBXScriptConnection? = nil

local function update()
	local character = player.Character
	container.Visible = character ~= nil and character:GetAttribute("CombatReady") == true
	local stamina = player:GetAttribute("CombatStamina")
	local maximum = player:GetAttribute("MaxCombatStamina")
	if type(stamina) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
		fill.Size = UDim2.fromScale(1, 1)
		return
	end
	fill.Size = UDim2.fromScale(math.clamp(stamina / maximum, 0, 1), 1)
end

local function bindCharacter(character: Model)
	if combatReadyConnection then
		combatReadyConnection:Disconnect()
	end
	combatReadyConnection = character:GetAttributeChangedSignal("CombatReady"):Connect(update)
	task.defer(update)
end

player:GetAttributeChangedSignal("CombatStamina"):Connect(update)
player:GetAttributeChangedSignal("MaxCombatStamina"):Connect(update)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
update()
