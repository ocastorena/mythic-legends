-- ServerScriptService/Services/CombatService

local Players = game:GetService("Players")

local WeaponsData = nil

local CombatEvent = nil

local CombatService = {}

local function handleCombatEvent(player: Player, action: string?, payload: any?)
	if action ~= "HitRequest" then
		return
	end

	local targetId = payload.targetId
	local weaponName = payload.weaponName

	if targetId then
		local targetPlayer = Players:GetPlayerByUserId(targetId)
		-- local tHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		local aChar = player.Character
		if aChar then
			local aHRP = aChar:FindFirstChild("HumanoidRootPart") :: BasePart
			local tgtChar = targetPlayer.Character
			local tgtHRP = tgtChar and tgtChar:FindFirstChild("HumanoidRootPart")
			local atkHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not (tgtHRP and atkHRP) then
				return
			end

			-- Ensure target sim-owns their HRP (usually true for characters)
			pcall(function()
				tgtHRP:SetNetworkOwner(targetPlayer)
			end)

			local dir = (tgtHRP.Position - aHRP.Position).Unit
			--local deltaV = dir * (push.horizSpeed or 80) + Vector3.yAxis * (push.upSpeed or 36)
			local deltaV = dir * WeaponsData[weaponName].HoriForce + Vector3.yAxis * WeaponsData[weaponName].VertForce
			-- Tell the target client to impulse (mass*Δv) + ragdoll
			CombatEvent:FireClient(targetPlayer, "HitResponse", {
				deltaV = deltaV,
				hitType = WeaponsData[weaponName].hitType,
				hitDuration = WeaponsData[weaponName].hitDuration,
			})
		end
	end
end

function CombatService.Init(context: any)
	WeaponsData = context.Metadata.Weapons
	CombatEvent = context.Remotes.CombatEvent

	CombatEvent.OnServerEvent:Connect(handleCombatEvent)

	print("[CombatService] Initialized")
end

return CombatService
