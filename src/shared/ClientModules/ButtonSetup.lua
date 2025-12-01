local ReplicatedStorage = game:GetService("ReplicatedStorage")
local clickSound = ReplicatedStorage:WaitForChild("Audio"):WaitForChild("ButtonClick")

local module = {}

function module.hookClick(button, handler)
	button.Activated:Connect(function(...)
		local sound = clickSound:Clone()
		sound.Parent = button
		sound:Play()
		game.Debris:AddItem(sound, sound.TimeLength + 0.1)

		return handler(...)
	end)
end

return module
