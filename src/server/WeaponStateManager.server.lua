-- ServerScriptService/WeaponStateManager
-- Server-owned R15 weapon presentation, stance state, and spatial melee resolution.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfigs = require(ReplicatedStorage:WaitForChild("WeaponConfigs"))
local WeaponAssets = ReplicatedStorage:WaitForChild("WeaponAssets")
local ToggleCombatState = ReplicatedStorage:WaitForChild("ToggleCombatState") :: RemoteEvent
local EquipLoadout = ReplicatedStorage:WaitForChild("EquipLoadout") :: RemoteEvent
local PerformAttack = ReplicatedStorage:WaitForChild("PerformAttack") :: RemoteEvent

local WEAPON_FOLDER_NAME = "EquippedWeapons"
local HITBOX_PADDING = Vector3.new(0.15, 0.15, 0.15)
local MIN_ATTACK_COOLDOWN = 0.1
local MAX_ATTACK_COOLDOWN = 5
local MAX_HITBOX_AXIS = 16
local MAX_KNOCKBACK = 100
local LOADOUT_REQUEST_COOLDOWN = 0.5
local TOGGLE_REQUEST_COOLDOWN = 0.2

local nextAttackAt: { [Player]: number } = {}
local nextLoadoutAt: { [Player]: number } = {}
local nextToggleAt: { [Player]: number } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

-- Studio-only pose helpers remain saved in Workspace for visual authoring, but should
-- never replicate as live gameplay geometry.
for _, authoringName in { "R15WeaponPositioningRig", "WeaponPosePreview" } do
	local authoringInstance = workspace:FindFirstChild(authoringName)
	if authoringInstance then
		authoringInstance:Destroy()
	end
end

local function getStarterLoadout(): (string, string)
	local rightWeapon = ""
	local leftWeapon = ""
	for weaponName, config in WeaponConfigs do
		if config.StarterSlot == "Right" and rightWeapon == "" then
			rightWeapon = weaponName
		elseif config.StarterSlot == "Left" and leftWeapon == "" then
			leftWeapon = weaponName
		end
	end
	return rightWeapon, leftWeapon
end

local function disconnectCharacterConnections(player: Player)
	local connections = characterConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	characterConnections[player] = nil
end

local function getAliveR15Character(player: Player): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil, nil
	end
	return character, humanoid
end

local function getConfig(weaponName: unknown): any?
	if type(weaponName) ~= "string" or #weaponName > 64 then
		return nil
	end
	local config = WeaponConfigs[weaponName]
	return if type(config) == "table" then config else nil
end

local function sanitizeWeaponName(weaponName: unknown): string
	return if getConfig(weaponName) then weaponName :: string else ""
end

