--!strict
-- ServerStorage/Tests/__tests__/MythlingEvolutionCommand.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local MythlingEvolutionCommand =
	require(ServerScriptService.Services.InventoryService.MythlingEvolutionCommand)
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

local function worker(formId: string, level: number?): Types.MythlingEntry
	return {
		typeId = formId,
		variantId = "retained_variant",
		claimedAt = 25,
		level = level or 6,
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
		stored = 7,
		progress = 0.25,
		newWork = 0,
		workerIdsBySlot = {},
	}
end

local function profile(userId: number): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return `station_{userId}`
	end, 0)
	assert(
		prepared,
		`[MythlingEvolutionCommand.spec] Fixture preparation failed: {tostring(problem)}`
	)
	data.profile.userId = userId
	data.currency.gold = 0
	data.materials = {}
	data.mythlings = { worker = worker("mythling_0001"), other = worker("mythling_0004") }
	local first = shrine("first", "fire_shrine", 1)
	first.workerIdsBySlot = { ["1"] = "worker" }
	local second = shrine("second", "water_shrine", 2)
	second.workerIdsBySlot = { ["1"] = "other" }
	data.base.shrines = { first = first, second = second }
	return data
end

local function savedShrines(data: Types.PlayerDoc): { [string]: Types.ShrineRecord }
	return (assert(data.base.shrines, "[MythlingEvolutionCommand.spec] Expected Shrine map"))
end

local function evolve(
	revision: number,
	token: string,
	formId: string?,
	targetFormId: string?
): Types.EvolveMythlingRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		workerId = "worker",
		expectedFormId = formId or "mythling_0001",
		expectedTargetFormId = targetFormId or "mythling_0002",
	}
end

