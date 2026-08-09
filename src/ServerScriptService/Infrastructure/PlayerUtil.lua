-- ServerScriptService/Infrastructure/PlayerUtil
-- Helpers for the join/leave lifecycle.

local Players = game:GetService("Players")

local PlayerUtil = {}

-- Runs `onAdded` once for every player already in the server and each new joiner.
--
-- Connect before taking the snapshot so a player cannot join between GetPlayers() and
-- PlayerAdded:Connect(). The seen set collapses the overlap when the new player is also
-- present in the snapshot.
function PlayerUtil.OnPlayer(onAdded: (Player) -> ()): RBXScriptConnection
	local seen: { [Player]: boolean } = {}
	local function dispatch(player: Player)
		if seen[player] then
			return
		end
		seen[player] = true
		onAdded(player)
	end

	local connection = Players.PlayerAdded:Connect(dispatch)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(dispatch, player)
	end
	return connection
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
