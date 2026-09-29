--!strict
-- ServerScriptService/Services/ProductionService/ShrineAccounting
-- Inactive bridge from canonical saved state to the detached Shrine engine; no lifecycle wiring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local BaseState = require(ServerScriptService.Shared.BaseState)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)

local ShrineAccounting = {}

local function defaultMetadata(): ShrineAccrual.Metadata
	local metadata: ShrineAccrual.Metadata = { forms = {}, shrines = {} }
	for id, definition in MythlingForms do
		metadata.forms[id] = {
			element = definition.element,
			baseYieldPerHour = definition.baseYieldPerHour,
		}
	end
	for id, definition in Shrines do
		metadata.shrines[id] = {
			element = definition.element,
			materialId = definition.materialId,
			levels = definition.levels,
		}
	end
	return FreezeUtil.DeepFreeze(metadata)
end

local DEFAULT_METADATA = defaultMetadata()

local function isPlain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function snapshot(
	draft: Types.PlayerDoc,
	metadata: ShrineAccrual.Metadata
): (ShrineAccrual.State?, string?)
	if not isPlain(draft) or table.isfrozen(draft) then
		return nil, "InvalidProfileDraft"
	end
	if draft.version ~= PlayerData.schemaVersion then
		return nil, "UnsupportedVersion"
	end
	local base = draft.base
	if
		not isPlain(base)
		or not isPlain(base.shrines)
		or not isPlain(base.craftingStation)
		or not isPlain(base.stands)
		or not isPlain(draft.mythlings)
	then
		return nil, "InvalidBaseState"
	end
	local shrines = base.shrines
	if not shrines then
		return nil, "InvalidBaseState"
	end
	local clock = draft.productionClock
	if clock == nil then
		return nil, "MissingProductionClock"
	end
	if not isPlain(clock) then
		return nil, "InvalidProductionClock"
	end
	if not isPlain(metadata) or not isPlain(metadata.forms) or not isPlain(metadata.shrines) then
		return nil, "InvalidMetadata"
	end
	local state: ShrineAccrual.State = {
		lastAccruedAt = clock.lastAccruedAt,
		nextBatchAt = clock.nextBatchAt,
		shrines = {},
		workers = {},
	}
	local assigned: { [string]: boolean } = {}
	for id, shrine in shrines do
		if not isId(id) or not isPlain(shrine) then
			return nil, "InvalidBaseState"
		end
		local slots = shrine.workerIdsBySlot
		local stored, progress, newWork = shrine.stored, shrine.progress, shrine.newWork
		if
			slots == nil
			or not isPlain(slots)
			or stored == nil
			or progress == nil
			or newWork == nil
		then
			return nil, "InvalidShrineProduction"
		end
		for _, workerId in slots do
			if not isId(workerId) then
				return nil, "InvalidAssignment"
			end
			assigned[workerId] = true
		end
		state.shrines[id] = {
			shrineId = shrine.shrineId,
			level = shrine.level,
			workerIdsBySlot = table.clone(slots),
			stored = stored,
			progress = progress,
			newWork = newWork,
		}
	end
	-- Validate canonical identities, purchased capacity and Station independently of accounting.
	if not BaseState.GetStatus(base) then
		return nil, "InvalidBaseState"
	end
	for id, entry in draft.mythlings do
		if not isId(id) or not isPlain(entry) or not isId(entry.typeId) then
			return nil, "InvalidMythlingRecord"
		end
		if metadata.forms[entry.typeId] == nil then
			-- Opaque prototypes can coexist only when they have no Shrine work to settle.
			-- A missing/nonzero/invalid credit on a participating form is never silently dropped.
			if assigned[id] or (entry.pendingXp ~= nil and entry.pendingXp ~= 0) then
				return nil, "UnresolvedMythlingForm"
			end
			continue
		end
		if entry.standId ~= nil then
			return nil, "LegacyStandConflict"
		end
		local level, xp, pendingXp = entry.level, entry.xp, entry.pendingXp
		if level == nil or xp == nil or pendingXp == nil then
			return nil, "IncompleteMythlingProgression"
		end
		state.workers[id] = {
			formId = entry.typeId,
			level = level,
			xp = xp,
			pendingXp = pendingXp,
		}
	end
	return state, nil
end

-- Use only inside a synchronous DataService.Transact/Update callback on its detached draft.
-- The caller supplies authenticated ownership and server time; this helper neither saves nor
-- publishes. No input defaults, acquisition grants, arbitrary-ledger Apply API, or clock reset.
function ShrineAccounting.SettleToDraft(
	draft: Types.PlayerDoc,
	now: number,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	local definitions = if metadata == nil then DEFAULT_METADATA else metadata
	local state, snapshotError = snapshot(draft, definitions)
	if not state then
		return false, snapshotError
	end
	local problem = ShrineAccrual.Validate(state, now, definitions, production, progression)
	if problem then
		return false, problem
	end
	if now < state.lastAccruedAt then
		return false, "BackdatedChange"
	end
	local settled, accrualError =
		ShrineAccrual.Accrue(state, now, definitions, production, progression)
	if not settled then
		return false, accrualError
	end

	-- Stage shallow replacements. Only numeric accounting fields change; borrowed nested legacy
	-- values and assignment maps are never mutated. Transactions installs the eventual live commit.
	local base = table.clone(draft.base)
	local shrines = table.clone(draft.base.shrines :: { [string]: Types.ShrineRecord })
	base.shrines = shrines
	for id, result in settled.shrines do
		local shrine = table.clone(shrines[id])
		shrine.stored = result.stored
		shrine.progress = result.progress
		shrine.newWork = result.newWork
		shrines[id] = shrine
	end
	local mythlings = table.clone(draft.mythlings)
	for id, result in settled.workers do
		local entry = table.clone(mythlings[id])
		entry.level = result.level
		entry.xp = result.xp
		entry.pendingXp = result.pendingXp
		mythlings[id] = entry
	end
	local clock = table.clone(draft.productionClock :: Types.ProductionClock)
	clock.lastAccruedAt = settled.lastAccruedAt
	clock.nextBatchAt = settled.nextBatchAt

	-- All checks and calculations completed before these non-yielding root writes.
	draft.base = base
	draft.mythlings = mythlings
	draft.productionClock = clock
	return true, nil
end

return table.freeze(ShrineAccounting)
