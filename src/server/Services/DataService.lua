-- ServerScriptService/Services/DataService
--
-- Notes:
-- - Uses UpdateAsync behind a small retry helper (pcall + backoff) per Roblox guidance.
-- - Tracks every known mutation as dirty, autosaves it, and keeps failed leave saves in
--   memory for another retry while the server remains alive.
-- - Saves on PlayerRemoving and performs a bounded, concurrent final flush on shutdown.

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
local ServerScriptService = game:GetService("ServerScriptService")

local Infrastructure = ServerScriptService:WaitForChild("Infrastructure")
local LogUtil = require(Infrastructure:WaitForChild("LogUtil"))
local log = LogUtil.For("DataService")

local KEYSPACE = "Mythic_Legends_PlayerDoc_v1"
local STORE = DataStoreService:GetDataStore(KEYSPACE)
local MAX_RETRIES = 3
local BACKOFF_BASE_SEC = 0.15 -- 0.15, 0.30, 0.60...
local AUTOSAVE_DELAY_SEC = 120
local AUTOSAVE_TICK_SEC = 10
local FAILED_SAVE_RETRY_SEC = 30
local MAX_SHUTDOWN_CONCURRENCY = 3
local SHUTDOWN_SAVE_TIMEOUT_SEC = 25

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
-- userId -> monotonically increasing revision. A revision changing during a save means
-- another write happened while UpdateAsync yielded, so the document stays queued.
local _dirtyRevisions: { [number]: number } = {}
local _nextSaveAt: { [number]: number } = {}
local _saving: { [number]: boolean } = {}
-- Failed PlayerRemoving saves remain queued until a later retry succeeds or the server
-- closes. This avoids discarding a recoverable in-memory document after a transient error.
local _departed: { [number]: boolean } = {}
local autosaveRunning = false

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

local function markDirtyByUserId(userId: number): boolean
	if not _docs[userId] then
		return false
	end

	local wasDirty = _dirtyRevisions[userId] ~= nil
	_dirtyRevisions[userId] = (_dirtyRevisions[userId] or 0) + 1
	if not wasDirty then
		_nextSaveAt[userId] = os.clock() + AUTOSAVE_DELAY_SEC
	end
	return true
end

local function releaseDepartedDocIfSaved(userId: number)
	if _departed[userId] and not _dirtyRevisions[userId] and not _saving[userId] then
		_docs[userId] = nil
		_volatile[userId] = nil
		_departed[userId] = nil
		_nextSaveAt[userId] = nil
	end
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
		if i < MAX_RETRIES then
			backoff(i)
		end
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
		markDirtyByUserId(userId)
		return
	end

	_docs[userId] = migrate(doc, userId)
end

local function getPlayerDoc(userId)
	if _docs[userId] then
		_departed[userId] = nil
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

-- Saves one cached document. A caller may force a snapshot even when it is not marked
-- dirty; this preserves SaveNow as a safe compatibility escape hatch for future features.
local function saveUser(userId: number, force: boolean): (boolean, any?)
	while _saving[userId] do
		task.wait()
	end

	local doc = _docs[userId]
	if not doc then
		return false, "No persisted document is cached"
	end
	if not force and not _dirtyRevisions[userId] then
		return true
	end

	local revisionAtStart = _dirtyRevisions[userId] or 0
	local snapshot = deepClone(doc)
	_saving[userId] = true

	local ok, err = withRetry(function()
		return STORE:UpdateAsync(tostring(userId), function()
			return snapshot
		end)
	end)

	_saving[userId] = nil

	if not ok then
		_nextSaveAt[userId] = os.clock() + FAILED_SAVE_RETRY_SEC
		log.error(`Save failed for userId {userId}`, err)
		return false, err
	end

	if (_dirtyRevisions[userId] or 0) == revisionAtStart then
		_dirtyRevisions[userId] = nil
		_nextSaveAt[userId] = nil
	else
		-- A write landed while the DataStore call yielded. Queue a quick follow-up rather
		-- than falsely declaring the newer state saved.
		_nextSaveAt[userId] = os.clock() + AUTOSAVE_TICK_SEC
	end

	releaseDepartedDocIfSaved(userId)
	return true
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

