-- StarterGui/HotbarGui/CombatActionController
-- Dedicated mobile Combat Loadout actions. These sit around Roblox's own Jump button,
-- match its dark circular treatment, and display the actual equipped Tool model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = ReplicatedStorage:WaitForChild("Client")
local Ui = Client:WaitForChild("Ui")
local ArenaBounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaBounds"))
local CharacterUtil = require(Client:WaitForChild("Character"):WaitForChild("CharacterUtil"))
local ModalUtil = require(Ui:WaitForChild("ModalUtil"))
local ThemeUtil = require(Ui:WaitForChild("ThemeUtil"))
local WeaponPreviewUtil = require(Ui:WaitForChild("WeaponPreviewUtil"))
local WeaponsMeta = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Weapons"))

local localPlayer = Players.LocalPlayer
local screenGui = script.Parent

local NORMAL_BUTTON_COLOR = Color3.fromRGB(60, 60, 64)
local PRESSED_BUTTON_COLOR = Color3.fromRGB(48, 48, 52)
local FALLBACK_JUMP_SIZE = 70
local ACTION_SCALE = 0.8
local MIN_ACTION_SIZE = 52
local MAX_ACTION_SIZE = 68
local JUMP_GAP = 10
local CLUSTER_INSET = 18

type ActionButton = {
	button: ImageButton,
	icon: ImageLabel,
	fallback: TextLabel,
	combatKind: string,
	tool: Tool?,
}

local root = Instance.new("Frame")
root.Name = "CombatActions"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Visible = false
root.Parent = screenGui

local function createAction(name: string, combatKind: string, fallbackText: string): ActionButton
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.AutoButtonColor = false
	button.BackgroundColor3 = NORMAL_BUTTON_COLOR
	button.BackgroundTransparency = 0.12
	button.BorderSizePixel = 0
	button.Image = ""
	button.Parent = root

	local icon = Instance.new("ImageLabel")
	icon.Name = "EquipmentIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.48)
	icon.Size = UDim2.fromScale(0.78, 0.78)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = button

	local fallback = Instance.new("TextLabel")
	fallback.Name = "FallbackLabel"
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Size = UDim2.fromScale(0.7, 0.36)
	fallback.BackgroundTransparency = 1
	fallback.BorderSizePixel = 0
	fallback.FontFace = ThemeUtil.Font.extraBold
	fallback.Text = fallbackText
	fallback.TextColor3 = Color3.new(1, 1, 1)
	fallback.TextScaled = true
	fallback.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	return {
		button = button,
		icon = icon,
		fallback = fallback,
		combatKind = combatKind,
		tool = nil,
	}
end

local primary = createAction("PrimaryAttackButton", "Melee", "ATK")
local secondary = createAction("SecondaryShieldButton", "Shield", "DEF")
local actions = { primary, secondary }