local function getWeaponFolder(character: Model): Folder
	local existing = character:FindFirstChild(WEAPON_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = WEAPON_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function clearWeapons(character: Model)
	local folder = character:FindFirstChild(WEAPON_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
	for _, motorName in { "RightHandMotor", "LeftHandMotor", "RightSheathMotor", "LeftSheathMotor" } do
		local motor = character:FindFirstChild(motorName, true)
		if motor and motor:IsA("Motor6D") then
			motor:Destroy()
		end
	end
end

local function prepareWeaponModel(model: Model): boolean
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		warn(`[WeaponStateManager] {model:GetFullName()} has no PrimaryPart`)
		return false
	end
	for _, attachmentName in { "HandGripAttachment", "SheathAttachment" } do
		local attachment = model:FindFirstChild(attachmentName, true)
		if not attachment or not attachment:IsA("Attachment") then
			warn(`[WeaponStateManager] {model:GetFullName()} needs an Attachment named {attachmentName}`)
			return false
		end
	end
	local hitbox = model:FindFirstChild("Hitbox", true)
	if not hitbox or not hitbox:IsA("BasePart") then
		warn(`[WeaponStateManager] {model:GetFullName()} needs a BasePart named Hitbox`)
		return false
	end

	-- A model is treated as one rigid assembly driven by its PrimaryPart Motor6D.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			if descendant ~= primaryPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "WeaponAssemblyWeld"
				weld.Part0 = primaryPart
				weld.Part1 = descendant
				weld.Parent = primaryPart
			end
		end
	end
	return true
end

local function cloneWeapon(character: Model, slot: string, weaponName: string): Model?
	local config = getConfig(weaponName)
	local asset = config and WeaponAssets:FindFirstChild(config.ModelName)
	if not asset or not asset:IsA("Model") then
		warn(`[WeaponStateManager] Missing Model WeaponAssets/{config and config.ModelName or weaponName}`)
		return nil
	end

	local model = asset:Clone()
	model.Name = `{slot}Weapon`
	model:SetAttribute("WeaponName", weaponName)
	model:SetAttribute("WeaponSlot", slot)
	if not prepareWeaponModel(model) then
		model:Destroy()
		return nil
	end
	model.Parent = getWeaponFolder(character)
	return model
end

local function createMotor(name: string, parent: BasePart, part0: BasePart, part1: BasePart, offset: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C1 = offset
	motor.Parent = parent
end

local function getAuthoredOffset(model: Model, attachmentName: string): CFrame?
	local attachment = model:FindFirstChild(attachmentName, true)
	local primaryPart = model.PrimaryPart
	if attachment and attachment:IsA("Attachment") and primaryPart then
		-- Attachments may live on any weapon part; normalize them into PrimaryPart space.
		return primaryPart.CFrame:ToObjectSpace(attachment.WorldCFrame)
	end
	return nil
end

local function attachSlot(character: Model, slot: string, weaponName: string, combatReady: boolean)
	if weaponName == "" then
		return
	end
	local config = getConfig(weaponName)
	local model = cloneWeapon(character, slot, weaponName)
	local primaryPart = model and model.PrimaryPart
	if not config or not model or not primaryPart then
		return
	end

	if combatReady then
		-- Unsheathed: transition ownership from UpperTorso to the matching R15 hand.
		local hand = character:FindFirstChild(`{slot}Hand`)
		local handGripOffset = getAuthoredOffset(model, "HandGripAttachment")
		if hand and hand:IsA("BasePart") and handGripOffset then
			createMotor(
				`{slot}HandMotor`,
				hand,
				hand,
				primaryPart,
				handGripOffset
			)
		else
			model:Destroy()
		end
	else
		-- Sheathed: both weapon assemblies are carried by the R15 UpperTorso.
		local upperTorso = character:FindFirstChild("UpperTorso")
		local sheathOffset = getAuthoredOffset(model, "SheathAttachment")
		if upperTorso and upperTorso:IsA("BasePart") and sheathOffset then
			createMotor(
				`{slot}SheathMotor`,
				upperTorso,
				upperTorso,
				primaryPart,
				sheathOffset
			)
		else
			model:Destroy()
		end
	end
end

local function rebuildAttachments(character: Model)
	clearWeapons(character)
	local combatReady = character:GetAttribute("CombatReady") == true
	attachSlot(character, "Right", character:GetAttribute("RightEquipped") or "", combatReady)
	attachSlot(character, "Left", character:GetAttribute("LeftEquipped") or "", combatReady)
end

local function resolveTargetHumanoid(part: BasePart): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

local function isEnemy(attacker: Player, targetHumanoid: Humanoid): boolean
	local targetCharacter = targetHumanoid.Parent
	local targetPlayer = if targetCharacter and targetCharacter:IsA("Model")
		then Players:GetPlayerFromCharacter(targetCharacter)
		else nil
	if not targetPlayer then
		return true -- NPCs with Humanoids are valid targets.
	end
	if targetPlayer == attacker then
		return false
	end
	return attacker.Neutral or targetPlayer.Neutral or attacker.Team ~= targetPlayer.Team
end

local function applyPositionalHit(attackerCharacter: Model, targetHumanoid: Humanoid, knockback: number)
	local targetCharacter = targetHumanoid.Parent
	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerRoot or not attackerRoot:IsA("BasePart") or not targetRoot or not targetRoot:IsA("BasePart") then
		return
	end
	local delta = targetRoot.Position - attackerRoot.Position
	local direction = if delta.Magnitude > 0.001 then delta.Unit else attackerRoot.CFrame.LookVector
	local impulseVelocity = direction * math.clamp(knockback, 0, MAX_KNOCKBACK) + Vector3.yAxis * 12
	targetRoot:ApplyImpulse(impulseVelocity * targetRoot.AssemblyMass)
end

local function performAttack(player: Player, hand: unknown)
	if hand ~= "Right" and hand ~= "Left" then
		return
	end
	local character = getAliveR15Character(player)
	if not character or character:GetAttribute("CombatReady") ~= true then
		return
	end

	local weaponName = character:GetAttribute(`{hand}Equipped`)
	local config = getConfig(weaponName)
	local folder = character:FindFirstChild(WEAPON_FOLDER_NAME)
	local weapon = folder and folder:FindFirstChild(`{hand}Weapon`)
	if not config or not weapon or not weapon:IsA("Model") or weapon:GetAttribute("WeaponName") ~= weaponName then
		return
	end
	local primaryPart = weapon.PrimaryPart
	if not primaryPart or not character:FindFirstChild(`{hand}HandMotor`, true) then
		return
	end

	local now = os.clock()
	if now < (nextAttackAt[player] or 0) then
		return
	end
	local cooldown = math.clamp(config.AttackCooldown, MIN_ATTACK_COOLDOWN, MAX_ATTACK_COOLDOWN)
	nextAttackAt[player] = now + cooldown

	local hitboxPart = weapon:FindFirstChild("Hitbox", true)
	if not hitboxPart or not hitboxPart:IsA("BasePart") then
		return
	end
	local size = hitboxPart.Size
	size = Vector3.new(
		math.clamp(size.X, 0.1, MAX_HITBOX_AXIS),
		math.clamp(size.Y, 0.1, MAX_HITBOX_AXIS),
		math.clamp(size.Z, 0.1, MAX_HITBOX_AXIS)
	) + HITBOX_PADDING

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.MaxParts = 100

	local hitHumanoids: { [Humanoid]: boolean } = {}
	local hitCount = 0
	local maxTargets = math.clamp(config.MaxTargets, 1, 10)
	for _, part in workspace:GetPartBoundsInBox(hitboxPart.CFrame, size, overlapParams) do
		local humanoid = resolveTargetHumanoid(part)
		if humanoid and not hitHumanoids[humanoid] and humanoid.Parent ~= character and isEnemy(player, humanoid) then
			hitHumanoids[humanoid] = true -- exactly once for this accepted swing
			hitCount += 1
			applyPositionalHit(character, humanoid, config.Knockback)
			if hitCount >= maxTargets then
				break
			end
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	disconnectCharacterConnections(player)
	nextAttackAt[player] = nil
	nextLoadoutAt[player] = nil
	nextToggleAt[player] = nil
	local starterRight, starterLeft = getStarterLoadout()
	character:SetAttribute("RightEquipped", starterRight)
	character:SetAttribute("LeftEquipped", starterLeft)
	character:SetAttribute("CombatReady", false)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(`[WeaponStateManager] {player.Name} must use an R15 character`)
		return
	end
	rebuildAttachments(character)
	characterConnections[player] = {
		humanoid.Died:Connect(function()
			nextAttackAt[player] = nil
			clearWeapons(character)
		end),
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				nextAttackAt[player] = nil
			end
		end),
	}
end

EquipLoadout.OnServerEvent:Connect(function(player: Player, rightWeaponName: unknown, leftWeaponName: unknown)
	local now = os.clock()
	if now < (nextLoadoutAt[player] or 0) then
		return
	end
	nextLoadoutAt[player] = now + LOADOUT_REQUEST_COOLDOWN
	local character = getAliveR15Character(player)
	if not character then
		return
	end
	-- Config membership is the presentation allowlist. Integrate inventory ownership here
	-- before exposing this remote in a progression-enabled build.
	character:SetAttribute("RightEquipped", sanitizeWeaponName(rightWeaponName))
	character:SetAttribute("LeftEquipped", sanitizeWeaponName(leftWeaponName))
	character:SetAttribute("CombatReady", false)
	nextAttackAt[player] = nil
	rebuildAttachments(character)
end)

ToggleCombatState.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if now < (nextToggleAt[player] or 0) then
		return
	end
	nextToggleAt[player] = now + TOGGLE_REQUEST_COOLDOWN
	local character = getAliveR15Character(player)
	if not character then
		return
	end
	character:SetAttribute("CombatReady", character:GetAttribute("CombatReady") ~= true)
	nextAttackAt[player] = nil
	rebuildAttachments(character)
end)

PerformAttack.OnServerEvent:Connect(performAttack)

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.defer(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.defer(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	disconnectCharacterConnections(player)
	nextAttackAt[player] = nil
	nextLoadoutAt[player] = nil
	nextToggleAt[player] = nil
end)
