--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Overlays/ModalBackdrop

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Motion = require(script.Parent.Parent:WaitForChild("Motion"))
local ModalState = require(script.Parent.Parent:WaitForChild("State"):WaitForChild("ModalState"))
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local function ModalBackdrop(scope: Fusion.Scope<typeof(Fusion)>): ScreenGui
	local isInputBlocked = scope:Value(ModalState.AnyOpen())
	local backdrop = scope:New("Frame")({
		Name = "ModalBackdrop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.surface.scrim.color,
		BackgroundTransparency = if ModalState.BackdropVisible()
			then Theme.surface.scrim.transparency
			else 1,
		BorderSizePixel = 0,
		Visible = ModalState.BackdropVisible(),
		ZIndex = 0,
	}) :: Frame

	local backdropTween: Tween? = nil
	local backdropGeneration = 0
	local function setBackdropVisible(isVisible: boolean)
		backdropGeneration += 1
		local generation = backdropGeneration
		if backdropTween then
			backdropTween:Cancel()
			backdropTween = nil
		end

		backdrop.Visible = true
		local tweenInfo
		if Motion.IsReduced() then
			tweenInfo = TweenInfo.new(0.25)
		elseif isVisible then
			tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else
			tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		end
		local tween = TweenService:Create(backdrop, tweenInfo, {
			BackgroundTransparency = if isVisible then Theme.surface.scrim.transparency else 1,
		})
		backdropTween = tween
		tween:Play()
		tween.Completed:Once(function(playbackState)
			if
				generation ~= backdropGeneration
				or playbackState ~= Enum.PlaybackState.Completed
			then
				return
			end
			backdropTween = nil
			backdrop.Visible = isVisible
		end)
	end

	local unsubscribeInput = ModalState.OnChanged(function(isOpen: boolean)
		isInputBlocked:set(isOpen)
	end)
	local unsubscribeBackdrop = ModalState.OnBackdropChanged(setBackdropVisible)
	table.insert(scope, unsubscribeInput)
	table.insert(scope, unsubscribeBackdrop)
	table.insert(scope, function()
		backdropGeneration += 1
		if backdropTween then
			backdropTween:Cancel()
			backdropTween = nil
		end
	end)

	return scope:New("ScreenGui")({
		Name = "ModalBackdropGui",
		Enabled = true,
		DisplayOrder = Theme.layer.scrim,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[scope.Children] = {
			backdrop :: Instance,
			scope:New("TextButton")({
				Name = "InputBlocker",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Active = isInputBlocked,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Modal = isInputBlocked,
				Selectable = false,
				Text = "",
				Visible = isInputBlocked,
				ZIndex = 21,
			}),
		},
	}) :: ScreenGui
end

return ModalBackdrop
