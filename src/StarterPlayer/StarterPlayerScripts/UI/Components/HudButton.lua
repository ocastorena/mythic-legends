-- StarterPlayer/StarterPlayerScripts/UI/Components/HudButton

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ThemeUtil = require(script.Parent.Parent:WaitForChild("ThemeUtil"))
local clickSound = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Audio"):WaitForChild("ButtonClick")

export type Props = {
	name: string,
	icon: string,
	iconColor: Color3,
	iconScale: number,
	layoutOrder: number,
	buttonSize: any,
	onActivated: () -> (),
}

local function HudButton(scope: any, props: Props): ImageButton
	local hovered = scope:Value(false)
	local button: ImageButton
	button = scope:New "ImageButton" {
		Name = props.name,
		Size = scope:Computed(function(use)
			local size = use(props.buttonSize)
			return UDim2.fromOffset(size, size)
		end),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = ThemeUtil.Platform.topbarButtonFill,
		BackgroundTransparency = scope:Computed(function(use)
			return if use(hovered)
				then ThemeUtil.Platform.topbarButtonHoverTransparency
				else ThemeUtil.Platform.topbarButtonTransparency
		end),
		Image = "",
		LayoutOrder = props.layoutOrder,
		[scope.OnEvent "MouseEnter"] = function()
			hovered:set(true)
		end,
		[scope.OnEvent "MouseLeave"] = function()
			hovered:set(false)
		end,
		[scope.OnEvent "Activated"] = function()
			local sound = clickSound:Clone()
			sound.Parent = button
			sound:Play()
			Debris:AddItem(sound, sound.TimeLength + 0.1)
			props.onActivated()
		end,
		[scope.Children] = {
			scope:New "UICorner" {
				CornerRadius = UDim.new(1, 0),
			},
			scope:New "ImageLabel" {
				Name = "Icon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(props.iconScale, props.iconScale),
				BackgroundTransparency = 1,
				Image = props.icon,
				ImageColor3 = props.iconColor,
				ScaleType = Enum.ScaleType.Fit,
			},
		},
	} :: ImageButton
	return button
end

return HudButton