local function fixture(firstProfile: Types.PlayerDoc?, clockOverride: (() -> number)?)
	-- Private helpers use identity tokens; the public facade checks connected engine Players.
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
	local dataSource: MythlingEvolutionCommand.DataSource = {
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
				local outcome = mutate(draft, state.now)
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
	local api = MythlingEvolutionCommand.new(dataSource, function(): number
		state.clockCalls += 1
		assert(state.inCallback, "[MythlingEvolutionCommand.spec] Clock must be inside transaction")
		return if clockOverride then clockOverride() else state.now
	end)
	return {
		first = first,
		second = second,
		profiles = profiles,
		state = state,
		api = api,
		dataSource = dataSource,
	}
end

describe("MythlingEvolutionCommand", function()
	it("supports both free consecutive evolutions in each of the six launch chains", function()
		for elementIndex, element in { "fire", "water", "earth", "air", "light", "dark" } do
			local data = profile(1001)
			local firstForm = string.format("mythling_%04d", (elementIndex - 1) * 3 + 1)
			local secondForm = string.format("mythling_%04d", (elementIndex - 1) * 3 + 2)
			local finalForm = string.format("mythling_%04d", (elementIndex - 1) * 3 + 3)
			data.mythlings.worker = worker(firstForm, 40)
			data.mythlings.worker.xp = 12.5
			savedShrines(data).first.shrineId = `{element}_shrine`
			local f = fixture(data)
			for revision, selection in { { firstForm, secondForm }, { secondForm, finalForm } } do
				expect(
					f.api.Evolve(
						f.first,
						evolve(revision - 1, "all-chains", selection[1], selection[2])
					)
				).toEqual({
					ok = true,
					revision = revision,
					values = {
						workerId = "worker",
						previousFormId = selection[1],
						formId = selection[2],
						level = 40,
						xp = 12.5,
						settledAt = 0,
					},
				})
				expect(data.mythlings.worker.typeId).toBe(selection[2])
				expect(data.mythlings.worker.level).toBe(40)
				expect(data.mythlings.worker.xp).toBe(12.5)
				expect(savedShrines(data).first.workerIdsBySlot).toEqual({ ["1"] = "worker" })
			end
			expect(data.currency.gold).toBe(0)
			expect(data.materials).toEqual({})
			expect(f.state.operations).toEqual({
				"Inventory.EvolveMythling",
				"Inventory.EvolveMythling",
			})
			expect(f.state.clockCalls).toBe(2)
			expect(f.state.transactionCalls).toBe(2)
			local before = gameplay(data)
			expect(f.api.Evolve(f.first, evolve(2, "final", finalForm, firstForm)).code).toBe(
				"NoEvolution"
			)
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it("settles due XP at the old form before evaluating the evolution threshold", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.mythlings.worker.level = 5
		data.mythlings.worker.xp = 599
		f.state.now = 1
		local result = f.api.Evolve(f.first, evolve(0, "due-xp"))
		expect(result.ok).toBe(true)
		expect(result.values).toEqual({
			workerId = "worker",
			previousFormId = "mythling_0001",
			formId = "mythling_0002",
			level = 6,
			xp = 0,
			settledAt = 1,
		})
		expect(savedShrines(data).first.progress).toBeCloseTo(0.25 + 12 * 1.04 / 3_600, 10)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(data.mythlings.other.xp).toBe(1)
		expect(data.mythlings.other.typeId).toBe("mythling_0004")
		expect(data.productionClock).toEqual({ lastAccruedAt = 1, nextBatchAt = 2 })
	end)

	it(
		"does not grant partial-batch XP early or commit settlement on an ineligible request",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.mythlings.worker.level = 5
			data.mythlings.worker.xp = 599.5
			f.state.now = 0.5
			local before = gameplay(data)
			expect(f.api.Evolve(f.first, evolve(0, "too-early"))).toEqual({
				ok = false,
				code = "LevelTooLow",
				revision = 1,
			})
			expect(gameplay(data)).toEqual(before)
			f.state.now = 1
			expect(f.api.Evolve(f.first, evolve(1, "ready")).ok).toBe(true)
			expect(data.mythlings.worker.level).toBe(6)
			expect(data.mythlings.worker.xp).toBe(0.5)
		end
	)

	it("retains partial old-form output and XP and uses new Yield only after evolution", function()
		local f = fixture()
		local data = f.profiles[f.first]
		f.state.now = 0.5
		expect(f.api.Evolve(f.first, evolve(0, "mid-batch")).ok).toBe(true)
		expect(savedShrines(data).first.stored).toBe(7)
		expect(savedShrines(data).first.progress).toBe(0.25)
		expect(savedShrines(data).first.newWork).toBeCloseTo(0.5 * 12 * 1.05 / 3_600, 10)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.worker.pendingXp).toBe(0.5)
		expect(data.productionClock).toEqual({ lastAccruedAt = 0.5, nextBatchAt = 1 })
		local workers = ShrineWorkers.new(f.dataSource, function()
			return 1
		end)
		expect(workers.Remove(f.first, {
			requestId = "1:remove-after-evolution",
			expectedRevision = 1,
			shrineInstanceId = "first",
			slotId = 1,
			expectedWorkerId = "worker",
		}).ok).toBe(true)
		expect(savedShrines(data).first.progress).toBeCloseTo(
			0.25 + 0.5 * (12 + 18) * 1.05 / 3_600,
			10
		)
		expect(savedShrines(data).first.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0)
	end)

	it("allows eligible assigned evolution at full storage without new XP or output", function()
		local f = fixture()
		local data = f.profiles[f.first]
		savedShrines(data).first.stored = 300
		savedShrines(data).first.progress = 0
		f.state.now = 100
		expect(f.api.Evolve(f.first, evolve(0, "full")).ok).toBe(true)
		expect(data.mythlings.worker.typeId).toBe("mythling_0002")
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(savedShrines(data).first.stored).toBe(300)
		expect(savedShrines(data).first.workerIdsBySlot).toEqual({ ["1"] = "worker" })
		expect(data.mythlings.other.xp).toBe(100)
	end)

	it(
		"settles an unassigned worker's previously earned pending credit without requiring a Shrine",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.base.shrines = {}
			data.mythlings.worker.level = 5
			data.mythlings.worker.xp = 599.5
			data.mythlings.worker.pendingXp = 0.5
			f.state.now = 1
			expect(f.api.Evolve(f.first, evolve(0, "unassigned")).ok).toBe(true)
			expect(data.mythlings.worker.level).toBe(6)
			expect(data.mythlings.worker.xp).toBe(0)
			expect(data.mythlings.worker.pendingXp).toBe(0)
			expect(data.base.shrines).toEqual({})
		end
	)

	it("enforces each configured level gate without charging or spending progression", function()
		for _, selection in
			{ { "mythling_0001", "mythling_0002", 5 }, { "mythling_0002", "mythling_0003", 39 } }
		do
			local f = fixture()
			local data = f.profiles[f.first]
			data.mythlings.worker.typeId = selection[1] :: string
			data.mythlings.worker.level = selection[3] :: number
			local before = gameplay(data)
			expect(
				f.api.Evolve(
					f.first,
					evolve(0, "threshold", selection[1] :: string, selection[2] :: string)
				).code
			).toBe("LevelTooLow")
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it("rejects unowned, stale-form, and stale-target selections atomically", function()
		for _, failure in { "owner", "form", "target" } do
			local f = fixture()
			local request = evolve(0, "stale")
			local expectedCode = "EvolutionTargetChanged"
			if failure == "owner" then
				request.workerId = "not_owned"
				expectedCode = "WorkerNotOwned"
			elseif failure == "form" then
				request.expectedFormId = "mythling_0002"
				expectedCode = "FormChanged"
			else
				request.expectedTargetFormId = "mythling_0005"
			end
			f.state.now = 300
			local before = gameplay(f.profiles[f.first])
			expect(f.api.Evolve(f.first, request)).toEqual({
				ok = false,
				code = expectedCode,
				revision = 1,
			})
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end
	end)

	it("rejects malformed request envelopes before entering a transaction", function()
		local invalidRequests: { any } =
			{ false, 1, "request", setmetatable(evolve(0, "meta"), {}) }
		for _, field in
			{
				"requestId",
				"expectedRevision",
				"workerId",
				"expectedFormId",
				"expectedTargetFormId",
			}
		do
			local raw: { [string]: any } = copy(evolve(0, "missing")) :: any
			raw[field] = nil
			table.insert(invalidRequests, raw)
		end
		for _, field in
			{
				"now",
				"level",
				"xp",
				"player",
				"formId",
				"metadata",
				"signature",
				"operation",
				"luck",
				"traitIds",
			}
		do
			local raw: { [string]: any } = copy(evolve(0, "extra")) :: any
			raw[field] = 1
			table.insert(invalidRequests, raw)
		end
		for _, value in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53, "1" } do
			local raw: any = evolve(0, "revision")
			raw.expectedRevision = value
			table.insert(invalidRequests, raw)
		end
		for _, field in { "requestId", "workerId", "expectedFormId", "expectedTargetFormId" } do
			for _, value in { "", string.rep("x", 129), 10 } do
				local raw: { [string]: any } = copy(evolve(0, "id")) :: any
				raw[field] = value
				table.insert(invalidRequests, raw)
			end
		end
		for _, request in invalidRequests do
			local f = fixture()
			local before = copy(f.profiles[f.first])
			expect(f.api.Evolve(f.first, request)).toEqual({
				ok = false,
				code = "InvalidRequest",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it("requires an already loaded active profile", function()
		for _, failure in { "available", "active" } do
			local f = fixture()
			if failure == "available" then
				f.state.available = false
			else
				f.state.active = false
			end
			local before = copy(f.profiles[f.first])
			expect(f.api.Evolve(f.first, evolve(0, "unavailable"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it("replays a success without evolving twice or resampling time", function()
		local f = fixture()
		f.profiles[f.first].mythlings.worker.level = 40
		f.state.now = 0.5
		local request = evolve(0, "retry")
		local result = f.api.Evolve(f.first, request)
		local after = copy(f.profiles[f.first])
		f.state.now = 500
		expect(f.api.Evolve(f.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.callbackCalls).toBe(1)
	end)

	it("binds every selected identity to the receipt signature", function()
		local f = fixture()
		expect(f.api.Evolve(f.first, evolve(0, "binding")).ok).toBe(true)
		local after = copy(f.profiles[f.first])
		local changes: { [string]: string } = {
			workerId = "other",
			expectedFormId = "mythling_0002",
			expectedTargetFormId = "mythling_0003",
		}
		for field, value in changes do
			local request: any = evolve(0, "binding")
			request[field] = value
			expect(f.api.Evolve(f.first, request).code).toBe("RequestConflict")
		end
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
	end)

	it("does not conflate delimiter-containing identity fields in rejected receipts", function()
		local f = fixture()
		local request = evolve(0, "delimiters", "c", "mythling_0002")
		request.workerId = "a;form=b"
		expect(f.api.Evolve(f.first, request).code).toBe("WorkerNotOwned")
		local after = copy(f.profiles[f.first])
		request.workerId = "a"
		request.expectedFormId = "b;form=c"
		expect(f.api.Evolve(f.first, request).code).toBe("RequestConflict")
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
	end)

	it("rejects stale revisions and mismatched request-ID prefixes before sampling time", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		expect(f.api.Evolve(f.first, evolve(1, "future")).code).toBe("StaleRevision")
		local request = evolve(0, "wrong-prefix")
		request.requestId = "7:wrong-prefix"
		expect(f.api.Evolve(f.first, request).code).toBe("InvalidTransaction")
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(0)
	end)

	it("retains rejection receipts after later XP makes a fresh evolution eligible", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.mythlings.worker.level = 5
		data.mythlings.worker.xp = 599
		local request = evolve(0, "too-young")
		expect(f.api.Evolve(f.first, request).code).toBe("LevelTooLow")
		f.state.now = 1
		expect(f.api.Evolve(f.first, evolve(1, "trained")).ok).toBe(true)
		local after = copy(data)
		expect(f.api.Evolve(f.first, request)).toEqual({
			ok = false,
			code = "LevelTooLow",
			revision = 1,
			replayed = true,
		})
		expect(data).toEqual(after)
		expect(f.state.clockCalls).toBe(2)
	end)

	it("retains changed forms, partial batches, and receipts through JSON continuation", function()
		local f = fixture()
		f.profiles[f.first].mythlings.worker.level = 40
		f.state.now = 0.5
		local request = evolve(0, "before-save")
		local result = f.api.Evolve(f.first, request)
		local restored = fixture(copy(f.profiles[f.first]))
		restored.state.now = 1
		expect(restored.api.Evolve(restored.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		expect(restored.state.clockCalls).toBe(0)
		expect(
			restored.api.Evolve(
				restored.first,
				evolve(1, "continued", "mythling_0002", "mythling_0003")
			).ok
		).toBe(true)
		local data = restored.profiles[restored.first]
		expect(data.mythlings.worker.typeId).toBe("mythling_0003")
		expect(data.mythlings.worker.level).toBe(40)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(savedShrines(data).first.progress).toBeCloseTo(
			0.25 + 0.5 * (12 + 18) * 1.39 / 3_600,
			10
		)
		expect(data.productionClock).toEqual({ lastAccruedAt = 1, nextBatchAt = 2 })
	end)

	it("isolates owned forms, accounting, and receipts to the requesting player", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		local request = evolve(0, "shared-token")
		expect(f.api.Evolve(f.first, request).ok).toBe(true)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		f.state.now = 1
		local result = f.api.Evolve(f.second, request)
		expect(result.ok).toBe(true)
		expect(result.replayed).toBeNil()
		expect(f.profiles[f.first]).toEqual(firstAfter)
		expect(f.profiles[f.second].mythlings.worker.typeId).toBe("mythling_0002")
		expect(f.state.players).toEqual({ f.first, f.second })
	end)

	it(
		"rolls back evolution, accounting, and receipt if the session ends after callback",
		function()
			local f = fixture()
			local before = copy(f.profiles[f.first])
			f.state.now = 300
			f.state.loseSessionAfterCallback = true
			expect(f.api.Evolve(f.first, evolve(0, "lost-session"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.clockCalls).toBe(1)
		end
	)

	for _, timestamp in { -1, math.huge, 0 / 0 } do
		it(`rejects invalid sampled time {tostring(timestamp)} without gameplay changes`, function()
			local f = fixture()
			f.state.now = timestamp
			local before = gameplay(f.profiles[f.first])
			local result = f.api.Evolve(f.first, evolve(0, "bad-clock"))
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end)
	end

	it("rejects backdated evolution without rewinding the accounting cursor", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.productionClock = { lastAccruedAt = 10, nextBatchAt = 11 }
		f.state.now = 9
		local before = gameplay(data)
		expect(f.api.Evolve(f.first, evolve(0, "backdated")).code).toBe("BackdatedChange")
		expect(gameplay(data)).toEqual(before)
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
		it(`rolls back {case.code} clocks without changing forms or receipts`, function()
			local f = fixture(nil, case.clock)
			local before = copy(f.profiles[f.first])
			expect(f.api.Evolve(f.first, evolve(0, "clock-failure"))).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end)
	end

	it("rejects unresolved canonical state without changing gameplay", function()
		for _, failure in
			{ "base", "progression", "legacy", "unknown", "assignment", "clock", "version" }
		do
			local f = fixture()
			local data = f.profiles[f.first]
			if failure == "base" then
				data.base.buildSlotUpgrades = -1
			elseif failure == "progression" then
				data.mythlings.worker.pendingXp = nil
			elseif failure == "legacy" then
				data.mythlings.worker.standId = 1
			elseif failure == "unknown" then
				data.mythlings.worker.typeId = "unknown_form"
			elseif failure == "assignment" then
				savedShrines(data).second.workerIdsBySlot = { ["1"] = "worker" }
			elseif failure == "clock" then
				data.productionClock = nil
			else
				data.version = 1
			end
			f.state.now = 300
			local before = gameplay(data)
			local result = f.api.Evolve(f.first, evolve(0, "invalid-state"))
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it("does not reinterpret an unassigned opaque prototype as a canonical form", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.mythlings.worker =
			{ typeId = "prototype_form", variantId = "old", claimedAt = 9, standId = 1 }
		savedShrines(data).first.workerIdsBySlot = {}
		local before = gameplay(data)
		expect(
			f.api.Evolve(f.first, evolve(0, "prototype", "prototype_form", "mythling_0001")).code
		).toBe("WorkerNotOwned")
		expect(gameplay(data)).toEqual(before)
	end)

	it(
		"preserves owned identity, inactive Luck and Traits, unrelated content, and purchased state",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire = { total = 17 }
			data.currency.gold = 8_000
			data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 0 }
			data.base.buildSlotUpgrades = 1
			data.craftingJobs = {
				active = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
				},
			}
			data.base.stands["1"] = {
				production = {
					lastAccruedAt = 10,
					materials = { fire = { stored = 4, progress = 0.5 } },
				},
			}
			data.mythlings.legacy =
				{ typeId = "prototype_form", variantId = "old", claimedAt = 9, standId = 1 }
			local legacyFields = data.mythlings.worker :: any
			legacyFields.luck = 77
			legacyFields.traitIds = { "insomniac", "lucky" }
			legacyFields.custom = { note = "retained" }
			local before = gameplay(data)
			local base, records, record, assignments, owned, selected, clock, station, jobs =
				data.base,
				savedShrines(data),
				savedShrines(data).first,
				savedShrines(data).first.workerIdsBySlot,
				data.mythlings,
				data.mythlings.worker,
				data.productionClock,
				data.base.craftingStation,
				data.craftingJobs
			expect(f.api.Evolve(f.first, evolve(0, "preserve")).ok).toBe(true)
			local expected = copy(before)
			expected.mythlings.worker.typeId = "mythling_0002"
			expect(gameplay(data)).toEqual(expected)
			expect(data.base).toBe(base)
			expect(savedShrines(data)).toBe(records)
			expect(savedShrines(data).first).toBe(record)
			expect(savedShrines(data).first.workerIdsBySlot).toBe(assignments)
			expect(data.mythlings).toBe(owned)
			expect(data.mythlings.worker).toBe(selected)
			expect(data.productionClock).toBe(clock)
			expect(data.base.craftingStation).toBe(station)
			expect(data.craftingJobs).toBe(jobs)
		end
	)
end)
