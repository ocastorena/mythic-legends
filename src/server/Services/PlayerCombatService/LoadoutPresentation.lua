-- Server-owned Arena presentation for the Combat Loadout.
--
-- Combat Tools live in the Backpack outside the Arena. Inside it, the server moves one
-- Primary Weapon and one Shield into the character. Roblox owns the standard Tool grip;
-- authored animations own the character pose.
-- Keeping both Tools in the character also gives PlayerCombatService an authoritative,
-- unambiguous definition of the active loadout.

local ArenaBounds = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ArenaBounds"))

local LoadoutPresentation = {}

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

local function stowTool(tool: Tool, backpack: Backpack?)
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