-- Marks the player's persisted document for autosave. Feature services must call this
-- immediately after mutating a table returned by GetSection.
function DataService.MarkDirty(player: Player): boolean
	assert(player and player.UserId, "[DataService.MarkDirty] invalid player")
	if DataService.IsReadOnly(player) then
		return false
	end
	return markDirtyByUserId(player.UserId)
end

-- Return a named top-level section table; auto-creates if missing.
function DataService.GetSection(player: Player, sectionName: string)
	assert(type(sectionName) == "string" and sectionName ~= "", "sectionName must be a non-empty string")
	local doc = getPlayerDoc(player.UserId)
	local section = doc[sectionName]
	if type(section) ~= "table" then
		section = {}
		doc[sectionName] = section
		DataService.MarkDirty(player)
	end
	return section
end

-- Save the current cached snapshot immediately. This is used for high-value events such
-- as winning or deleting a Mythling; ordinary writes rely on MarkDirty + autosave.
function DataService.SaveNow(player: Player): boolean
	assert(player and player.UserId, "[DataService.SaveNow] invalid player")
	local ok = saveUser(player.UserId, true)
	return ok
end

-- Dev utility: clear both persistent and cached storage for a player.
function DataService.WipeAsync(player: Player): boolean
	local userId = player.UserId
	while _saving[userId] do
		task.wait()
	end

	_docs[userId] = deepClone(DEFAULT_DOC) -- reset cache first (so immediate reads are empty)
	_volatile[userId] = nil
	_departed[userId] = nil
	markDirtyByUserId(userId)
	local revisionAtStart = _dirtyRevisions[userId] or 0

	local ok, err = withRetry(function()
		return STORE:SetAsync(tostring(userId), deepClone(DEFAULT_DOC))
	end)
	if not ok then
		_nextSaveAt[userId] = os.clock() + FAILED_SAVE_RETRY_SEC
		log.error(`Wipe failed for userId {userId}`, err)
		return false
	end

	if (_dirtyRevisions[userId] or 0) == revisionAtStart then
		_dirtyRevisions[userId] = nil
		_nextSaveAt[userId] = nil
	end
	return true
end

local function startAutosaveLoop()
	task.spawn(function()
		while autosaveRunning do
			task.wait(AUTOSAVE_TICK_SEC)
			if not autosaveRunning then
				break
			end

			local now = os.clock()
			for userId, dueAt in pairs(_nextSaveAt) do
				if dueAt <= now and _docs[userId] and not _saving[userId] then
					saveUser(userId, false)
				end
			end
		end
	end)
end

local function flushOnShutdown()
	local deadline = os.clock() + SHUTDOWN_SAVE_TIMEOUT_SEC
	local userIds = {}
	for userId in pairs(_docs) do
		table.insert(userIds, userId)
	end

	local pending = 0
	local started = 0
	for _, userId in ipairs(userIds) do
		while pending >= MAX_SHUTDOWN_CONCURRENCY and os.clock() < deadline do
			task.wait()
		end
		if os.clock() >= deadline then
			break
		end

		started += 1
		pending += 1
		task.spawn(function()
			saveUser(userId, true)
			pending -= 1
		end)
	end

	while pending > 0 and os.clock() < deadline do
		task.wait()
	end

	if pending > 0 or started < #userIds then
		log.warn(
			`Shutdown save deadline reached; started {started}/{#userIds} saves with {pending} still pending`
		)
	end
end

-- Initialize hooks once; call from a server bootstrapper.
function DataService.Init()
	if autosaveRunning then
		return
	end
	autosaveRunning = true

	-- Save on leave (recommended hook for per-player saves).
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if _docs[userId] then
			if DataService.SaveNow(player) and not _dirtyRevisions[userId] then
				_docs[userId] = nil
				_dirtyRevisions[userId] = nil
				_nextSaveAt[userId] = nil
			else
				_departed[userId] = true
				log.warn(`Player left with an unsaved document for userId {userId}; retry queued`)
			end
		end
		_volatile[userId] = nil
	end)

	-- Roblox allows only a short shutdown window. Save a few documents at once and stop
	-- waiting before the hard limit, rather than silently abandoning the whole queue.
	game:BindToClose(function()
		flushOnShutdown()
	end)

	startAutosaveLoop()
	log.info("Initialized")
end

function DataService.Stop()
	autosaveRunning = false
end

return DataService