local function getArena(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local arena = map and map:FindFirstChild("Arena")
	return if arena and arena:IsA("BasePart") then arena else nil
end

local function visitCarriedTools(callback: (Tool) -> ())
	local character = CharacterUtil.Get()
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				callback(child)
			end
		end
	end

	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				callback(child)
			end
		end
	end
end

local function findTool(combatKind: string): Tool?
	local found: Tool? = nil
	visitCarriedTools(function(tool)
		local _, profile = WeaponsMeta.GetProfile(tool)
		if not found and profile and profile.combatKind == combatKind then
			found = tool
		end
	end)
	return found
end

local function isInArena(): boolean
	local character = CharacterUtil.Get()
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return false
	end

	local heightAllowance = 0
	for _, action in ipairs(actions) do
		local tool = findTool(action.combatKind)
		if tool then
			local _, profile = WeaponsMeta.GetProfile(tool)
			if profile and type(profile.arenaHeightAllowanceStuds) == "number" then
				heightAllowance = math.max(heightAllowance, profile.arenaHeightAllowanceStuds)
			end
		end
	end

	return ArenaBounds.Contains(getArena(), rootPart.Position, heightAllowance)
end

local function renderTool(action: ActionButton, tool: Tool?)
	if action.tool == tool then
		return
	end

	action.tool = tool
	WeaponPreviewUtil.Clear(action.icon)
	action.icon.Image = ""
	action.icon.Visible = false
	action.fallback.Visible = tool == nil

	if not tool then
		return
	end

	local _, profile = WeaponsMeta.GetProfile(tool)
	local thumbnail = profile and profile.thumbnail
	if type(thumbnail) == "string" and thumbnail ~= "" then
		action.icon.Image = thumbnail
		action.icon.Visible = true
		action.fallback.Visible = false
	elseif tool.TextureId ~= "" then
		action.icon.Image = tool.TextureId
		action.icon.Visible = true
		action.fallback.Visible = false
	elseif WeaponPreviewUtil.Render(action.icon, tool) then
		action.icon.Visible = true
		action.fallback.Visible = false
	else
		action.fallback.Visible = true
	end
end

local function getJumpButton(): GuiButton?
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local touchControlFrame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jumpButton = touchControlFrame and touchControlFrame:FindFirstChild("JumpButton")
	return if jumpButton and jumpButton:IsA("GuiButton") then jumpButton else nil
end

local function relayout()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local jumpButton = getJumpButton()
	local jumpSize = if jumpButton then jumpButton.AbsoluteSize.X else FALLBACK_JUMP_SIZE
	local actionSize = math.clamp(math.round(jumpSize * ACTION_SCALE), MIN_ACTION_SIZE, MAX_ACTION_SIZE)

	local jumpCenter: Vector2
	if jumpButton and jumpButton.AbsoluteSize.X > 0 then
		jumpCenter = jumpButton.AbsolutePosition + jumpButton.AbsoluteSize / 2
	else
		jumpCenter = Vector2.new(
			viewport.X - FALLBACK_JUMP_SIZE * 0.75 - 10,
			viewport.Y - FALLBACK_JUMP_SIZE * 0.5 - 20
		)
	end

	primary.button.Size = UDim2.fromOffset(actionSize, actionSize)
	secondary.button.Size = UDim2.fromOffset(actionSize, actionSize)
	-- JumpButton lives in Roblox's CoreGui coordinate space, while this full-screen root
	-- can be extended beyond a device's safe area. Convert the absolute Jump center into
	-- root-local coordinates before positioning, otherwise notched phones add a large
	-- invisible gap between the controls.
	local rootOrigin = root.AbsolutePosition
	local radialOffset = jumpSize / 2 + JUMP_GAP + actionSize / 2
	primary.button.Position = UDim2.fromOffset(
		jumpCenter.X - radialOffset - rootOrigin.X,
		jumpCenter.Y - CLUSTER_INSET - rootOrigin.Y
	)
	secondary.button.Position = UDim2.fromOffset(
		jumpCenter.X - CLUSTER_INSET - rootOrigin.X,
		jumpCenter.Y - radialOffset - rootOrigin.Y
	)
end

local function activate(action: ActionButton)
	if ModalUtil.AnyOpen() or not isInArena() then
		return
	end

	local tool = findTool(action.combatKind)
	local character = CharacterUtil.Get()
	if not (tool and character and tool.Parent == character) then
		return
	end

	tool:Activate()
end

local function deactivate(action: ActionButton)
	local tool = findTool(action.combatKind)
	if tool then
		tool:Deactivate()
	end
end

local function isPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

for _, action in ipairs(actions) do
	action.button.InputBegan:Connect(function(input)
		if isPressInput(input) then
			action.button.BackgroundColor3 = PRESSED_BUTTON_COLOR
			if action == secondary then
				activate(action)
			end
		end
	end)
	action.button.InputEnded:Connect(function(input)
		if isPressInput(input) then
			action.button.BackgroundColor3 = NORMAL_BUTTON_COLOR
			if action == secondary then
				deactivate(action)
			end
		end
	end)
	action.button.Activated:Connect(function()
		if action == primary then
			activate(action)
		end
	end)
end

local modalOpen = ModalUtil.AnyOpen()
ModalUtil.OnChanged(function(anyPanelOpen)
	modalOpen = anyPanelOpen
	if anyPanelOpen then
		deactivate(secondary)
	end
end)

local elapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.1 then
		return
	end
	elapsed = 0

	local inArena = isInArena()
	root.Visible = UserInputService.TouchEnabled and inArena and not modalOpen

	for _, action in ipairs(actions) do
		local tool = findTool(action.combatKind)
		renderTool(action, tool)
		action.button.Interactable = tool ~= nil
			and tool.Parent == CharacterUtil.Get()
			and inArena
			and not modalOpen
	end
	relayout()
end)

relayout()
