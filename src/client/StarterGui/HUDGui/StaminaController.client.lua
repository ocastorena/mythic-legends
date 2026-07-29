-- Arena-only Stamina meter. The server replicates the authoritative values as Player
-- attributes; this controller only presents them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaBounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaBounds"))
local ThemeUtil = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Ui"):WaitForChild("ThemeUtil"))

local player = Players.LocalPlayer
local screenGui = script.Parent

-- Keep the stamina indicator aligned with the fixed six-slot hotbar. The meter is a
-- quiet progress strip rather than another piece of HUD chrome, so it has no label,
-- padding, or outline competing with the item slots.
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
