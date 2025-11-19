-- StarterCharacterScripts/CombatClient

-- services
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

-- modules
local CombatUtils       = script.Parent:FindFirstChild("CombatUtils")
local Knockback         = require(CombatUtils.Knockback)

-- constants
local player            = Players.LocalPlayer
local char              = player.CharacterAdded:Wait()
local hum               = char:WaitForChild("Humanoid")
local hrp               = char:WaitForChild("HumanoidRootPart")
local animator          = hum.Animator

-- remotes
local combatEvent       = ReplicatedStorage.Remotes.CombatEvent

-- state
local equippedWeapon    = nil
local animationId       = nil
local animationRunning  = false

-- hitbox visualization
local function visualizeHitbox(cFrame: CFrame, hitboxSize: Vector3)
	local part = Instance.new("Part")
	part.Size = hitboxSize
	part.CFrame = cFrame
	part.CanCollide = false
	part.Parent = workspace
	part.Anchored = true
end

-- during animation, check for hits using tool hitbox
local function handleHitRequest(weapon: Tool)
	local handle = weapon:FindFirstChild("Handle")
	local seen = {}
	
	-- avoid self hits
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	while animationRunning do
		local cFrame = handle.Hitbox.CFrame
		local hitboxSize = handle.Hitbox.Size
		--visualizeHitbox(cFrame, hitboxSize)
		
		local parts = workspace:GetPartBoundsInBox(cFrame, hitboxSize, params)
		for _, part in ipairs(parts) do
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model ~= char then
				local targetPlayer = Players:GetPlayerFromCharacter(model)
				if targetPlayer and not seen[targetPlayer.UserId] then
					seen[targetPlayer.UserId] = true
					combatEvent:FireServer("HitRequest", {
						targetId = targetPlayer.UserId,
						weaponName = weapon.Name
					})
				end
			end
		end
		RunService.RenderStepped:Wait()
	end
end

local function handleHitResponse(impulse: Vector3, hitType: string, hitDuration: number)
	if hitType == "Knockback" then
		Knockback.Start(impulse, char, hitDuration)
	end
end

---------- Connects ----------
combatEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "HitResponse" then return end
	local deltaV = payload.deltaV
	local impulse = deltaV * hrp.AssemblyMass
	local hitType = payload.hitType
	local hitDuration = payload.hitDuration
	handleHitResponse(impulse, hitType, hitDuration)
end)

char.ChildAdded:Connect(function(tool)
	if tool:IsA("Tool") then
		if tool:GetAttribute("CombatReady") then return end
		tool:SetAttribute("CombatReady", true)

		if not tool:FindFirstChild("Handle") then
			error(string.format("[CombatClient] Tool %s does not have a Handle",tool.Name))
			return
		end
		equippedWeapon = tool
		animationId = tool:FindFirstChild("Handle"):FindFirstChild("Animation").AnimationId
	end
end)

-- Handle weapon hits with animation markers
animator.AnimationPlayed:Connect(function(track: AnimationTrack)
	local id = track.Animation and track.Animation.AnimationId or ""
	if id == animationId then
		track:GetMarkerReachedSignal("Begin"):Connect(function()
			animationRunning = true
			handleHitRequest(equippedWeapon)
		end)
		track:GetMarkerReachedSignal("End"):Connect(function()
			animationRunning = false
		end)
	end
end)
