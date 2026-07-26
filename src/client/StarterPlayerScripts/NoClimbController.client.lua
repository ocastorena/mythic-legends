-- StarterPlayer/StarterPlayerScripts/NoClimbController
-- Blocks "climbing other players" but still allows ladders/walls.
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char   = player.Character or player.CharacterAdded:Wait()
local hum    = char:WaitForChild("Humanoid")

-- 1) Block future transitions into Climbing
hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

-- 2) If somehow already climbing, force exit
if hum:GetState() == Enum.HumanoidStateType.Climbing then
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
end

-- 3) Guard: if something tries to push us into Climbing later, drop out
hum.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Climbing then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end)
