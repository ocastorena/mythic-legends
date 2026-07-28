-- ServerScriptService/Services/PlayerCombatService/KnockbackUtil
-- Applies gameplay-critical knockback on the server, then returns character physics to
-- the affected player after a deliberately short recovery window.

local Players = game:GetService("Players")

local KnockbackUtil = {}

local ownershipTokens: { [BasePart]: number } = {}
local ownershipCharacters: { [BasePart]: Model } = {}
local nextOwnershipToken = 0

local function isCharacterBodyPart(part: BasePart, character: Model): boolean
	return part:IsDescendantOf(character)
		and part:FindFirstAncestorOfClass("Tool") == nil
		and part:FindFirstAncestorOfClass("Accessory") == nil
end

-- Modern R15 ragdolls split into multiple physics assemblies (torso, limbs, head).
-- Applying the launch to only HumanoidRootPart lets grounded limbs absorb the force and
-- makes the player collapse in place. Deduplicate every current body assembly so the
-- entire ragdoll receives the same velocity change.
local function getAssemblyRoots(character: Model): { BasePart }
	local roots = {}
	local seen: { [BasePart]: boolean } = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and isCharacterBodyPart(descendant, character) then
			local assemblyRoot = descendant.AssemblyRootPart
			if assemblyRoot and not seen[assemblyRoot] then
				seen[assemblyRoot] = true
				table.insert(roots, assemblyRoot)
			end
		end
	end

	return roots
end

local function clearOwnershipRecord(root: BasePart)
	ownershipTokens[root] = nil
	ownershipCharacters[root] = nil
end

local function restoreOwnership(root: BasePart, token: number, player: Player)
	if ownershipTokens[root] ~= token then
		return
	end

	clearOwnershipRecord(root)
	if root.Parent then
		local restored = pcall(function()
			if player.Parent == Players then
				root:SetNetworkOwner(player)
			else
				root:SetNetworkOwnershipAuto()
			end
		end)
		if not restored and root.Parent then
			pcall(function()
				root:SetNetworkOwnershipAuto()
			end)
		end
	end
end

local function takeServerOwnership(root: BasePart, character: Model): (boolean, number)
	nextOwnershipToken += 1
	local token = nextOwnershipToken

	local succeeded = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	if not succeeded then
		return false, token
	end

	ownershipTokens[root] = token
	ownershipCharacters[root] = character
	return true, token
end

function KnockbackUtil.ClaimServerOwnership(character: Model, player: Player): boolean
	local roots = getAssemblyRoots(character)
	if #roots == 0 then
		return false
	end

	local claimed = {}
	for _, root in ipairs(roots) do
		local succeeded = root.Parent ~= nil and pcall(function()
			root:SetNetworkOwner(nil)
		end)
		if not succeeded then
			for _, claimedRoot in ipairs(claimed) do
				pcall(function()
					if player.Parent == Players then
						claimedRoot:SetNetworkOwner(player)
					else
						claimedRoot:SetNetworkOwnershipAuto()
					end
				end)
			end
			return false
		end

		table.insert(claimed, root)
	end

	return true
end

function KnockbackUtil.Apply(
	character: Model,
	player: Player,
	deltaV: Vector3,
	ownershipSeconds: number,
	preservePlayerOwnership: boolean?,
	angularVelocity: Vector3?
): boolean
	local roots = getAssemblyRoots(character)
	if #roots == 0 then
		return false
	end

	if preservePlayerOwnership then
		-- The validated target's owning client applies this impulse through the combat
		-- event. A server write here can be overwritten by the owner or double the launch.
		return roots[1].Parent ~= nil
	end

	local launched: { { root: BasePart, token: number } } = {}
	for _, root in ipairs(roots) do
		if root.Parent then
			local owned, token = takeServerOwnership(root, character)
			if owned then
				table.insert(launched, { root = root, token = token })
			end
		end
	end

	if #launched ~= #roots then
		for _, launch in ipairs(launched) do
			restoreOwnership(launch.root, launch.token, player)
		end
		return false
	end

	for _, launch in ipairs(launched) do
		local applied = pcall(function()
			launch.root.AssemblyAngularVelocity = angularVelocity or Vector3.zero
			launch.root:ApplyImpulse(deltaV * launch.root.AssemblyMass)
		end)
		if not applied then
			for _, ownedLaunch in ipairs(launched) do
				restoreOwnership(ownedLaunch.root, ownedLaunch.token, player)
			end
			return false
		end
	end

	for _, launch in ipairs(launched) do
		if ownershipSeconds > 0 then
			task.delay(ownershipSeconds, function()
				restoreOwnership(launch.root, launch.token, player)
			end)
		else
			restoreOwnership(launch.root, launch.token, player)
		end
	end

	return true
end

function KnockbackUtil.ApplyVelocity(
	character: Model,
	player: Player,
	launchVelocity: Vector3,
	durationSeconds: number,
	ownershipSeconds: number,
	angularVelocity: Vector3?
): boolean
	local roots = getAssemblyRoots(character)
	if #roots == 0 then
		return false
	end

	local launched = {}
	for _, root in ipairs(roots) do
		local owned, token = takeServerOwnership(root, character)
		if not owned then
			for _, launch in ipairs(launched) do
				if launch.linearVelocity.Parent then
					launch.linearVelocity:Destroy()
				end
				if launch.attachment.Parent then
					launch.attachment:Destroy()
				end
				restoreOwnership(launch.root, launch.token, player)
			end
			return false
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = "CombatFallbackLaunchAttachment"
		attachment.Parent = root

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name = "CombatFallbackLaunchVelocity"
		linearVelocity.Attachment0 = attachment
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		linearVelocity.VectorVelocity = launchVelocity
		linearVelocity.ForceLimitsEnabled = false
		linearVelocity.Parent = root
		root.AssemblyAngularVelocity = angularVelocity or Vector3.zero

		table.insert(launched, {
			root = root,
			token = token,
			attachment = attachment,
			linearVelocity = linearVelocity,
		})
	end

	task.delay(math.clamp(durationSeconds, 0.04, 0.2), function()
		for _, launch in ipairs(launched) do
			if launch.linearVelocity.Parent then
				launch.linearVelocity:Destroy()
			end
			if launch.attachment.Parent then
				launch.attachment:Destroy()
			end
		end
	end)

	for _, launch in ipairs(launched) do
		task.delay(math.max(durationSeconds, ownershipSeconds), function()
			restoreOwnership(launch.root, launch.token, player)
		end)
	end
	return true
end

function KnockbackUtil.Release(root: BasePart)
	clearOwnershipRecord(root)
	if root.Parent then
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end
end

function KnockbackUtil.ReleaseCharacter(character: Model)
	local roots = {}
	for root, ownerCharacter in pairs(ownershipCharacters) do
		if ownerCharacter == character then
			table.insert(roots, root)
		end
	end

	for _, root in ipairs(roots) do
		KnockbackUtil.Release(root)
	end
end

return KnockbackUtil
