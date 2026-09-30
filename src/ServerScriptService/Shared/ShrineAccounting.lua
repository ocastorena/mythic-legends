--!strict
-- ServerScriptService/Shared/ShrineAccounting
-- Bridges canonical saved state to the detached Shrine engine inside the caller's transaction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local BaseState = require(ServerScriptService.Shared.BaseState)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local ProductionClockUtil = require(ServerScriptService.Shared.ProductionClockUtil)

local ShrineAccounting = {}

export type AccountingChange = (
	ShrineAccrual.State,
	number,
	ShrineAccrual.Metadata,
	ShrineAccrual.ProductionConfig?,
	ShrineAccrual.ProgressionConfig?
) -> (ShrineAccrual.State?, string?)

export type Snapshot = { state: ShrineAccrual.State, metadata: ShrineAccrual.Metadata }

type ChangeScope =
	{ kind: "Accounting" }
	| { kind: "Assignments" }
	| { kind: "Upgrade", shrineInstanceId: string }
	| { kind: "Dismantle", shrineInstanceId: string }
	| { kind: "Evolution", workerId: string, targetFormId: string }
	| { kind: "Sale", workerId: string }

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
	if not isPlain(draft) then
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
	if not isPlain(clock) or not ProductionClockUtil.ValidateLifecycle(clock) then
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

