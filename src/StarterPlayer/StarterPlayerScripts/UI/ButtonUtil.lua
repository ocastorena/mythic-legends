-- StarterPlayer/StarterPlayerScripts/UI/ButtonUtil
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local clickSound = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Audio"):WaitForChild("ButtonClick")

local ButtonUtil = {}

function ButtonUtil.hookClick(button, handler)
	button.Activated:Connect(function(...)
		local sound = clickSound:Clone()
		sound.Parent = button
		sound:Play()
		game.Debris:AddItem(sound, sound.TimeLength + 0.1)

		return handler(...)
	end)
end

return ButtonUtil
