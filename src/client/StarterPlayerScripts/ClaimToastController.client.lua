-- StarterPlayer/StarterPlayerScripts/ClaimToastController
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local SpawnEvent = Remotes:WaitForChild("SpawnEvent")

-- Grab the cloned ScreenGui from PlayerGui (StarterGui → PlayerGui)
local playerGui  = localPlayer:WaitForChild("PlayerGui")
local screenGui  = playerGui:WaitForChild("ClaimToast") :: ScreenGui
local toastFrame = screenGui:WaitForChild("Frame") :: Frame
local textLabel  = toastFrame:WaitForChild("Text") :: TextLabel

-- Ensure it doesn’t vanish on respawn
screenGui.ResetOnSpawn = false

-- Read final size from template; we tween from 0 → final
local FINAL_SIZE = toastFrame.Size
local POP_TI   = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_TI  = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function popAndFade(message: string)
	textLabel.Text = message

	-- prep
	toastFrame.Visible = true
	toastFrame.Size = UDim2.fromOffset(0, 0)
	toastFrame.BackgroundTransparency = 0.2
	textLabel.TextTransparency = 0

	-- pop-in
	TweenService:Create(toastFrame, POP_TI, { Size = FINAL_SIZE }):Play()

	-- fade out after short hold
	task.delay(4.0, function()
		local t1 = TweenService:Create(toastFrame, FADE_TI, { BackgroundTransparency = 1 })
		local t2 = TweenService:Create(textLabel,  FADE_TI, { TextTransparency = 1 })
		t1:Play(); t2:Play()
		t2.Completed:Wait()
		toastFrame.Visible = false
	end)
end

local function resolveName(payload)
	if payload and typeof(payload.displayName) == "string" and payload.displayName ~= "" then
		-- check first character for vowel sound
		local firstChar = string.sub(payload.displayName, 1, 1):lower()
		local article = (firstChar == "a" or firstChar == "e" or firstChar == "i" or firstChar == "o" or firstChar == "u") and "an" or "a"

		return string.format("%s %s", article, payload.displayName)
	end
	return "a Mythling"
end

-- Server fires: SpawnEvent:FireAllClients("Claimed", { mythlingId, winnerUserId, instanceId, typeId|typeName })
SpawnEvent.OnClientEvent:Connect(function(event, payload)
	if event ~= "Claimed" then return end
	if not payload or payload.winnerUserId ~= localPlayer.UserId then return end
	local name = resolveName(payload)
	popAndFade(("You claimed %s!"):format(name))
end)
