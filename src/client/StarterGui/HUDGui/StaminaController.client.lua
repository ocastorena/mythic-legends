-- Arena-only Stamina meter. The server replicates the authoritative values as Player
-- attributes; this controller only presents them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaBounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaBounds"))
local ThemeUtil = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Ui"):WaitForChild("ThemeUtil"))

local player = Players.LocalPlayer
local screenGui = script.Parent

local container = Instance.new("Frame")
container.Name = "StaminaMeter"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -86)
container.Size = UDim2.fromOffset(224, 24)
container.BackgroundColor3 = ThemeUtil.Surface.panel.color
container.BackgroundTransparency = ThemeUtil.Surface.panel.transparency
container.BorderSizePixel = 0
container.Visible = false
container.Parent = screenGui
ThemeUtil.corner(container, ThemeUtil.Radius.pill)

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 4)
padding.PaddingBottom = UDim.new(0, 4)
padding.PaddingLeft = UDim.new(0, 5)
padding.PaddingRight = UDim.new(0, 5)
padding.Parent = container

local trough = Instance.new("Frame")
trough.Name = "Trough"
trough.Size = UDim2.fromScale(1, 1)
trough.BackgroundColor3 = ThemeUtil.Surface.trough.color
trough.BackgroundTransparency = ThemeUtil.Surface.trough.transparency
trough.BorderSizePixel = 0
trough.ClipsDescendants = true
trough.Parent = container
ThemeUtil.corner(trough, ThemeUtil.Radius.pill)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = ThemeUtil.Accent.cyan
fill.BorderSizePixel = 0
fill.Parent = trough
ThemeUtil.corner(fill, ThemeUtil.Radius.pill)

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.BorderSizePixel = 0
label.FontFace = ThemeUtil.Font.extraBold
label.Text = "STAMINA"
label.TextColor3 = ThemeUtil.Text.strong
label.TextSize = 11
label.TextStrokeColor3 = Color3.fromRGB(20, 20, 22)
label.TextStrokeTransparency = 0.45
label.ZIndex = fill.ZIndex + 1
label.Parent = trough

local cachedArena: BasePart? = nil
local function getArena(): BasePart?
	if cachedArena and cachedArena.Parent then
		return cachedArena
	end
	local map = workspace:FindFirstChild("Map")
	local arena = map and map:FindFirstChild("Arena")
	cachedArena = if arena and arena:IsA("BasePart") then arena else nil
	return cachedArena
end

local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inArena = root
		and root:IsA("BasePart")
		and ArenaBounds.Contains(getArena(), root.Position, 12)
	container.Visible = inArena == true

	local stamina = player:GetAttribute("CombatStamina")
	local maximum = player:GetAttribute("CombatMaxStamina")
	if type(stamina) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
		fill.Size = UDim2.fromScale(1, 1)
		return
	end

	fill.Size = UDim2.fromScale(math.clamp(stamina / maximum, 0, 1), 1)
	label.Text = string.format("STAMINA  %d", math.floor(stamina + 0.5))
end

player:GetAttributeChangedSignal("CombatStamina"):Connect(update)
player:GetAttributeChangedSignal("CombatMaxStamina"):Connect(update)
player.CharacterAdded:Connect(function()
	task.defer(update)
end)

task.spawn(function()
	while script.Parent do
		update()
		task.wait(0.1)
	end
end)

update()
