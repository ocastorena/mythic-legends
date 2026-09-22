--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/CombatActions

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Types = require(script.Parent.Parent.Parent.Types)
local Theme = require(script.Parent.Parent.Theme)

local NORMAL_BUTTON_COLOR = Color3.fromRGB(60, 60, 64)
local FALLBACK_JUMP_SIZE = 70
local JUMP_GAP = 10
local CLUSTER_INSET = 18

export type Props = {
	combatController: Types.CombatControllerApi,
}

local function createButton(root: Frame, name: string): (ImageButton, Frame)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.AutoButtonColor = false
	button.BackgroundColor3 = NORMAL_BUTTON_COLOR
	button.BackgroundTransparency = 0.12
	button.BorderSizePixel = 0
	button.Image = ""
	button.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.72
	stroke.Thickness = 1.5
	stroke.Parent = button

	local icon = Instance.new("Frame")
	icon.Name = "EquipmentIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.78, 0.78)
	icon.BackgroundTransparency = 1
	icon.ZIndex = button.ZIndex + 1
	icon.Parent = button
	return button, icon
end

local function CombatActions(scope: Fusion.Scope<typeof(Fusion)>, props: Props): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = scope:New("ScreenGui")({
		Name = "CombatActionGui",
		Enabled = UserInputService.TouchEnabled,
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	local root = Instance.new("Frame")
	root.Name = "CombatActions"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = screenGui
	local attackButton, attackIcon = createButton(root, "PrimaryAttackButton")
	local shieldButton, shieldIcon = createButton(root, "SecondaryShieldButton")
	local shieldStatus = Instance.new("TextLabel")
	shieldStatus.Name = "GuardStatus"
	shieldStatus.AnchorPoint = Vector2.new(0.5, 0)
	shieldStatus.Position = UDim2.fromScale(0.5, 1)
	shieldStatus.Size = UDim2.new(1.7, 0, 0, 18)
	shieldStatus.BackgroundTransparency = 1
	shieldStatus.FontFace = Theme.font.bold
	shieldStatus.TextSize = 12
	shieldStatus.TextColor3 = Theme.textColors.strong
	shieldStatus.TextStrokeTransparency = 0.35
	shieldStatus.Text = ""
	shieldStatus.ZIndex = shieldButton.ZIndex + 2
	shieldStatus.Parent = shieldButton

	local function getJumpButton(): GuiButton?
		local touchGui = playerGui:FindFirstChild("TouchGui")
		local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
		local jumpButton = frame and frame:FindFirstChild("JumpButton")
		return if jumpButton and jumpButton:IsA("GuiButton") then jumpButton else nil
	end

	local function relayout()
		if root.Parent == nil then
			return
		end
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local jumpButton = getJumpButton()
		local jumpSize = if jumpButton and jumpButton.AbsoluteSize.X > 0
			then jumpButton.AbsoluteSize.X
			else FALLBACK_JUMP_SIZE
		local actionSize = math.round(jumpSize)
		local jumpCenter = if jumpButton and jumpButton.AbsoluteSize.X > 0
			then jumpButton.AbsolutePosition + jumpButton.AbsoluteSize / 2
			else Vector2.new(
				viewport.X - FALLBACK_JUMP_SIZE * 0.75 - 10,
				viewport.Y - FALLBACK_JUMP_SIZE * 0.5 - 20
			)
		local origin = root.AbsolutePosition
		local radialOffset = jumpSize / 2 + JUMP_GAP + actionSize / 2
		attackButton.Size = UDim2.fromOffset(actionSize, actionSize)
		shieldButton.Size = UDim2.fromOffset(actionSize, actionSize)
		attackButton.Position = UDim2.fromOffset(
			jumpCenter.X - radialOffset - origin.X,
			jumpCenter.Y - CLUSTER_INSET - origin.Y
		)
		shieldButton.Position = UDim2.fromOffset(
			jumpCenter.X - CLUSTER_INSET - origin.X,
			jumpCenter.Y - radialOffset - origin.Y
		)
	end

	local unbind = props.combatController.BindView({
		root = root,
		attackButton = attackButton,
		attackIcon = attackIcon,
		shieldButton = shieldButton,
		shieldIcon = shieldIcon,
		shieldStatus = shieldStatus,
		relayout = relayout,
	})
	table.insert(scope, unbind)
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(scope, camera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout))
	end
	table.insert(
		scope,
		playerGui.ChildAdded:Connect(function(child: Instance)
			if child.Name == "TouchGui" then
				task.defer(relayout)
			end
		end)
	)
	task.defer(relayout)
	return screenGui
end

return CombatActions
