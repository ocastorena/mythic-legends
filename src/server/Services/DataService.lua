-- ServerScriptService/Services/DataService
--
-- Notes:
-- - Uses UpdateAsync behind a small retry helper (pcall + backoff) per Roblox guidance.
-- - Saves on PlayerRemoving and BindToClose. (Don’t yield long in those hooks.)
-- - No autosave loop by design.

-- schema example
-- {
--     version = 1.0, -- must match SCHEMA_VERSION below
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LogUtil = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("LogUtil"))
local log = LogUtil.For("DataService")

local KEYSPACE = "Mythic_Legends_PlayerDoc_v1"
local STORE = DataStoreService:GetDataStore(KEYSPACE)
local MAX_RETRIES = 3 -- light retry for transient DS errors
local BACKOFF_BASE_SEC = 0.15 -- 0.15, 0.30, 0.60...

-- Current schema version. Bumping this REQUIRES adding a matching MIGRATIONS entry --
-- see the migration notes below.
local SCHEMA_VERSION = 1.0

-- Top-level document schema (add sections as you grow your game)
local DEFAULT_DOC = {
	version = SCHEMA_VERSION,
	profile = {},
	mythlings = {}, -- array of saved mythlings
	resources = {},
	items = {},
	currency = {},
}

-- In-memory cache: uid -> doc table
local _docs: { [number]: any } = {}
local _loading = {}
-- Scratch documents for sessions whose save could not be read; never persisted.
local _volatile: { [number]: any } = {}

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

-- ====== Migrations ======
--
-- Keyed by the version being migrated FROM; each returns the upgraded doc. To add one:
-- bump SCHEMA_VERSION, then add MIGRATIONS[oldVersion] returning a doc at the new
-- version. Migrations run in sequence, so a very old save walks forward one step at a
-- time. Never delete an entry -- players who have not logged in since still need it.
--
-- Example:
--   MIGRATIONS[1.0] = function(doc)
--       doc.flags = doc.flags or {}
--       doc.version = 1.1
--       return doc
--   end
local MIGRATIONS: { [number]: (any) -> any } = {}

-- Fills in any top-level section the document is missing, so adding a section to
-- DEFAULT_DOC does not need a migration of its own.
local function backfillSections(doc)
	for key, value in pairs(DEFAULT_DOC) do
		if doc[key] == nil then
			doc[key] = (type(value) == "table") and deepClone(value) or value
		end
	end
	return doc
end

-- Walks a document up to SCHEMA_VERSION. Returns nil if it cannot be migrated, which the
-- caller must treat as "do not touch this save" rather than "start fresh".
local function migrate(doc, userId: number)
	local guard = 0
	while doc.version ~= SCHEMA_VERSION do
		local step = MIGRATIONS[doc.version]
		if not step then
			log.error(
				`No migration from version {doc.version} to {SCHEMA_VERSION} for userId {userId};`
					.. " refusing to overwrite this save"
			)
			return nil
		end

		local before = doc.version
		doc = step(doc)

		guard += 1
		if doc.version == before or guard > 32 then
			log.error(`Migration from version {before} did not advance for userId {userId}`)
			return nil
		end
	end
	return backfillSections(doc)
end

-- Load (or create default), then cache it.
local function loadPlayerDoc(userId: number)
	local ok, result = withRetry(function()
		return STORE:GetAsync(tostring(userId))
	end)

	if not ok then
		-- Never fall back to a blank document here: SaveNow would then overwrite the real
		-- save with an empty one. Leave the cache unset so this session is read-only.
		log.error(`Load failed for userId {userId}; not caching a document`, result)
		return
	end

	local doc = result
	if not doc then
		_docs[userId] = deepClone(DEFAULT_DOC)
		return
	end

	_docs[userId] = migrate(doc, userId)
end

local function getPlayerDoc(userId)
	if _docs[userId] then
		return _docs[userId]
	end

	if _loading[userId] then
		repeat
			task.wait()
		until not _loading[userId]
	else
		_loading[userId] = true
		loadPlayerDoc(userId) -- sets _docs[userId], or leaves it nil on failure
		_loading[userId] = nil
	end

	if _docs[userId] then
		log.debug(`Loaded document for userId {userId}`)
		return _docs[userId]
	end

	-- Load or migration failed. Hand back a scratch document so gameplay keeps running,
	-- and mark the session read-only so SaveNow cannot clobber the real save with it.
	log.warn(`Serving a volatile document for userId {userId}; changes will NOT be saved`)
	_volatile[userId] = _volatile[userId] or deepClone(DEFAULT_DOC)
	return _volatile[userId]
end

-- ====== Module ======
local DataService = {}

-- DataService owns persistence that other services read during their own Init, so it must
-- come first.
DataService.Priority = 10

-- True when this player's save could not be read and must not be written.
function DataService.IsReadOnly(player: Player): boolean
	return _volatile[player.UserId] ~= nil and _docs[player.UserId] == nil
end

-- Return a named top-level section table; auto-creates if missing.
function DataService.GetSection(player: Player, sectionName: string)
	assert(type(sectionName) == "string" and sectionName ~= "", "sectionName must be a non-empty string")
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
	if not doc then
		-- Either nothing was loaded, or the load failed and the session is volatile.
		return
	end
	local snapshot = deepClone(doc)

	local ok, err = withRetry(function()
		return STORE:UpdateAsync(tostring(userId), function()
			return snapshot
		end)
	end)
	if not ok then
		log.error(`Save failed for userId {userId}`, err)
	end
end

-- Dev utility: clear both persistent and cached storage for a player.
function DataService.WipeAsync(player: Player)
	local userId = player.UserId
	_docs[userId] = deepClone(DEFAULT_DOC) -- reset cache first (so immediate reads are empty)
	_volatile[userId] = nil
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
		_volatile[player.UserId] = nil
	end)

	-- Save all on shutdown (server closes). Keep it quick; Roblox may force close after ~30s.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.SaveNow(player)
		end
	end)

	log.info("Initialized")
end

return DataService
