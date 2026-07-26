-- ServerScriptService/Services/CombatService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = ReplicatedStorage:WaitForChild("Util")
local PlayerUtil = require(Util:WaitForChild("PlayerUtil"))
local LogUtil = require(Util:WaitForChild("LogUtil"))

local log = LogUtil.For("CombatService")

local WeaponsData = nil
local CombatEvent = nil

-- Furthest a hit may land, in studs. Generous enough to cover a lunging swing plus the
-- attacker's latency, tight enough that cross-map hits are rejected.
local MAX_HIT_DISTANCE = 30

-- Minimum seconds between accepted hits on the same target by the same attacker. Without
-- this a client can fire the remote every frame and pin someone in permanent knockback.
-- Scoped per attacker-target pair rather than per attacker, because one legitimate swing
-- reports each player its hitbox overlaps and must not rate-limit itself.
local HIT_COOLDOWN = 0.5

-- attackerUserId -> targetUserId -> os.clock() of last accepted hit
local lastHitAt: { [number]: { [number]: number } } = {}

--- The weapon the attacker is actually holding, lowercased to match the metadata keys.
--- Returns nil when they hold nothing, so a client cannot name a weapon it does not have.
local function getEquippedWeaponName(player: Player): string?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	return tool and tool.Name:lower() or nil
end

local function handleCombatEvent(player: Player, action: string?, payload: any?)
	if action ~= "HitRequest" or type(payload) ~= "table" then
		return
	end

	local targetId = tonumber(payload.targetId)
	if not targetId then
		return
	end

	local targetPlayer = Players:GetPlayerByUserId(targetId)
	if not targetPlayer or targetPlayer == player then
		return
	end

	-- Rate limit this attacker against this specific target.
	local now = os.clock()
	local byTarget = lastHitAt[player.UserId]
	if byTarget and byTarget[targetId] and (now - byTarget[targetId]) < HIT_COOLDOWN then
		return
	end

	-- The weapon comes from what the attacker is holding, not from the payload. The
	-- client used to name its own weapon, letting it pick the hardest-hitting entry.
	local weaponName = getEquippedWeaponName(player)
	if not weaponName then
		return
	end

	local weapon = WeaponsData[weaponName]
	if not weapon then
		log.debug(`Unknown weapon '{weaponName}' from {player.Name}`)
		return
	end

	local attackerPos = PlayerUtil.GetPosition(player)
	local targetPos = PlayerUtil.GetPosition(targetPlayer)
	if not (attackerPos and targetPos) then
		return
	end

	-- Range check: previously any client could knock any player from anywhere.
	local separation = (targetPos - attackerPos).Magnitude
	if separation > MAX_HIT_DISTANCE then
		log.debug(`Rejected out-of-range hit from {player.Name}: {math.floor(separation)} studs`)
		return
	end

	byTarget = byTarget or {}
	byTarget[targetId] = now
	lastHitAt[player.UserId] = byTarget

	local targetChar = targetPlayer.Character
	local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end

	-- Ensure target sim-owns their HRP (usually true for characters)
	pcall(function()
		targetRoot:SetNetworkOwner(targetPlayer)
	end)

	local dir = (targetPos - attackerPos)
	-- Straight-down or perfectly overlapping positions would make Unit NaN.
	dir = dir.Magnitude > 0 and dir.Unit or Vector3.xAxis

	local deltaV = dir * weapon.horiForce + Vector3.yAxis * weapon.vertForce

	-- Tell the target client to impulse (mass*Δv) + ragdoll
	CombatEvent:FireClient(targetPlayer, "HitResponse", {
		deltaV = deltaV,
		hitType = weapon.hitType,
		hitDuration = weapon.hitDuration,
	})
end

local CombatService = {}

function CombatService.Init(context: any)
	WeaponsData = context.Metadata.Weapons
	CombatEvent = context.Remotes.CombatEvent

	CombatEvent.OnServerEvent:Connect(handleCombatEvent)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		lastHitAt[userId] = nil
		-- also drop them as a target, so the table cannot grow across a long server life
		for _, byTarget in pairs(lastHitAt) do
			byTarget[userId] = nil
		end
	end)

	log.info("Initialized")
end

return CombatService
