-- Server-owned Arena presentation for the Combat Loadout.
--
-- Combat Tools live in the Backpack outside the Arena. Inside it, the server moves one
-- Primary Weapon and one Shield into the character and mounts each to its configured hand.
-- Keeping both Tools in the character also gives PlayerCombatService an authoritative,
-- unambiguous definition of the active loadout.

local ArenaBounds = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ArenaBounds"))

local LoadoutPresentation = {}

local GRIP_NAME = "CombatLoadoutGrip"
local GRIP_ATTRIBUTE = "CombatLoadoutGrip"

local WeaponsData = nil
local Arena: BasePart? = nil
local arenaHeightAllowance = 0

local function getProfile(tool: Tool): any?
	local _, profile = WeaponsData.GetProfile(tool)
	return profile
end

local function isInArena(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and root:IsA("BasePart")
		and ArenaBounds.Contains(Arena, root.Position, arenaHeightAllowance)
end

local function carriedCombatTools(player: Player, character: Model): { Tool }
	local tools = {}
	local function collect(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and WeaponsData.IsCombatTool(child) then
				table.insert(tools, child)
			end
		end
	end

	collect(character)
	collect(player:FindFirstChildOfClass("Backpack"))
	return tools
end

local function destroyExternalGrips(character: Model, handle: BasePart)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("JointInstance")
			and descendant.Part1 == handle
			and not descendant:IsDescendantOf(handle.Parent) then
			descendant:Destroy()
		end
	end
end

local function ensureGrip(character: Model, tool: Tool)
	local handName = WeaponsData.GetHand(tool)
	local hand = handName and character:FindFirstChild(handName)
	local handle = tool:FindFirstChild("Handle")
	if not (hand and hand:IsA("BasePart") and handle and handle:IsA("BasePart")) then
		return
	end

	local existing = hand:FindFirstChild(GRIP_NAME)
	if existing and existing:IsA("Motor6D") and existing.Part1 == handle then
		-- ShieldPoseController owns C1 while the Shield is raising/lowering. Reapplying the
		-- resting Tool grip from this 10 Hz server sync fights that rendered animation and
		-- produces visible snapping.
		return
	end

	destroyExternalGrips(character, handle)
	if existing then
		existing:Destroy()
	end

	local gripAttachment = hand:FindFirstChild(handName == "LeftHand" and "LeftGripAttachment" or "RightGripAttachment")
	local grip = Instance.new("Motor6D")
	grip.Name = GRIP_NAME
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = if gripAttachment and gripAttachment:IsA("Attachment")
		then gripAttachment.CFrame
		else CFrame.identity
	grip.C1 = tool.Grip
	grip:SetAttribute(GRIP_ATTRIBUTE, true)
	grip.Parent = hand
end

local function stowTool(tool: Tool, backpack: Backpack?)
	local handle = tool:FindFirstChild("Handle")
	local character = tool.Parent
	if character and character:IsA("Model") and handle and handle:IsA("BasePart") then
		destroyExternalGrips(character, handle)
	end
	if backpack then
		tool.Parent = backpack
	end
end

function LoadoutPresentation.Configure(weaponsData: any, arena: BasePart)
	WeaponsData = weaponsData
	Arena = arena
	arenaHeightAllowance = 0
	for _, profile in pairs(WeaponsData.Profiles) do
		if type(profile) == "table" and type(profile.arenaHeightAllowanceStuds) == "number" then
			arenaHeightAllowance = math.max(arenaHeightAllowance, profile.arenaHeightAllowanceStuds)
		end
	end
end

function LoadoutPresentation.Sync(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local tools = carriedCombatTools(player, character)
	if not isInArena(character) then
		for _, tool in ipairs(tools) do
			if tool.Parent == character then
				stowTool(tool, backpack)
			end
		end
		player:SetAttribute("CombatLoadoutVisible", false)
		return
	end

	local equippedKinds: { [string]: true } = {}
	for _, tool in ipairs(tools) do
		local profile = getProfile(tool)
		local combatKind = profile and profile.combatKind
		if type(combatKind) == "string" and not equippedKinds[combatKind] then
			equippedKinds[combatKind] = true
			tool.Parent = character
			ensureGrip(character, tool)
		elseif tool.Parent == character then
			stowTool(tool, backpack)
		end
	end

	player:SetAttribute("CombatLoadoutVisible", next(equippedKinds) ~= nil)
end

function LoadoutPresentation.Clear(player: Player, character: Model?)
	if character then
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and WeaponsData.IsCombatTool(child) then
				stowTool(child, backpack)
			end
		end
	end
	player:SetAttribute("CombatLoadoutVisible", false)
end

return LoadoutPresentation
