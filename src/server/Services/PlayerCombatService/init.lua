-- ServerScriptService/Services/PlayerCombatService
-- The attacker client selects one blade contact. The server performs inexpensive sanity
-- checks, then relays the positional effect without independently choosing another target.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local PlayerUtil = require(Infrastructure:WaitForChild("PlayerUtil"))
local KnockdownUtil = require(script.KnockdownUtil)

local log = LogUtil.For("PlayerCombatService")

local WeaponsData = nil
local CombatEvent: RemoteEvent? = nil
local CombatVfxEvent: RemoteEvent? = nil
local Arena: BasePart? = nil

local nextHitAt: { [number]: number } = {}
local lastHitSequence: { [number]: number } = {}
local recoveryUntil: { [number]: number } = {}
local recoveryTokens: { [number]: number } = {}
local nextHitId = 0

local EPSILON = 0.001
local MAX_SEQUENCE = 2147483647
local MAX_SERVER_TOLERANCE_STUDS = 12

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function isInsideArena(position: Vector3, heightAllowanceStuds: number?): boolean
	if not Arena then
		return false
	end

	local localPosition = Arena.CFrame:PointToObjectSpace(position)
	local radius = math.max(Arena.Size.X, Arena.Size.Z) * 0.5
	local horizontalDistance = Vector2.new(localPosition.X, localPosition.Z).Magnitude
	local heightAllowance = type(heightAllowanceStuds) == "number" and math.max(0, heightAllowanceStuds) or 0
	return horizontalDistance <= radius
		and math.abs(localPosition.Y) <= Arena.Size.Y * 0.5 + heightAllowance
end

local function getPlanarDirection(vector: Vector3, fallback: Vector3): Vector3
	local planar = Vector3.new(vector.X, 0, vector.Z)
	return if planar.Magnitude > EPSILON then planar.Unit else fallback
end

local function getEquippedMeleeTool(character: Model): (Tool?, any?)
	local equippedTool: Tool? = nil
	local equippedProfile = nil
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local _, profile = WeaponsData.GetProfile(child)
			if profile and profile.combatKind == "Melee" then
				if equippedTool then
					return nil, nil
				end
				equippedTool = child
				equippedProfile = profile
			end
		end
	end
	return equippedTool, equippedProfile
end

local function sendRecovered(target: Player, character: Model, hitId: number)
	if recoveryTokens[target.UserId] ~= hitId then
		return
	end

	recoveryTokens[target.UserId] = nil
	recoveryUntil[target.UserId] = nil
	if CombatVfxEvent and target.Parent == Players and target.Character == character then
		CombatVfxEvent:FireClient(target, "Recovered", {
			character = character,
		})
	end
end

local function applyImpact(
	attacker: Player,
	attackerRoot: BasePart,
	target: Player,
	targetCharacter: Model,
	targetRoot: BasePart,
	profile: any,
	sequence: number
)
	local impact = profile.impact
	local attackerForward = getPlanarDirection(attackerRoot.CFrame.LookVector, Vector3.new(0, 0, -1))
	local direction = getPlanarDirection(targetRoot.Position - attackerRoot.Position, attackerForward)
	local launchVelocity = direction * impact.planarDeltaV + Vector3.yAxis * impact.verticalDeltaV
	local tumbleAxis = Vector3.yAxis:Cross(direction)
	local tumbleSpeed = type(impact.tumbleAngularSpeed) == "number" and math.max(0, impact.tumbleAngularSpeed) or 0
	local angularVelocity = if tumbleAxis.Magnitude > EPSILON
		then tumbleAxis.Unit * tumbleSpeed
		else Vector3.zero
	local maximumReactionSeconds = type(impact.ragdollMaxSeconds) == "number"
		and math.max(0, impact.ragdollMaxSeconds)
		or 0
	local landingRecoverySeconds = type(impact.ragdollLandingRecoverySeconds) == "number"
		and math.max(0, impact.ragdollLandingRecoverySeconds)
		or 0
	local launchDurationSeconds = type(impact.launchControlSeconds) == "number"
		and math.clamp(impact.launchControlSeconds, 0.08, 0.25)
		or 0.1

	local knockedDown = false
	local knockdownToken: number? = nil
	if impact.reactionMode == "Knockdown" and maximumReactionSeconds > 0 then
		knockedDown, knockdownToken = KnockdownUtil.Start(targetCharacter, maximumReactionSeconds)
	end

	nextHitId += 1
	local hitId = nextHitId
	recoveryTokens[target.UserId] = hitId
	recoveryUntil[target.UserId] = os.clock() + maximumReactionSeconds + landingRecoverySeconds

	if CombatVfxEvent then
		CombatVfxEvent:FireClient(target, "ApplyKnockback", {
			character = targetCharacter,
			hitId = hitId,
			launchVelocity = launchVelocity,
			angularVelocity = angularVelocity,
			launchDurationSeconds = launchDurationSeconds,
		})

		local configuredTrailSeconds = profile.vfx and profile.vfx.airTrailSeconds
		local airTrailSeconds = if knockedDown and type(configuredTrailSeconds) == "number"
			then math.max(0, configuredTrailSeconds)
			else 0
		CombatVfxEvent:FireAllClients("Impact", {
			character = targetCharacter,
			config = profile.vfx,
			airTrailSeconds = airTrailSeconds,
			attackerUserId = attacker.UserId,
			sequence = sequence,
		})
	end

	if not knockedDown then
		sendRecovered(target, targetCharacter, hitId)
		return
	end

	KnockdownUtil.StopAfterLanding(
		targetCharacter,
		knockdownToken,
		landingRecoverySeconds,
		function()
			if CombatVfxEvent then
				CombatVfxEvent:FireAllClients("Landed", {
					character = targetCharacter,
				})
			end
		end,
		function()
			sendRecovered(target, targetCharacter, hitId)
		end
	)

	-- Missing the arena can prevent a landing sample. This is only a recovery failsafe.
	task.delay(maximumReactionSeconds + landingRecoverySeconds + 0.05, function()
		KnockdownUtil.Stop(targetCharacter, knockdownToken, true)
		sendRecovered(target, targetCharacter, hitId)
	end)
