-- StarterPlayer/StarterPlayerScripts/UI/Overlays/ModalBackdrop

local Players = game:GetService("Players")

local ModalState = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ModalState"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local function ModalBackdrop(scope: any): ScreenGui
	local enabled = scope:Value(ModalState.AnyOpen())
	local unsubscribe = ModalState.OnChanged(function(isOpen: boolean)
		enabled:set(isOpen)
	end)
	table.insert(scope, unsubscribe)

	return scope:New("ScreenGui")({
		Name = "ModalBackdropGui",
		Enabled = enabled,
		DisplayOrder = Theme.Layer.scrim,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[scope.Children] = {
			scope:New("Frame")({
				Name = "ModalBackdrop",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.Surface.scrim.color,
				BackgroundTransparency = Theme.Surface.scrim.transparency,
				BorderSizePixel = 0,
				ZIndex = 0,
			}),
			scope:New("TextButton")({
				Name = "InputBlocker",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Active = true,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Modal = true,
				Selectable = false,
				Text = "",
				ZIndex = 21,
			}),
		},
	}) :: ScreenGui
end

return ModalBackdrop
