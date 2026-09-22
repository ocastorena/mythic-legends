--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/NoClimbController
-- Restartable: each character subscription owns and restores its climbing override.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local CharacterUtil = require(script.Parent.Parent.Character.CharacterUtil)
local NoClimbController = {}
local lifetime = Trove.new()
local isRunning = false

function NoClimbController.Init(_context: unknown) end

function NoClimbController.Start()
	if isRunning then
		return
	end
	isRunning = true
	local disconnectCharacter = CharacterUtil.OnCharacter(function(character, characterLifetime)
		local humanoid = character:WaitForChild("Humanoid")
		if not humanoid:IsA("Humanoid") or not isRunning then
			return
		end
		local wasEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Climbing)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		characterLifetime:Add(function()
			if
				humanoid.Parent and not humanoid:GetStateEnabled(Enum.HumanoidStateType.Climbing)
			then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, wasEnabled)
			end
		end)
		if humanoid:GetState() == Enum.HumanoidStateType.Climbing then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		characterLifetime:Connect(humanoid.StateChanged, function(_, state)
			if state == Enum.HumanoidStateType.Climbing then
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		end)
	end)
	lifetime:Add(function()
		disconnectCharacter()
	end)
end

function NoClimbController.Stop()
	isRunning = false
	lifetime:Clean()
end

return NoClimbController
