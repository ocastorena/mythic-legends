-- ReplicatedStorage/Util/ToastUtil
-- Transient message that pops in and fades out. Owns the ClaimToast ScreenGui and its
-- animation, so callers only supply text.
--
-- Split out of ClaimToastController: the animation was never claim-specific, it just had
-- one caller. Anything that needs to tell the player something in passing can use this
-- without another controller growing a second copy of the tween code.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ToastUtil = {}

local POP_TI = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_TI = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD_SECONDS = 4.0

local localPlayer = Players.LocalPlayer

local frame: Frame? = nil
local label: TextLabel? = nil
local finalSize: UDim2? = nil
-- Bumped per show so a toast that arrives mid-fade cancels the previous hide.
local showToken = 0

local function ensureGui(): boolean
	if frame and frame.Parent then
		return true
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local screenGui = playerGui and playerGui:FindFirstChild("ClaimToast")
	if not (screenGui and screenGui:IsA("ScreenGui")) then
		return false
	end

	-- Survive respawns; the toast is not tied to the character.
	screenGui.ResetOnSpawn = false

	local toastFrame = screenGui:FindFirstChild("Frame")
	local textLabel = toastFrame and toastFrame:FindFirstChild("Text")
	if not (toastFrame and toastFrame:IsA("Frame") and textLabel and textLabel:IsA("TextLabel")) then
		return false
	end

	frame = toastFrame
	label = textLabel
	-- Read the authored size once, before the first tween shrinks it to zero.
	finalSize = finalSize or toastFrame.Size
	return true
end

--- Pops a message in and fades it out. Safe to call repeatedly; the newest wins.
function ToastUtil.Show(message: string)
	if not ensureGui() then
		return
	end
	local toastFrame, textLabel = frame :: Frame, label :: TextLabel

	showToken += 1
	local token = showToken

	textLabel.Text = message

	-- prep
	toastFrame.Visible = true
	toastFrame.Size = UDim2.fromOffset(0, 0)
	toastFrame.BackgroundTransparency = 0.2
	textLabel.TextTransparency = 0

	-- pop-in
	TweenService:Create(toastFrame, POP_TI, { Size = finalSize }):Play()

	-- fade out after short hold
	task.delay(HOLD_SECONDS, function()
		if token ~= showToken then
			return -- superseded by a newer toast
		end
		local t1 = TweenService:Create(toastFrame, FADE_TI, { BackgroundTransparency = 1 })
		local t2 = TweenService:Create(textLabel, FADE_TI, { TextTransparency = 1 })
		t1:Play()
		t2:Play()
		t2.Completed:Wait()
		if token == showToken then
			toastFrame.Visible = false
		end
	end)
end

return ToastUtil
