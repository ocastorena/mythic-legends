-- ServerScriptService/Services/CombatService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsData = require(ReplicatedStorage:WaitForChild("Config").Weapons)

local Context = nil

local combatEvent = nil

local CombatService = {}

local function handleCombatEvent(player: Player, action: string?, payload: any?)
	if action ~= "HitRequest" then return end
	
	local targetId = payload.targetId
	local weaponName = payload.weaponName
	
	if targetId then
		local targetPlayer = Players:GetPlayerByUserId(targetId)
		local tHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		local aHRP = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		local tgtChar = targetPlayer.Character
		local tgtHRP = tgtChar and tgtChar:FindFirstChild("HumanoidRootPart")
		local atkHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (tgtHRP and atkHRP) then return end

		-- Ensure target sim-owns their HRP (usually true for characters)
		pcall(function() tgtHRP:SetNetworkOwner(targetPlayer) end)
		
		local dir = (tgtHRP.Position - aHRP.Position).Unit
		--local deltaV = dir * (push.horizSpeed or 80) + Vector3.yAxis * (push.upSpeed or 36)
		local deltaV = dir * weaponsData[weaponName].HoriForce + Vector3.yAxis * weaponsData[weaponName].VertForce
		-- Tell the target client to impulse (mass*Δv) + ragdoll
		Context.Remotes.CombatEvent:FireClient(targetPlayer, "HitResponse", {
			deltaV = deltaV,
			hitType = weaponsData[weaponName].HitType,
			hitDuration = weaponsData[weaponName].HitDuration,
		}) 
	end
end

function CombatService.Init(context: any)
	Context = context
	combatEvent = Context.Remotes.CombatEvent
	
	combatEvent.OnServerEvent:Connect(handleCombatEvent)
	
	print("[CombatService] Initialized")
end

return CombatService
