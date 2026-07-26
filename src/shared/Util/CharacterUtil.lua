-- ReplicatedStorage/Util/CharacterUtil
-- Client-side character lifecycle. The mirror of PlayerUtil.OnPlayer on the server.
--
-- Controllers used to each write their own `player.Character or player.CharacterAdded:Wait()`
-- and cache the Humanoid/HumanoidRootPart in a local. That local goes stale the moment the
-- player dies, so behaviour silently stopped working after the first respawn. Always take
-- the character from here rather than caching it.

local Players = game:GetService("Players")

local CharacterUtil = {}

local localPlayer = Players.LocalPlayer

--- Runs `onCharacter(character)` for the character that already exists, and again for
--- every respawn. Returns the CharacterAdded connection.
---
--- The callback is spawned, so it may yield (WaitForChild) without blocking the caller or
--- delaying later respawns.
function CharacterUtil.OnCharacter(onCharacter: (Model) -> ()): RBXScriptConnection
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	return localPlayer.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, character)
	end)
end

--- The current character, or nil while dead/loading.
function CharacterUtil.Get(): Model?
	return localPlayer.Character
end

--- The live HumanoidRootPart, or nil. Read this per use; never cache it across respawns.
function CharacterUtil.GetRoot(): BasePart?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root or nil
end

--- The live Humanoid, or nil.
function CharacterUtil.GetHumanoid(): Humanoid?
	local character = localPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

--- Current world position, or nil while the character is unavailable.
function CharacterUtil.GetPosition(): Vector3?
	local root = CharacterUtil.GetRoot()
	return root and root.Position or nil
end

return CharacterUtil
