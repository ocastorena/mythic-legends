--!strict
-- StarterPlayer/StarterPlayerScripts/Character/CharacterUtil
-- Character subscriptions own yielding callbacks and per-character resources.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)

type TroveInstance = Trove.Trove
local CharacterUtil = {}
local localPlayer = Players.LocalPlayer

-- Cleanup cancels suspended callbacks. Respawning ends the previous character lifetime.
function CharacterUtil.OnCharacter(onCharacter: (Model, TroveInstance) -> ()): () -> ()
	local lifetime = Trove.new()
	local characterLifetime = lifetime:Extend()
	local isActive = true
	local function bind(character: Model)
		characterLifetime:Clean()
		if not isActive then
			return
		end
		characterLifetime:Add(task.defer(function()
			if isActive and localPlayer.Character == character then
				onCharacter(character, characterLifetime)
			end
		end))
	end
	lifetime:Connect(localPlayer.CharacterAdded, bind)
	lifetime:Connect(localPlayer.CharacterRemoving, function()
		characterLifetime:Clean()
	end)
	if localPlayer.Character then
		bind(localPlayer.Character)
	end
	return function()
		if not isActive then
			return
		end
		isActive = false
		lifetime:Destroy()
	end
end

function CharacterUtil.Get(): Model?
	return localPlayer.Character
end

function CharacterUtil.GetRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function CharacterUtil.GetHumanoid(): Humanoid?
	local character = localPlayer.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

function CharacterUtil.GetPosition(): Vector3?
	local root = CharacterUtil.GetRoot()
	return if root then root.Position else nil
end

return CharacterUtil
