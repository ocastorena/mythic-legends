-- StarterPlayer/StarterPlayerScripts/PlayerCombatController

-- services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- modules
local CharacterUtil = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Character"):WaitForChild("CharacterUtil"))

-- remotes
local combatEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatEvent")
local weaponsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Weapons"))

local localPlayer = Players.LocalPlayer
local bindings: { [Tool]: { RBXScriptConnection } } = {}
local lastSwingRequestAt = 0

-- The custom hotbar owns equipping, so combat cannot depend exclusively on Roblox's
-- default Tool activation path. Keep the Tool signal as a compatibility path for touch
-- and tool-specific interactions, but also listen for an unconsumed primary input.
-- This local debounce only merges those two reports from one click; the server remains
-- authoritative for the real swing cooldown.
local REQUEST_DEDUP_SECONDS = 0.08

local function getEquippedMeleeTool(): Tool?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and weaponsData.IsMeleeTool(child) then
			return child
		end
	end

	return nil
end

local function requestSwing(tool: Tool?)
	if not tool or tool.Parent ~= localPlayer.Character or not weaponsData.IsMeleeTool(tool) then
		return
	end

	local now = os.clock()
	if now - lastSwingRequestAt < REQUEST_DEDUP_SECONDS then
		return
	end
	lastSwingRequestAt = now
	combatEvent:FireServer("SwingRequest")
end

local function unbindTool(tool: Tool)
	local connections = bindings[tool]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	bindings[tool] = nil
end

-- Tool animations remain local presentation. A single input request is the only combat
-- information sent to the server; the server chooses the hit target and applies impact.
local function bindMeleeTool(tool: Tool)
	if bindings[tool] or not weaponsData.IsMeleeTool(tool) then
		return
	end

	local connections = {}
	connections[1] = tool.Activated:Connect(function()
		requestSwing(tool)
	end)
	connections[2] = tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unbindTool(tool)
		end
	end)
	bindings[tool] = connections
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		requestSwing(getEquippedMeleeTool())
	end
end)

-- Rebind on every spawn. Only recognised melee tools get an input listener, so future
-- shields, consumables, and utility tools cannot hijack this controller or error because
-- they lack a Handle, Animation, or Hitbox.
CharacterUtil.OnCharacter(function(character)
	if localPlayer.Character ~= character then
		return
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindMeleeTool(child)
		end
	end)

	for _, existing in ipairs(character:GetChildren()) do
		if existing:IsA("Tool") then
			bindMeleeTool(existing)
		end
	end
end)
