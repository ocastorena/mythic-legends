-- StarterPlayer/StarterPlayerScripts/UI/Overlays/Toast

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ThemeUtil = require(script.Parent.Parent:WaitForChild("ThemeUtil"))
local ToastUtil = require(script.Parent.Parent:WaitForChild("ToastUtil"))

local POP_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD_SECONDS = 4

local function Toast(scope: any): ScreenGui
	local frame: Frame
	local label: TextLabel
	local scale: UIScale
	local generation = 0
	local activeTweens: { Tween } = {}

	local function cancelTweens()
		for _, tween in activeTweens do
			tween:Cancel()
		end
		table.clear(activeTweens)
	end

	local function playTween(instance: Instance, tweenInfo: TweenInfo, goals: { [string]: any }): Tween
		local tween = TweenService:Create(instance, tweenInfo, goals)
		table.insert(activeTweens, tween)
		tween:Play()
		return tween
	end

	local function show(message: string)
		generation += 1
		local currentGeneration = generation
		cancelTweens()
		label.Text = message
		label.TextTransparency = 1
		frame.BackgroundTransparency = 1
		frame.Visible = true
		scale.Scale = 0.7
		playTween(scale, POP_TWEEN, { Scale = 1 })
		playTween(frame, POP_TWEEN, { BackgroundTransparency = 0.2 })
		playTween(label, POP_TWEEN, { TextTransparency = 0 })

		task.delay(HOLD_SECONDS, function()
			if generation ~= currentGeneration then
				return
			end
			cancelTweens()
			playTween(frame, FADE_TWEEN, { BackgroundTransparency = 1 })
			local fade = playTween(label, FADE_TWEEN, { TextTransparency = 1 })
			fade.Completed:Wait()
			if generation == currentGeneration then
				frame.Visible = false
				table.clear(activeTweens)
			end
		end)
	end

	scale = scope:New "UIScale" { Scale = 0.7 }
	label = scope:New "TextLabel" {
		Name = "MessageLabel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = ThemeUtil.Font.extraBold,
		Text = "",
		TextColor3 = ThemeUtil.Text.body,
		TextScaled = true,
		TextTransparency = 1,
		TextWrapped = true,
		ZIndex = 2,
		[scope.Children] = {
			scope:New "UIPadding" {
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
			},
			scope:New "UITextSizeConstraint" {
				MinTextSize = 12,
				MaxTextSize = 20,
			},
			scope:New "UIStroke" {
				Color = Color3.new(0, 0, 0),
				Thickness = 2,
				Transparency = 0.15,
			},
		},
	} :: TextLabel
	frame = scope:New "Frame" {
		Name = "ToastFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0.4, 0, 0, 44),
		BackgroundColor3 = ThemeUtil.Surface.modal.color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
		[scope.Children] = {
			scale,
			label,
			scope:New "UICorner" { CornerRadius = UDim.new(1, 0) },
			scope:New "UISizeConstraint" {
				MinSize = Vector2.new(240, 44),
				MaxSize = Vector2.new(640, 56),
			},
		},
	} :: Frame

	local unsubscribe = ToastUtil.Subscribe(show)
	table.insert(scope, function()
		generation += 1
		unsubscribe()
		cancelTweens()
	end)

	return scope:New "ScreenGui" {
		Name = "ToastGui",
		Enabled = true,
		DisplayOrder = ThemeUtil.Layer.toast,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[scope.Children] = { frame },
	} :: ScreenGui
end

return Toast
