--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/CombatController/MeleeHitbox

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MeleeHitbox = {}

export type SweepRequest = {
	attacker: Player,
	character: Model,
	hitbox: BasePart,
	previousCFrame: CFrame,
	samples: number,
	padding: Vector3,
	maxParts: number,
	requireLineOfSight: boolean,
}

type CandidateScore = {
	contact: number,
	rootDistance: number,
}

local function getPlayerFromPart(part: BasePart): Player?
	local ancestor: Instance? = part
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(ancestor)
			if player then
				return player
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function hasLineOfSight(attackerCharacter: Model, targetCharacter: Model): boolean
	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerRoot or not attackerRoot:IsA("BasePart") or not targetRoot or not targetRoot:IsA("BasePart") then
		return false
	end

	local origin = attackerRoot.Position + Vector3.yAxis * 1.5
	local direction = targetRoot.Position + Vector3.yAxis * 1.5 - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter }
	params.IgnoreWater = true
	local result = Workspace:Raycast(origin, direction, params)
	return result == nil or result.Instance:IsDescendantOf(targetCharacter)
end

-- This is the stable detector boundary. A future package-backed implementation can replace
-- this sweep without changing combat input, networking, or server validation.
function MeleeHitbox.FindClosestTarget(request: SweepRequest): Player?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { request.character }
	params.MaxParts = request.maxParts

	local attackerRoot = request.character:FindFirstChild("HumanoidRootPart")
	local candidates: { [Player]: CandidateScore } = {}
	local samples = math.max(1, math.floor(request.samples))

	for sampleIndex = 1, samples do
		local sample = request.previousCFrame:Lerp(request.hitbox.CFrame, sampleIndex / samples)
		for _, part in Workspace:GetPartBoundsInBox(sample, request.hitbox.Size + request.padding, params) do
			local target = getPlayerFromPart(part)
			local targetCharacter = target and target.Character
			local humanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
			if
				target
				and target ~= request.attacker
				and targetCharacter
				and humanoid
				and humanoid.Health > 0
				and targetCharacter:GetAttribute("CombatReady") == true
				and targetRoot
				and targetRoot:IsA("BasePart")
				and (not request.requireLineOfSight or hasLineOfSight(request.character, targetCharacter))
			then
				local contact = (part.Position - sample.Position).Magnitude
				local rootDistance = if attackerRoot and attackerRoot:IsA("BasePart")
					then (targetRoot.Position - attackerRoot.Position).Magnitude
					else math.huge
				local existing = candidates[target]
				if not existing or contact < existing.contact then
					candidates[target] = { contact = contact, rootDistance = rootDistance }
				end
			end
		end
	end

	local bestTarget: Player? = nil
	local bestContact = math.huge
	local bestRootDistance = math.huge
	for target, score in candidates do
		if
			score.contact < bestContact
			or (score.contact == bestContact and score.rootDistance < bestRootDistance)
			or (
				score.contact == bestContact
				and score.rootDistance == bestRootDistance
				and (not bestTarget or target.UserId < bestTarget.UserId)
			)
		then
			bestTarget = target
			bestContact = score.contact
			bestRootDistance = score.rootDistance
		end
	end

	return bestTarget
end

return MeleeHitbox