end

local function handleHitReport(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end

	local sequence = payload.sequence
	local targetUserId = payload.targetUserId
	if type(sequence) ~= "number"
		or sequence % 1 ~= 0
		or sequence < 1
		or sequence > MAX_SEQUENCE
		or type(targetUserId) ~= "number"
		or targetUserId % 1 ~= 0 then
		return
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end

	local attackerCharacter, _, attackerRoot = getAliveCharacter(player)
	local targetCharacter, _, targetRoot = getAliveCharacter(target)
	if not (attackerCharacter and attackerRoot and targetCharacter and targetRoot) then
		return
	end

	local _, profile = getEquippedMeleeTool(attackerCharacter)
	if not profile then
		return
	end

	local now = os.clock()
	if sequence <= (lastHitSequence[player.UserId] or 0)
		or now < (nextHitAt[player.UserId] or 0)
		or now < (recoveryUntil[player.UserId] or 0) then
		return
	end

	if profile.arenaOnly ~= false
		and (not isInsideArena(attackerRoot.Position, profile.arenaHeightAllowanceStuds)
			or not isInsideArena(targetRoot.Position, profile.arenaHeightAllowanceStuds)) then
		return
	end

	local configuredReach = type(profile.target.reachStuds) == "number" and math.max(0, profile.target.reachStuds) or 0
	local configuredTolerance = type(profile.target.serverToleranceStuds) == "number"
		and math.clamp(profile.target.serverToleranceStuds, 0, MAX_SERVER_TOLERANCE_STUDS)
		or 0
	if (targetRoot.Position - attackerRoot.Position).Magnitude > configuredReach + configuredTolerance then
		return
	end

	lastHitSequence[player.UserId] = sequence
	nextHitAt[player.UserId] = now + math.max(0.05, profile.swing.cooldownSeconds)
	applyImpact(player, attackerRoot, target, targetCharacter, targetRoot, profile, sequence)
end

local function handleCombatEvent(player: Player, action: string?, payload: any)
	if action == "HitReport" then
		handleHitReport(player, payload)
	end
end

local function clearPlayerCombatState(player: Player, character: Model?)
	nextHitAt[player.UserId] = nil
	lastHitSequence[player.UserId] = nil
	recoveryUntil[player.UserId] = nil
	recoveryTokens[player.UserId] = nil
	if character then
		KnockdownUtil.Stop(character, nil, true)
	end
end

local PlayerCombatService = {}

function PlayerCombatService.Init(context: any)
	WeaponsData = context.Metadata.Weapons
	CombatEvent = context.Remotes.CombatEvent
	CombatVfxEvent = context.Remotes.CombatVfxEvent
	Arena = context.Instances.Arena

	CombatEvent.OnServerEvent:Connect(handleCombatEvent)

	PlayerUtil.OnPlayer(function(player)
		player.CharacterRemoving:Connect(function(character)
			clearPlayerCombatState(player, character)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearPlayerCombatState(player, player.Character)
	end)

	log.info("Initialized")
end

return PlayerCombatService
