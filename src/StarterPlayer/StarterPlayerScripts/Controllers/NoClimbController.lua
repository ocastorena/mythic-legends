-- StarterPlayer/StarterPlayerScripts/Controllers/NoClimbController

local NoClimbController = {}
local connections: { RBXScriptConnection } = {}

function NoClimbController.Init(_context: unknown)
end

function NoClimbController.Start()
-- Blocks "climbing other players" but still allows ladders/walls.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script:FindFirstAncestor("Controllers").Parent
local CharacterUtil = require(Client:WaitForChild("Character"):WaitForChild("CharacterUtil"))

-- Re-applied per character: the guard used to be installed once on the first Humanoid, so
-- every respawn after that was unguarded on the client.
table.insert(connections, CharacterUtil.OnCharacter(function(character)
	local hum = character:WaitForChild("Humanoid") :: Humanoid

	-- 1) Block future transitions into Climbing
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	-- 2) If somehow already climbing, force exit
	if hum:GetState() == Enum.HumanoidStateType.Climbing then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	-- 3) Guard: if something tries to push us into Climbing later, drop out
	table.insert(connections, hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Climbing then
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end))
end))
end

function NoClimbController.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

return NoClimbController
