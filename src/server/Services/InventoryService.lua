-- ServerScriptService/Systems/InventoryService.lua
-- Server-only service that manages a player's Mythling inventory.
-- Persistence is delegated to DataService (authoritative read/write).
--
-- Public API:
--   InventoryService.Init([dataService]) -> ()
--   InventoryService.SaveWonMythling(player, params) -> string mythlingId
--   InventoryService.SetStandIndex(player, mythlingId, standIndex:number) -> boolean
--   InventoryService.RemoveMythling(player, mythlingId) -> boolean
--   InventoryService.ListMythlings(player) -> { {id, typeName, standIndex, claimedAt, thumbnailId?}, ... }
--   InventoryService.GetMythling(player, mythlingId) -> entry? (full server entry)
--
-- Notes:
-- - This module never trusts the client. Call it from server scripts (ClaimService, BaseService, etc.).
-- - Data layout lives under doc.inventory.mythlings (array of entries).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Systems = ServerScriptService:WaitForChild("Systems")

local GetMythlingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GetMythlings")

local Ctx = nil
local InventoryService = {}

-- You can inject DataService via Init(); otherwise we require it here.
local DataService: any = nil

-- ===================== helpers =====================

local function makeId(): string
	return string.format("%d%04x", os.time(), math.random(0, 0xFFFF))
end

-- Extract traits from a captured live model (optional conveniences).
-- Reads Settings/Mutations (NumberValue/StringValue/BoolValue) and Settings/Perks (StringValue/BoolValue)
local function readTraitsFromModel(model: Model): ({ mutations: {any}, perks: {string} })
	local mutations = {}
	local perks = {}

	if not model then
		return { mutations = mutations, perks = perks }
	end

	local settings = model:FindFirstChild("Settings")
	if not settings then
		return { mutations = mutations, perks = perks }
	end

	local muts = settings:FindFirstChild("Mutations")
	if muts and muts:IsA("Folder") then
		for _, child in ipairs(muts:GetChildren()) do
			if child:IsA("NumberValue") then
				table.insert(mutations, { name = child.Name, v = child.Value })
			elseif child:IsA("StringValue") then
				table.insert(mutations, { name = child.Name, v = child.Value })
			elseif child:IsA("BoolValue") then
				table.insert(mutations, { name = child.Name, v = (child.Value == true) })
			end
		end
	end

	local pf = settings:FindFirstChild("Perks")
	if pf and pf:IsA("Folder") then
		for _, child in ipairs(pf:GetChildren()) do
			if child:IsA("StringValue") then
				local val = child.Value
				table.insert(perks, (val ~= "" and val) or child.Name)
			elseif child:IsA("BoolValue") then
				if child.Value then
					table.insert(perks, child.Name)
				end
			end
		end
	end

	return { mutations = mutations, perks = perks }
end

-- ===================== public API =====================

function InventoryService.Init(context)
	Ctx = context
	

	local inventoryEvent = Ctx.Remotes.InventoryEvent
	inventoryEvent.OnServerEvent:Connect(function(player, event, msg)
		if event == "Delete" then
			local result = InventoryService.RemoveMythling(player, msg)
			if result then
				local list = InventoryService.ListMythlings(player)
				Ctx.Remotes.InventoryEvent:FireClient(player, "Update", list)
			end
		end
	end)
	
	print("[InventoryService] Initialized")
end

-- Called by ClaimService when a player wins a Mythling.
-- params:
--   mythlingId (spawn id)  - optional, for analytics/backrefs
--   typeId / typeName      - identify the Mythling kind
--   rarity / variantId     - optional extra tags
--   model                  - optional live model instance (to read traits/seed)
-- returns: new inventory instance id (string)
function InventoryService.SaveWonMythling(player: Player, params: any): string
	print("[InventoryService] SaveWonMythling")
	assert(player and player.UserId, "[InventoryService.SaveWonMythling] invalid player")
	assert(params, "[InventoryService.SaveWonMythling] params required")

	local list = Ctx.Services.DataService.GetSection(player, "mythlings")
	local model: Model? = params.model
	local traits = model and readTraitsFromModel(model)
	local id     = makeId()
	local entry = {
		id          = id,
		displayName = params.displayName,
		typeId      = params.typeId,                                        -- optional
		claimedAt   = os.time(),
		standId     = -1,                                                   -- filled later by BaseService
		rarity      = params.rarity,
		variantId   = params.variantId,
		mutations   = nil
	}

	list[id] = entry
	Ctx.Services.DataService.SaveNow(player)
	return entry.id
end

-- Persist which stand a mythling is displayed on (-1 to clear).
function InventoryService.SetStandIndex(player: Player, mythlingId: string, standIndex: number): boolean
	assert(player and player.UserId, "[InventoryService.SetStandIndex] invalid player")
	assert(type(mythlingId) == "string", "[InventoryService.SetStandIndex] mythlingId must be string")

	local list = Ctx.Services.DataService.GetSection(player, "mythlings")

	list[mythlingId].standIndex = tonumber(standIndex) or -1
	Ctx.Services.DataService.SaveNow(player)
	return true
end

-- Delete an inventory entry by id (used by your side-panel Delete).
function InventoryService.RemoveMythling(player: Player, mythlingId: string): boolean
	assert(player and player.UserId, "[InventoryService.RemoveMythling] invalid player")
	assert(type(mythlingId) == "string", "[InventoryService.RemoveMythling] mythlingId must be string")

	local list = Ctx.Services.DataService.GetSection(player, "mythlings")

	list[mythlingId] = nil
	Ctx.Services.DataService.SaveNow(player)
	return true
end

-- Lightweight list for UI grids (bandwidth-friendly).
-- Each row: { id, typeName, standIndex, claimedAt, thumbnailId? }
function InventoryService.ListMythlings(player: Player): {any}
	assert(player and player.UserId, "[InventoryService.ListMythlings] invalid player")

	local list = Ctx.Services.DataService.GetSection(player, "mythlings")
	return list
end

-- Fetch the full server entry (for systems that need details).
function InventoryService.GetMythling(player: Player, mythlingId: string): any?
	assert(player and player.UserId, "[InventoryService.GetMythling] invalid player")
	assert(type(mythlingId) == "string", "[InventoryService.GetMythling] mythlingId must be string")

	local list = Ctx.Services.DataService.GetSection(player, "mythlings")
	return mythlingId and list[mythlingId] or nil
end


-- Remote functions
GetMythlingsRemote.OnServerInvoke = function(player)
	return InventoryService.ListMythlings(player)
end

return InventoryService
