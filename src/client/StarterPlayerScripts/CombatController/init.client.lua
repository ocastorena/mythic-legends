-- StarterPlayer/StarterPlayerScripts/CombatController

-- services
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- modules
local KnockbackUtil     = require(script.KnockbackUtil)
local CharacterUtil     = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("CharacterUtil"))

-- remotes
local combatEvent       = ReplicatedStorage.Remotes.CombatEvent

-- Per-character handles, refreshed on every spawn. These were previously captured once
-- from `player.CharacterAdded:Wait()`, which both skipped the character that already
-- existed (blocking until the first respawn) and went stale on every death after that.
local char: Model? = nil
local hrp: BasePart? = nil

-- state, reset per life
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
	if hitType == "Knockback" and char then
		KnockbackUtil.Start(impulse, char, hitDuration)
	end
end

local function onToolAdded(tool: Instance)
	if not tool:IsA("Tool") then
		return
	end

	-- No "already processed" guard here: registering is idempotent, and the same Tool
	-- instance is re-parented in from the Backpack on every respawn, so skipping it the
	-- second time would leave the player holding a weapon that never swings.
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		error(string.format("[CombatController] Tool %s does not have a Handle", tool.Name))
	end
	equippedWeapon = tool
	animationId = handle:FindFirstChild("Animation").AnimationId
end

-- Handle weapon hits with animation markers
local function onAnimationPlayed(track: AnimationTrack)
	local id = track.Animation and track.Animation.AnimationId or ""
	if id ~= animationId then
		return
	end
	track:GetMarkerReachedSignal("Begin"):Connect(function()
		animationRunning = true
		handleHitRequest(equippedWeapon)
	end)
	track:GetMarkerReachedSignal("End"):Connect(function()
		animationRunning = false
	end)
end

---------- Connects ----------
combatEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "HitResponse" then return end
	if not hrp then return end
	local impulse = payload.deltaV * hrp.AssemblyMass
	handleHitResponse(impulse, payload.hitType, payload.hitDuration)
end)

-- Rebind everything character-scoped on each spawn. Connections made against the previous
-- character are severed when Roblox destroys it, so they do not need unwinding here.
CharacterUtil.OnCharacter(function(character)
	local hum = character:WaitForChild("Humanoid") :: Humanoid

	char = character
	hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

	-- a fresh body is unarmed and mid-nothing
	equippedWeapon = nil
	animationId = nil
	animationRunning = false

	character.ChildAdded:Connect(onToolAdded)
	-- Tools can be re-parented in before this runs on a respawn.
	for _, existing in ipairs(character:GetChildren()) do
		onToolAdded(existing)
	end

	local animator = hum:WaitForChild("Animator") :: Animator
	animator.AnimationPlayed:Connect(onAnimationPlayed)
end)