-- Server-only detached read; this never accrues time or exposes an Apply operation. Consumers
-- must project an explicit allowlist rather than replicate this internal accounting snapshot.
function ShrineAccounting.ReadSnapshot(
	data: Types.PlayerDoc,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (Snapshot?, string?)
	local definitions = if metadata == nil then DEFAULT_METADATA else metadata
	local state, problem = snapshot(data, definitions)
	if not state then
		return nil, problem
	end
	problem =
		ShrineAccrual.Validate(state, state.lastAccruedAt, definitions, production, progression)
	if problem then
		return nil, problem
	end
	FreezeUtil.DeepFreeze(state)
	-- The default metadata is immutable; custom test metadata is borrowed read-only, never frozen.
	local result: Snapshot = { state = state, metadata = definitions }
	local response: Snapshot = result
	table.freeze(result)
	return response, nil
end

-- Use only inside a synchronous DataService.Transact/Update callback on its detached draft.
-- The caller supplies authenticated ownership and server time; this helper neither saves nor
-- publishes. No input defaults, acquisition grants, arbitrary-ledger Apply API, or clock reset.
local function changeToDraft(
	draft: Types.PlayerDoc,
	now: number,
	change: AccountingChange,
	scope: ChangeScope,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	if type(draft) == "table" and table.isfrozen(draft) then
		return false, "InvalidProfileDraft"
	end
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
	local changeAssignments = scope.kind == "Assignments"
	local upgradeShrineId = if scope.kind == "Upgrade" then scope.shrineInstanceId else nil
	local removeShrineId = if scope.kind == "Dismantle" then scope.shrineInstanceId else nil
	local evolveWorkerId = if scope.kind == "Evolution" then scope.workerId else nil
	local removeWorkerId = if scope.kind == "Sale" then scope.workerId else nil
	local targetFormId = if scope.kind == "Evolution" then scope.targetFormId else nil
	local selectedShrineId = upgradeShrineId or removeShrineId
	if selectedShrineId ~= nil and not state.shrines[selectedShrineId] then
		return false, "ShrineNotOwned"
	end
	local selectedWorkerId = evolveWorkerId or removeWorkerId
	if selectedWorkerId ~= nil and not state.workers[selectedWorkerId] then
		return false, "WorkerNotOwned"
	end
	-- Only a fresh, immutable snapshot reaches a trusted synchronous reducer. Never accept a
	-- precomputed ledger from a caller or expose a separate snapshot/apply pair.
	FreezeUtil.DeepFreeze(state)
	local settled, accrualError = change(state, now, definitions, production, progression)
	if not settled then
		return false, accrualError
	end
	problem = ShrineAccrual.Validate(settled, now, definitions, production, progression)
	if problem then
		return false, problem
	end
	if settled.lastAccruedAt ~= now then
		return false, "InvalidAccountingChange"
	end
	-- Each entry point allows only its specific structural change. Never silently discard
	-- grants or an unselected worker/Shrine structural change.
	for id, before in state.shrines do
		local after = settled.shrines[id]
		if id == removeShrineId then
			if after ~= nil then
				return false, "InvalidAccountingChange"
			end
			continue
		end
		local expectedLevel = before.level + (if id == upgradeShrineId then 1 else 0)
		if not after or after.shrineId ~= before.shrineId or after.level ~= expectedLevel then
			return false, "InvalidAccountingChange"
		end
		if not changeAssignments then
			for slot, workerId in before.workerIdsBySlot do
				if after.workerIdsBySlot[slot] ~= workerId then
					return false, "InvalidAccountingChange"
				end
			end
			for slot, workerId in after.workerIdsBySlot do
				if before.workerIdsBySlot[slot] ~= workerId then
					return false, "InvalidAccountingChange"
				end
			end
		end
	end
	for id in settled.shrines do
		if state.shrines[id] == nil then
			return false, "InvalidAccountingChange"
		end
	end
	for id, before in state.workers do
		local after = settled.workers[id]
		if id == removeWorkerId then
			if after ~= nil then
				return false, "InvalidAccountingChange"
			end
			continue
		end
		local expectedFormId = if id == evolveWorkerId then targetFormId else before.formId
		if
			not after
			or after.formId ~= expectedFormId
			or (id == evolveWorkerId and after.formId == before.formId)
		then
			return false, "InvalidAccountingChange"
		end
	end
	for id in settled.workers do
		if state.workers[id] == nil then
			return false, "InvalidAccountingChange"
		end
	end

	-- Stage shallow replacements; borrowed nested legacy values are never mutated.
	-- Transactions installs the eventual live commit while preserving live table identities.
	local base = table.clone(draft.base)
	local shrines = table.clone(draft.base.shrines :: { [string]: Types.ShrineRecord })
	base.shrines = shrines
	if removeShrineId ~= nil then
		shrines[removeShrineId] = nil
	end
	for id, result in settled.shrines do
		local shrine = table.clone(shrines[id])
		shrine.stored = result.stored
		shrine.progress = result.progress
		shrine.newWork = result.newWork
		if id == upgradeShrineId then
			shrine.level = result.level
		end
		if changeAssignments then
			shrine.workerIdsBySlot = table.clone(result.workerIdsBySlot)
		end
		shrines[id] = shrine
	end
	if (upgradeShrineId ~= nil or removeShrineId ~= nil) and not BaseState.GetStatus(base) then
		return false, "InvalidBaseState"
	end
	local mythlings = table.clone(draft.mythlings)
	if removeWorkerId ~= nil then
		mythlings[removeWorkerId] = nil
	end
	for id, result in settled.workers do
		local entry = table.clone(mythlings[id])
		entry.level = result.level
		entry.xp = result.xp
		entry.pendingXp = result.pendingXp
		if id == evolveWorkerId then
			entry.typeId = result.formId
		end
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

function ShrineAccounting.SettleToDraft(
	draft: Types.PlayerDoc,
	now: number,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	return changeToDraft(
		draft,
		now,
		ShrineAccrual.Accrue,
		{ kind = "Accounting" },
		metadata,
		production,
		progression
	)
end

-- Base owns assignment policy. Its trusted pure reducer must settle on the supplied schedule
-- before changing slots. This runs only inside the caller's non-yielding profile transaction.
function ShrineAccounting.ChangeAssignmentsToDraft(
	draft: Types.PlayerDoc,
	now: number,
	change: AccountingChange,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	return changeToDraft(
		draft,
		now,
		change,
		{ kind = "Assignments" },
		metadata,
		production,
		progression
	)
end

-- Production owns collection/capacity policy. Its trusted pure reducer returns the settled
-- accounting with a storage debit; its matching Inventory grant belongs in the SAME transaction.
-- Unlike assignment changes, storage changes must retain every assignment and its slot identity.
function ShrineAccounting.ChangeStorageToDraft(
	draft: Types.PlayerDoc,
	now: number,
	change: AccountingChange,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	return changeToDraft(
		draft,
		now,
		change,
		{ kind = "Accounting" },
		metadata,
		production,
		progression
	)
end

-- Base owns next-level and payment policy. Settle at the old level, then permit exactly one
-- level increase on the selected Shrine, retaining every assignment. Payment belongs in the
-- same transaction; this bridge does not authorize a purchase or expose arbitrary ledger apply.
function ShrineAccounting.ChangeShrineLevelToDraft(
	draft: Types.PlayerDoc,
	now: number,
	shrineInstanceId: string,
	change: AccountingChange,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	if not isId(shrineInstanceId) then
		return false, "InvalidRequest"
	end
	return changeToDraft(
		draft,
		now,
		change,
		{ kind = "Upgrade", shrineInstanceId = shrineInstanceId },
		metadata,
		production,
		progression
	)
end

-- Base owns empty-Shrine eligibility. Retain every worker and its earned/pending XP, remove
-- exactly the selected Shrine, and stage all surviving accounting in this same transaction.
function ShrineAccounting.RemoveShrineToDraft(
	draft: Types.PlayerDoc,
	now: number,
	shrineInstanceId: string,
	change: AccountingChange,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	if not isId(shrineInstanceId) then
		return false, "InvalidRequest"
	end
	return changeToDraft(
		draft,
		now,
		change,
		{ kind = "Dismantle", shrineInstanceId = shrineInstanceId },
		metadata,
		production,
		progression
	)
end

-- Inventory owns evolution links and eligibility. Accept only a different selected target form;
-- every ownership key, other form, Shrine level, and assignment must survive unchanged.
function ShrineAccounting.ChangeWorkerFormToDraft(
	draft: Types.PlayerDoc,
	now: number,
	workerId: string,
	targetFormId: string,
	change: AccountingChange,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	if not isId(workerId) or not isId(targetFormId) then
		return false, "InvalidRequest"
	end
	return changeToDraft(
		draft,
		now,
		change,
		{ kind = "Evolution", workerId = workerId, targetFormId = targetFormId },
		metadata,
		production,
		progression
	)
end

-- Inventory owns sale eligibility and payout. Remove only the selected owned worker; its XP
-- retires with it. Preserve all other workers and Shrine work, and pay in the same transaction.
function ShrineAccounting.RemoveWorkerToDraft(
	draft: Types.PlayerDoc,
	now: number,
	workerId: string,
	change: AccountingChange,
	metadata: ShrineAccrual.Metadata?,
	production: ShrineAccrual.ProductionConfig?,
	progression: ShrineAccrual.ProgressionConfig?
): (boolean, string?)
	if not isId(workerId) then
		return false, "InvalidRequest"
	end
	return changeToDraft(
		draft,
		now,
		change,
		{ kind = "Sale", workerId = workerId },
		metadata,
		production,
		progression
	)
end

return table.freeze(ShrineAccounting)
