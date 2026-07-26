-- ReplicatedStorage/Util/PlayerUtil
-- Helpers for the join/leave lifecycle.

local Players = game:GetService("Players")

local PlayerUtil = {}

-- Runs `onAdded` for every player already in the server, then for each new joiner.
--
-- Services connect PlayerAdded inside Start(), which races the first joiners on a fresh
-- server: a player who arrives before Start() runs would never be registered, leaving a
-- nil cache entry that every later request errors on. Always use this instead of a bare
-- Players.PlayerAdded:Connect for per-player setup.
function PlayerUtil.OnPlayer(onAdded: (Player) -> ()): RBXScriptConnection
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onAdded, player)
	end
	return Players.PlayerAdded:Connect(onAdded)
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
