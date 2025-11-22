-- ServerScriptService/Services/DataService
--
-- Notes:
-- - Uses UpdateAsync behind a small retry helper (pcall + backoff) per Roblox guidance.
-- - Saves on PlayerRemoving and BindToClose. (Don’t yield long in those hooks.)
-- - No autosave loop by design.

-- schema example
-- {
--     version = 1.4, -- instead of "_v"
--     profile = {
--         userId = 123,
--         createdAt = 1710000000,
--         lastLoginAt = 1711000000,
--     },
--     currency = {
--         coins = 0,
--         gems = 0,
--         // add more as needed
--     },
--     resources = {
--         crystal = { total = 90 },       -- resourceId matches Resources metadata key
--         essence = { total = 0 },
--     },
--     items = {
--         -- keyed by item instance id if they’re unique; otherwise by itemId with counts
--         -- ["itm_abc123"] = { itemId = "potion_small", quantity = 2 }
--     },
--     mythlings = {
--         ["myth_1763253150c04d"] = {
--             typeId = "dragon",  -- matches Mythlings metadata key
--             variantId = "regular",
--             standId = 1,
--             claimedAt = 1763253150,
--             lastCollectionAt = 1763234322.350362,
--         },
--         -- more...
--     },
--     stands = {
--         -- if you track stand/base state; otherwise drop this
--         -- [1] = { mythlingInstanceId = "myth_1763253150c04d", slotState = "occupied" }
--     },
--     flags = {
--         tutorialCompleted = true,
--     },
-- }

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local KEYSPACE = "Mythic_Legends_PlayerDoc_v1"
local STORE = DataStoreService:GetDataStore(KEYSPACE)
local MAX_RETRIES = 3 -- light retry for transient DS errors
local BACKOFF_BASE_SEC = 0.15 -- 0.15, 0.30, 0.60...
-- Top-level document schema (add sections as you grow your game)
local DEFAULT_DOC = {
	version = 1.0,
	profile = {},
	mythlings = {}, -- array of saved mythlings
	resources = {},
	items = {},
	currency = {},
}

-- In-memory cache: uid -> doc table
local _docs: { [number]: any } = {}
local _loading = {}

-- ====== Utilities ======
local function deepClone(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = (type(v) == "table") and deepClone(v) or v
	end
	return c
end

local function backoff(attempt) -- 1..MAX_RETRIES
	task.wait(BACKOFF_BASE_SEC * (2 ^ (attempt - 1)))
end

local function withRetry(fn)
	local ok, res
	for i = 1, MAX_RETRIES do
		ok, res = pcall(fn)
		if ok then
			return true, res
		end
		backoff(i)
	end
	return false, res
end

-- Load (or create default), then cache it.
local function loadPlayerDoc(userId: number)
	local ok, result = withRetry(function()
		return STORE:GetAsync(tostring(userId))
	end)

	local doc = ok and result or nil
	if doc and doc.version ~= DEFAULT_DOC.version then
		doc = deepClone(DEFAULT_DOC)
	else
		doc = doc or deepClone(DEFAULT_DOC)
	end

	_docs[userId] = doc
end

local function getPlayerDoc(userId)
	if _docs[userId] then
		print("[DataService] From cache:", _docs[userId])
		return _docs[userId]
	end

	if _loading[userId] then
		repeat
			task.wait()
		until not _loading[userId]
		return _docs[userId]
	end

	_loading[userId] = true
	loadPlayerDoc(userId) -- sets _docs[userId]
	_loading[userId] = nil

	print("[DataService] From dataStore:", _docs[userId])
	return _docs[userId]
end

-- ====== Module ======
local DataService = {}

-- Return a named top-level section table; auto-creates if missing.
function DataService.GetSection(player: Player, sectionName: string)
	assert(type(sectionName) == "string" and sectionName ~= "", "sectionName must be a non-empty string")
	print("[DataService] Getting", sectionName)
	local doc = getPlayerDoc(player.UserId)
	local section = doc[sectionName]
	if type(section) ~= "table" then
		section = {}
		doc[sectionName] = section
	end
	return section
end

-- Save the current cached snapshot immediately
function DataService.SaveNow(player: Player)
	local userId = player.UserId
	local doc = _docs[userId]
	print("doc:", doc)
	if not doc then
		return
	end
	local snapshot = deepClone(doc)

	withRetry(function()
		return STORE:UpdateAsync(tostring(userId), function()
			return snapshot
		end)
	end)
end

-- Dev utility: clear both persistent and cached storage for a player.
function DataService.WipeAsync(player: Player)
	local userId = player.UserId
	_docs[userId] = deepClone(DEFAULT_DOC) -- reset cache first (so immediate reads are empty)
	withRetry(function()
		return STORE:SetAsync(tostring(userId), deepClone(DEFAULT_DOC))
	end)
end

-- Initialize hooks once; call from a server bootstrapper.
function DataService.Init()
	-- Save on leave (recommended hook for per-player saves).
	Players.PlayerRemoving:Connect(function(player)
		DataService.SaveNow(player)
		_docs[player.UserId] = nil
	end)

	-- Save all on shutdown (server closes). Keep it quick; Roblox may force close after ~30s.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.SaveNow(player)
		end
	end)

	print("[DataService] Initialized")
end

return DataService
