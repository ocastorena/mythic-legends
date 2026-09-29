--!strict
-- ServerStorage/Tests/__tests__/ShrineWorkers.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function worker(formId: string): Types.MythlingEntry
	return {
		typeId = formId,
		variantId = "retained_variant",
		claimedAt = 25,
		level = 1,
		xp = 0,
		pendingXp = 0,
	}
end

local function shrine(id: string, shrineId: string, buildSlotId: number): Types.ShrineRecord
	return {
		id = id,
		shrineId = shrineId,
		buildSlotId = buildSlotId,
		level = 1,
		stored = 0,
		progress = 0,
		newWork = 0,
		workerIdsBySlot = {},
	}
end

local function profile(userId: number): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return `station_{userId}`
	end, 0)
	assert(prepared, `[ShrineWorkers.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = userId
	data.mythlings = {
		worker = worker("mythling_0001"),
		replacement = worker("mythling_0003"),
		water = worker("mythling_0004"),
	}
	data.base.shrines = { first = shrine("first", "fire_shrine", 1) }
	return data
end

local function savedShrines(data: Types.PlayerDoc): { [string]: Types.ShrineRecord }
	return (assert(data.base.shrines, "[ShrineWorkers.spec] Expected Shrine map"))
end

local function slots(record: Types.ShrineRecord): { [string]: string }
	return (assert(record.workerIdsBySlot, "[ShrineWorkers.spec] Expected assignment map"))
end

local function assign(
	revision: number,
	token: string,
	workerId: string?,
	slotId: number?,
	shrineInstanceId: string?
): Types.AssignShrineWorkerRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineInstanceId = shrineInstanceId or "first",
		slotId = slotId or 1,
		workerId = workerId or "worker",
	}
end

local function remove(
	revision: number,
	token: string,
	expectedWorkerId: string?,
	slotId: number?,
	shrineInstanceId: string?
): Types.RemoveShrineWorkerRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineInstanceId = shrineInstanceId or "first",
		slotId = slotId or 1,
		expectedWorkerId = expectedWorkerId or "worker",
	}
end

local function fixture(firstProfile: Types.PlayerDoc?, clockOverride: (() -> number)?)
	-- The private bridge only forwards these ownership tokens; public service gates require Players.
	local first = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local second = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
	local profiles: { [Player]: Types.PlayerDoc } = {
		[first] = firstProfile or profile(1001),
		[second] = profile(1002),
	}
	local state = {
		now = 0,
		active = true,
		available = true,
		loseSessionAfterCallback = false,
		inCallback = false,
		clockCalls = 0,
		transactionCalls = 0,
		callbackCalls = 0,
		operations = {} :: { string },
		players = {} :: { Player },
	}
	local dataSource: ShrineWorkers.DataSource = {
		GetLoadedData = function(player: Player): Types.PlayerDoc?
			return if state.available and state.active then profiles[player] else nil
		end,
		Transact = function(player, request, mutate)
			state.transactionCalls += 1
			table.insert(state.operations, request.operation)
			table.insert(state.players, player)
			local data = profiles[player]
			if not data or not state.available then
				return { ok = false, code = "DataUnavailable", revision = 0 }
			end
			return Transactions.Run(data, request, function(draft)
				state.inCallback = true
				state.callbackCalls += 1
				local outcome = mutate(draft)
				state.inCallback = false
				if state.loseSessionAfterCallback then
					state.active = false
				end
				return outcome
			end, function()
				return state.active
			end)
		end,
	}
	local api = ShrineWorkers.new(dataSource, function(): number
		state.clockCalls += 1
		assert(state.inCallback, "[ShrineWorkers.spec] Clock must be sampled inside transaction")
		return if clockOverride then clockOverride() else state.now
	end)
	return { first = first, second = second, profiles = profiles, state = state, api = api }
end

describe("ShrineWorkers", function()
	it("assigns and removes matching workers for all six real launch elements", function()
		for _, content in
			{
				{ "fire_shrine", "mythling_0001" },
				{ "water_shrine", "mythling_0004" },
				{ "earth_shrine", "mythling_0007" },
				{ "air_shrine", "mythling_0010" },
				{ "light_shrine", "mythling_0013" },
				{ "dark_shrine", "mythling_0016" },
			}
		do
			local data = profile(1001)
			data.mythlings.worker.typeId = content[2]
			savedShrines(data).first.shrineId = content[1]
			local f = fixture(data)
			f.state.now = 10
			expect(f.api.Assign(f.first, assign(0, "assign"))).toEqual({
				ok = true,
				revision = 1,
				values = {
					shrineInstanceId = "first",
					slotId = 1,
					workerId = "worker",
					settledAt = 10,
				},
			})
			expect(slots(savedShrines(data).first)).toEqual({ ["1"] = "worker" })
			expect(data.mythlings.worker.xp).toBe(0)
			f.state.now = 11
			expect(f.api.Remove(f.first, remove(1, "remove"))).toEqual({
				ok = true,
				revision = 2,
				values = {
					shrineInstanceId = "first",
					slotId = 1,
					workerId = "worker",
					settledAt = 11,
				},
			})
			expect(slots(savedShrines(data).first)).toEqual({})
			expect(data.mythlings.worker.xp).toBe(1)
			expect(savedShrines(data).first.progress).toBeCloseTo(12 / 3_600)
			expect(f.state.operations).toEqual({
				"Base.AssignShrineWorker",
				"Base.RemoveShrineWorker",
			})
			expect(f.state.transactionCalls).toBe(2)
			expect(f.state.clockCalls).toBe(2)
		end
	end)

	it("rejects malformed envelopes without a transaction or clock sample", function()
		for _, action in { "Assign", "Remove" } do
			local valid = if action == "Assign" then assign(0, "invalid") else remove(0, "invalid")
			for _, field in
				{
					"requestId",
					"expectedRevision",
					"shrineInstanceId",
					"slotId",
					if action == "Assign" then "workerId" else "expectedWorkerId",
				}
			do
				local f = fixture()
				-- Deliberately malformed dynamic request boundary, not a saved-state cast.
				local raw: { [string]: any } = copy(valid) :: any
				raw[field] = nil
				local result = if action == "Assign"
					then f.api.Assign(f.first, raw :: any)
					else f.api.Remove(f.first, raw :: any)
				expect(result).toEqual({ ok = false, code = "InvalidRequest", revision = 0 })
				expect(f.state.transactionCalls).toBe(0)
				expect(f.state.clockCalls).toBe(0)
			end
			for _, extra in { "now", "ledger", "metadata", "player", "unexpected" } do
				local f = fixture()
				local raw: { [string]: any } = copy(valid) :: any
				raw[extra] = 1
				local result = if action == "Assign"
					then f.api.Assign(f.first, raw :: any)
					else f.api.Remove(f.first, raw :: any)
				expect(result.code).toBe("InvalidRequest")
				expect(f.state.transactionCalls).toBe(0)
			end
		end
		for _, slotId in { 0, -1, 1.5, math.huge, 0 / 0 } do
			local f = fixture()
			local request = assign(0, "bad-slot")
			request.slotId = slotId
			expect(f.api.Assign(f.first, request).code).toBe("InvalidRequest")
			expect(f.state.transactionCalls).toBe(0)
		end
	end)

	it("requires an available active profile without trying to load it", function()
		for _, stateKey in { "available", "active" } do
			local f = fixture()
			if stateKey == "available" then
				f.state.available = false
			else
				f.state.active = false
			end
			local before = copy(f.profiles[f.first])
			expect(f.api.Assign(f.first, assign(0, "unavailable"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.api.Remove(f.first, remove(0, "unavailable"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	for _, case in
		{
			{
				workerId = "worker",
				shrineInstanceId = "not_owned",
				slotId = 1,
				code = "ShrineNotOwned",
			},
			{
				workerId = "not_owned",
				shrineInstanceId = "first",
				slotId = 1,
				code = "WorkerNotOwned",
			},
			{ workerId = "worker", shrineInstanceId = "first", slotId = 2, code = "InvalidSlot" },
			{
				workerId = "water",
				shrineInstanceId = "first",
				slotId = 1,
				code = "ElementMismatch",
			},
		}
	do
		it(`rejects {case.code} without settling or assigning`, function()
			local f = fixture()
			f.state.now = 100
			local before = gameplay(f.profiles[f.first])
			local result = f.api.Assign(
				f.first,
				assign(0, "reject", case.workerId, case.slotId, case.shrineInstanceId)
			)
			expect(result).toEqual({ ok = false, code = case.code, revision = 1 })
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end)
	end

	it("never automatically moves or replaces assigned workers", function()
		local data = profile(1001)
		savedShrines(data).second = shrine("second", "fire_shrine", 2)
		slots(savedShrines(data).first)["1"] = "worker"
		local f = fixture(data)
		local before = gameplay(data)
		f.state.now = 100
		expect(f.api.Assign(f.first, assign(0, "same")).code).toBe("WorkerAlreadyAssigned")
		expect(f.api.Assign(f.first, assign(1, "move", "worker", 1, "second")).code).toBe(
			"WorkerAlreadyAssigned"
		)
		expect(f.api.Assign(f.first, assign(2, "replace", "replacement")).code).toBe("SlotOccupied")
		expect(gameplay(data)).toEqual(before)
	end)

	it("requires the selected removal's current occupant, including for empty slots", function()
		local f = fixture()
		local data = f.profiles[f.first]
		slots(savedShrines(data).first)["1"] = "worker"
		local before = gameplay(data)
		expect(f.api.Remove(f.first, remove(0, "wrong", "replacement")).code).toBe(
			"AssignmentChanged"
		)
		expect(gameplay(data)).toEqual(before)
		expect(f.api.Remove(f.first, remove(1, "right")).ok).toBe(true)
		local after = gameplay(data)
		expect(f.api.Remove(f.first, remove(2, "empty")).code).toBe("AssignmentChanged")
		expect(gameplay(data)).toEqual(after)
		expect(data.mythlings.worker).toEqual(before.mythlings.worker)
	end)

	it(
		"preserves numbered gaps and live record identities through assignment and removal",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local record = savedShrines(data).first
			record.level = 3
			data.mythlings.third = worker("mythling_0002")
			slots(record)["1"] = "worker"
			slots(record)["3"] = "third"
			local base, records, assignments, owned, firstWorker, clock =
				data.base,
				savedShrines(data),
				slots(record),
				data.mythlings,
				data.mythlings.worker,
				data.productionClock
			expect(f.api.Assign(f.first, assign(0, "middle", "replacement", 2)).ok).toBe(true)
			expect(f.api.Remove(f.first, remove(1, "first")).ok).toBe(true)
			expect(slots(record)).toEqual({ ["2"] = "replacement", ["3"] = "third" })
			expect(copy(slots(record))).toEqual({ ["2"] = "replacement", ["3"] = "third" })
			expect(data.base).toBe(base)
			expect(savedShrines(data)).toBe(records)
			expect(savedShrines(data).first).toBe(record)
			expect(slots(record)).toBe(assignments)
			expect(data.mythlings).toBe(owned)
			expect(data.mythlings.worker).toBe(firstWorker)
			expect(data.productionClock).toBe(clock)
		end
	)

	it(
		"retains each worker's fractional work and XP when changing workers within one batch",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			expect(f.api.Assign(f.first, assign(0, "common")).ok).toBe(true)
			f.state.now = 0.25
			expect(f.api.Remove(f.first, remove(1, "remove-common")).ok).toBe(true)
			expect(data.mythlings.worker.pendingXp).toBe(0.25)
			expect(savedShrines(data).first.newWork).toBeCloseTo(12 * 0.25 / 3_600)
			f.state.now = 0.5
			expect(f.api.Assign(f.first, assign(2, "epic", "replacement")).ok).toBe(true)
			f.state.now = 1
			expect(f.api.Remove(f.first, remove(3, "remove-epic", "replacement")).ok).toBe(true)
			expect(data.mythlings.worker.xp).toBe(0.25)
			expect(data.mythlings.replacement.xp).toBe(0.5)
			expect(data.mythlings.worker.pendingXp).toBe(0)
			expect(data.mythlings.replacement.pendingXp).toBe(0)
			expect(savedShrines(data).first.progress).toBeCloseTo((12 * 0.25 + 32 * 0.5) / 3_600)
			expect(savedShrines(data).first.newWork).toBe(0)
			expect(savedShrines(data).first.stored).toBe(0)
		end
	)

	it("flushes an unassigned worker's earned XP but never catches up an empty interval", function()
		local f = fixture()
		local data = f.profiles[f.first]
		expect(f.api.Assign(f.first, assign(0, "start")).ok).toBe(true)
		f.state.now = 0.25
		expect(f.api.Remove(f.first, remove(1, "pause")).ok).toBe(true)
		f.state.now = 100
		expect(f.api.Assign(f.first, assign(2, "resume")).ok).toBe(true)
		expect(data.mythlings.worker.xp).toBe(0.25)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(savedShrines(data).first.progress).toBeCloseTo(12 * 0.25 / 3_600)
		f.state.now = 101
		expect(f.api.Remove(f.first, remove(3, "stop")).ok).toBe(true)
		expect(data.mythlings.worker.xp).toBe(1.25)
		expect(savedShrines(data).first.progress).toBeCloseTo(12 * 1.25 / 3_600)
	end)

	it("allows roster changes at full storage without earning paused output or XP", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.stored = 300
		slots(record)["1"] = "worker"
		f.state.now = 1_000
		expect(f.api.Remove(f.first, remove(0, "full-remove")).ok).toBe(true)
		expect(f.api.Assign(f.first, assign(1, "full-assign", "replacement")).ok).toBe(true)
		f.state.now = 2_000
		expect(f.api.Remove(f.first, remove(2, "full-remove-epic", "replacement")).ok).toBe(true)
		expect(record.stored).toBe(300)
		expect(record.progress).toBe(0)
		expect(record.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.replacement.xp).toBe(0)
	end)

	it(
		"settles the filling batch once and excludes later full-storage time before removal",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local record = savedShrines(data).first
			record.stored = 299
			record.progress = 0.999
			slots(record)["1"] = "worker"
			f.state.now = 300
			expect(f.api.Remove(f.first, remove(0, "fills")).ok).toBe(true)
			expect(record.stored).toBe(300)
			expect(record.progress).toBe(0)
			expect(record.newWork).toBe(0)
			expect(data.mythlings.worker.xp).toBe(1)
			expect(data.mythlings.worker.pendingXp).toBe(0)
		end
	)

	it(
		"permits explicit remove-then-reassign at the same timestamp without duplicate earnings",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			savedShrines(data).second = shrine("second", "fire_shrine", 2)
			slots(savedShrines(data).first)["1"] = "worker"
			f.state.now = 1
			expect(f.api.Remove(f.first, remove(0, "remove")).ok).toBe(true)
			expect(f.api.Assign(f.first, assign(1, "move", "worker", 1, "second")).ok).toBe(true)
			expect(f.api.Remove(f.first, remove(2, "remove-again", "worker", 1, "second")).ok).toBe(
				true
			)
			expect(data.mythlings.worker.xp).toBe(1)
			expect(savedShrines(data).first.progress).toBeCloseTo(12 / 3_600)
			expect(savedShrines(data).second.progress).toBe(0)
			expect(savedShrines(data).second.newWork).toBe(0)
		end
	)

	it("replays successful receipts without sampling time or duplicating the mutation", function()
		local f = fixture()
		local request = assign(0, "retry")
		f.state.now = 0.25
		local result = f.api.Assign(f.first, request)
		local after = copy(f.profiles[f.first])
		f.state.now = 500
		expect(f.api.Assign(f.first, request)).toEqual({
			ok = true,
			revision = result.revision,
			values = result.values,
			replayed = true,
		})
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.callbackCalls).toBe(1)
	end)

	it("binds receipt signatures to every selection and the operation", function()
		local f = fixture()
		local request = assign(0, "binding")
		expect(f.api.Assign(f.first, request).ok).toBe(true)
		local after = copy(f.profiles[f.first])
		for _, changed in
			{
				assign(0, "binding", "replacement"),
				assign(0, "binding", "worker", 2),
				assign(0, "binding", "worker", 1, "another"),
			}
		do
			expect(f.api.Assign(f.first, changed).code).toBe("RequestConflict")
		end
		expect(f.api.Remove(f.first, remove(0, "binding")).code).toBe("RequestConflict")
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
	end)

	it("rejects stale revisions and malformed revision-bound IDs before the callback", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		expect(f.api.Assign(f.first, assign(1, "future")).code).toBe("StaleRevision")
		local malformed = assign(0, "wrong-prefix")
		malformed.requestId = "7:wrong-prefix"
		expect(f.api.Assign(f.first, malformed).code).toBe("InvalidTransaction")
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(0)
	end)

	it(
		"replays rejected decisions even after the originally occupied slot becomes empty",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			slots(savedShrines(data).first)["1"] = "worker"
			local request = assign(0, "occupied", "replacement")
			expect(f.api.Assign(f.first, request).code).toBe("SlotOccupied")
			expect(f.api.Remove(f.first, remove(1, "free-slot")).ok).toBe(true)
			local after = copy(data)
			expect(f.api.Assign(f.first, request)).toEqual({
				ok = false,
				code = "SlotOccupied",
				revision = 1,
				replayed = true,
			})
			expect(data).toEqual(after)
			expect(f.state.clockCalls).toBe(2)
		end
	)

	it("preserves receipts and pending credit across a serialized continuation", function()
		local f = fixture()
		expect(f.api.Assign(f.first, assign(0, "start")).ok).toBe(true)
		f.state.now = 0.25
		local request = remove(1, "pause")
		local result = f.api.Remove(f.first, request)
		local restored = fixture(copy(f.profiles[f.first]))
		restored.state.now = 1
		expect(restored.api.Remove(restored.first, request)).toEqual({
			ok = true,
			revision = 2,
			values = result.values,
			replayed = true,
		})
		expect(restored.state.clockCalls).toBe(0)
		expect(restored.api.Assign(restored.first, assign(2, "resume")).ok).toBe(true)
		local data = restored.profiles[restored.first]
		expect(data.mythlings.worker.xp).toBe(0.25)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(savedShrines(data).first.progress).toBeCloseTo(12 * 0.25 / 3_600)
	end)

	it(
		"uses only the selected player's ownership, clock, revision, and receipt namespace",
		function()
			local f = fixture()
			local secondBefore = copy(f.profiles[f.second])
			local request = assign(0, "shared-token")
			expect(f.api.Assign(f.first, request).ok).toBe(true)
			expect(f.profiles[f.second]).toEqual(secondBefore)
			local firstAfter = copy(f.profiles[f.first])
			f.state.now = 1
			local result = f.api.Assign(f.second, request)
			expect(result.ok).toBe(true)
			expect(result.replayed).toBeNil()
			expect(f.profiles[f.first]).toEqual(firstAfter)
			expect(f.state.players).toEqual({ f.first, f.second })
		end
	)

	it("rolls back settlement and assignment together if the active session is lost", function()
		local f = fixture()
		local data = f.profiles[f.first]
		slots(savedShrines(data).first)["1"] = "worker"
		local before = copy(data)
		f.state.now = 300
		f.state.loseSessionAfterCallback = true
		expect(f.api.Remove(f.first, remove(0, "lost-session"))).toEqual({
			ok = false,
			code = "DataUnavailable",
			revision = 0,
		})
		expect(data).toEqual(before)
		expect(f.state.clockCalls).toBe(1)
	end)

	for _, timestamp in { -1, math.huge, 0 / 0 } do
		it(
			`rejects invalid sampled time {tostring(timestamp)} without changing gameplay`,
			function()
				local f = fixture()
				f.state.now = timestamp
				local before = gameplay(f.profiles[f.first])
				local result = f.api.Assign(f.first, assign(0, "invalid-clock"))
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(gameplay(f.profiles[f.first])).toEqual(before)
			end
		)
	end

	it("rejects backdated changes without moving the saved cursor backwards", function()
		local f = fixture()
		f.state.now = 10
		expect(f.api.Assign(f.first, assign(0, "start")).ok).toBe(true)
		local before = gameplay(f.profiles[f.first])
		f.state.now = 9
		expect(f.api.Remove(f.first, remove(1, "backdated")).code).toBe("BackdatedChange")
		expect(gameplay(f.profiles[f.first])).toEqual(before)
	end)

	local failingClocks: { { code: string, clock: () -> number } } = {
		{
			code = "MutationFailed",
			clock = function(): number
				error("intentional failure")
			end,
		},
		{
			code = "MutationYielded",
			clock = function(): number
				coroutine.yield()
				return 1
			end,
		},
	}
	for _, case in failingClocks do
		it(`rolls back {case.code} clocks without a receipt or worker change`, function()
			local f = fixture(nil, case.clock)
			local before = copy(f.profiles[f.first])
			expect(f.api.Assign(f.first, assign(0, "clock-failure"))).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end)
	end

	it(
		"rejects incomplete progression, invalid Base state, and competing legacy assignment",
		function()
			for _, failure in { "progression", "base", "legacy" } do
				local f = fixture()
				local data = f.profiles[f.first]
				if failure == "progression" then
					data.mythlings.worker.pendingXp = nil
				elseif failure == "base" then
					data.base.buildSlotUpgrades = -1
				else
					data.mythlings.worker.standId = 1
				end
				local before = gameplay(data)
				f.state.now = 100
				local result = f.api.Assign(f.first, assign(0, "invalid-state"))
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"fails closed for unknown selected or assigned forms without losing earned credit",
		function()
			for _, stateName in { "selected", "assigned", "pending" } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.mythlings.worker.typeId = "unknown_form"
				if stateName == "assigned" then
					slots(savedShrines(data).first)["1"] = "worker"
				elseif stateName == "pending" then
					data.mythlings.worker.pendingXp = 0.25
				end
				local before = gameplay(data)
				f.state.now = 100
				local result = if stateName == "assigned"
					then f.api.Remove(f.first, remove(0, "unknown"))
					else f.api.Assign(f.first, assign(0, "unknown"))
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"preserves unrelated saved state and legacy attributes without adding mirrored assignment",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire = { total = 17 }
			data.base.stands["1"] = {
				production = {
					lastAccruedAt = 10,
					materials = { fire = { stored = 4, progress = 0.5 } },
				},
			}
			data.mythlings.legacy =
				{ typeId = "prototype_form", variantId = "old", claimedAt = 9, standId = 1 }
			-- Historical extension fields are opaque save data, not part of new acquisition defaults.
			local legacyFields = data.mythlings.worker :: any
			legacyFields.luck = 77
			legacyFields.traitIds = { "insomniac", "lucky" }
			legacyFields.custom = { note = "retained" }
			local before = gameplay(data)
			local material, station, stands, legacy =
				data.materials.fire,
				data.base.craftingStation,
				data.base.stands,
				data.mythlings.legacy
			f.state.now = 0.25
			expect(f.api.Assign(f.first, assign(0, "preserve")).ok).toBe(true)
			local expected = copy(before)
			slots(savedShrines(expected).first)["1"] = "worker"
			assert(expected.productionClock).lastAccruedAt = 0.25
			expect(gameplay(data)).toEqual(expected)
			expect(data.materials.fire).toBe(material)
			expect(data.base.craftingStation).toBe(station)
			expect(data.base.stands).toBe(stands)
			expect(data.mythlings.legacy).toBe(legacy)
		end
	)
end)
