--!strict
-- StarterPlayer/StarterPlayerScripts/UI/ButtonUtil
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local clickSound = ReplicatedStorage:WaitForChild("Assets")
	:WaitForChild("Audio")
	:WaitForChild("ButtonClick") :: Sound

local ButtonUtil = {}

function ButtonUtil.HookClick(button: GuiButton, handler: () -> ()): RBXScriptConnection
	return button.Activated:Connect(function()
		local sound = clickSound:Clone()
		sound.Parent = button
		sound:Play()
		Debris:AddItem(sound, sound.TimeLength + 0.1)

		handler()
	end)
end

return ButtonUtil
