--!strict
-- ServerScriptService/Infrastructure/PlayerUtil
-- Helpers for the join/leave lifecycle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)

local PlayerUtil = {}

-- Runs `onAdded` once for every player already in the server and each new joiner.
--
-- Connect before taking the snapshot so a player cannot join between GetPlayers() and
-- PlayerAdded:Connect(). The seen set collapses the overlap when the new player is also
-- present in the snapshot.
function PlayerUtil.OnPlayer(onAdded: (Player, () -> boolean) -> (), owner: Trove.Trove)
	local lifetime = owner:Extend()
	local isObserving = true
	local seen: { [Player]: boolean } = {}
	lifetime:Add(function()
		isObserving = false
		table.clear(seen)
	end)
	local function dispatch(player: Player)
		if not isObserving or player.Parent ~= Players or seen[player] then
			return
		end
		seen[player] = true
		onAdded(player, function()
			return isObserving and seen[player] == true and player.Parent == Players
		end)
	end

	lifetime:Connect(Players.PlayerAdded, dispatch)
	lifetime:Connect(Players.PlayerRemoving, function(player: Player)
		seen[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		lifetime:Add(task.defer(function()
			-- Started profile requests unwind cooperatively so their session can be released.
			lifetime:Pop(coroutine.running())
			dispatch(player)
		end))
	end
end

-- Server-authoritative character position. Returns nil while the character is loading,
-- so callers must treat that as "cannot verify" rather than assuming a location.
function PlayerUtil.GetPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	return root.Position
end

return PlayerUtil
