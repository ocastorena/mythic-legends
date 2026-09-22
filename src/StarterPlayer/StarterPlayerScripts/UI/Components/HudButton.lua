--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/HudButton

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FusionUtil = require(script.Parent.Parent.State.FusionUtil)
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local clickSound = ReplicatedStorage:WaitForChild("Assets")
	:WaitForChild("Audio")
	:WaitForChild("ButtonClick") :: Sound

export type Props = {
	name: string,
	icon: string,
	iconColor: Color3,
	isOpen: Fusion.UsedAs<boolean>,
	layoutOrder: number,
	buttonSize: Fusion.UsedAs<number>,
	onActivated: () -> (),
}

local function HudButton(scope: Fusion.Scope<typeof(Fusion)>, props: Props): ImageButton
	local hovered = scope:Value(false)
	local pressed = scope:Value(false)
	local activePressInput: InputObject? = nil

	local function isPrimaryPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	local function finishPress(input: InputObject)
		if input ~= activePressInput then
			return
		end
		activePressInput = nil
		pressed:set(false)
	end

	table.insert(scope, UserInputService.InputEnded:Connect(finishPress))
	local targetIconSize = scope:Computed(function(use: Fusion.Use)
		local buttonSize: number = FusionUtil.UseNumber(use, props.buttonSize)
		local displayScale = buttonSize / Theme.platform.topbarButtonSize
		local openScale = if FusionUtil.UseBoolean(use, props.isOpen)
			then Theme.platform.topbarIconOpenScale
			else 1
		return Theme.platform.topbarIconSize * displayScale * openScale
	end)
	local animatedIconSize = FusionUtil.SpringNumber(
		scope,
		targetIconSize,
		Theme.platform.topbarIconSpringSpeed,
		Theme.platform.topbarIconSpringDamping
	)
	local button: ImageButton
	button = scope:New("ImageButton")({
		Name = props.name,
		Size = scope:Computed(function(use: Fusion.Use)
			local size = FusionUtil.UseNumber(use, props.buttonSize)
			return UDim2.fromOffset(size, size)
		end),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.platform.topbarButtonFill,
		BackgroundTransparency = Theme.platform.topbarButtonTransparency,
		Image = "",
		LayoutOrder = props.layoutOrder,
		[scope.OnEvent("InputBegan")] = function(input)
			if activePressInput == nil and isPrimaryPress(input) then
				activePressInput = input
				pressed:set(true)
			end
		end,
		[scope.OnEvent("InputEnded")] = finishPress,
		[scope.OnEvent("MouseEnter")] = function()
			hovered:set(true)
		end,
		[scope.OnEvent("MouseLeave")] = function()
			hovered:set(false)
		end,
		[scope.OnEvent("Activated")] = function()
			local sound = clickSound:Clone()
			sound.Parent = button
			sound:Play()
			Debris:AddItem(sound, sound.TimeLength + 0.1)
			props.onActivated()
		end,
		[scope.Children] = {
			scope:New("UICorner")({
				CornerRadius = UDim.new(1, 0),
			}),
			scope:New("Frame")({
				Name = "StateLayer",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.platform.topbarButtonStateLayerFill,
				BackgroundTransparency = scope:Computed(function(use: Fusion.Use)
					if FusionUtil.UseBoolean(use, pressed) then
						return Theme.platform.topbarButtonPressedStateTransparency
					elseif FusionUtil.UseBoolean(use, hovered) then
						return Theme.platform.topbarButtonHoverStateTransparency
					end
					return 1
				end),
				BorderSizePixel = 0,
				ZIndex = 1,
				[scope.Children] = {
					scope:New("UICorner")({
						CornerRadius = UDim.new(1, 0),
					}),
				},
			}),
			scope:New("ImageLabel")({
				Name = "Icon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = scope:Computed(function(use: Fusion.Use)
					local size = FusionUtil.UseNumber(use, animatedIconSize)
					return UDim2.fromOffset(size, size)
				end),
				BackgroundTransparency = 1,
				Image = props.icon,
				ImageColor3 = props.iconColor,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 2,
			}),
		},
	}) :: ImageButton
	return button
end

return HudButton
