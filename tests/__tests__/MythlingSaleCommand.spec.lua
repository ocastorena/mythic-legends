--!strict
-- ServerStorage/Tests/__tests__/MythlingSaleCommand.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local MythlingSaleCommand =
	require(ServerScriptService.Services.InventoryService.MythlingSaleCommand)
local MythlingEvolutionCommand =
	require(ServerScriptService.Services.InventoryService.MythlingEvolutionCommand)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local MAX_SAFE_INTEGER = 9007199254740991

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
		level = 6,
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
	assert(prepared, `[MythlingSaleCommand.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = userId
	data.currency.gold = 100
	data.materials = { fire_material = { total = 15 } }
	data.mythlings = { worker = worker("mythling_0001"), other = worker("mythling_0004") }
	local first = shrine("first", "fire_shrine", 1)
	local second = shrine("second", "water_shrine", 2)
	second.workerIdsBySlot = { ["1"] = "other" }
	data.base.shrines = { first = first, second = second }
	return data
end

local function savedShrines(data: Types.PlayerDoc): { [string]: Types.ShrineRecord }
	return (assert(data.base.shrines, "[MythlingSaleCommand.spec] Expected Shrine map"))
end

local function sell(
	revision: number,
	token: string,
	formId: string?,
	gold: number?
): Types.SellMythlingRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		workerId = "worker",
		expectedFormId = formId or "mythling_0001",
		expectedGoldValue = gold or 25,
	}
end

local function fixture(firstProfile: Types.PlayerDoc?, clockOverride: (() -> number)?)
	-- Private commands use identity tokens; the public facade validates connected engine Players.
	local first = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local second = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
	local profiles: { [Player]: Types.PlayerDoc } =
		{ [first] = firstProfile or profile(1001), [second] = profile(1002) }
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
	local dataSource: MythlingSaleCommand.DataSource = {
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
	local api = MythlingSaleCommand.new(dataSource, function(): number
		state.clockCalls += 1
		assert(state.inCallback, "[MythlingSaleCommand.spec] Clock must be inside transaction")
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

describe("MythlingSaleCommand", function()
	it("sells all 18 launch forms for their configured 25, 100, or 300 Gold", function()
		for elementIndex = 1, 6 do
			for stage, gold in { 25, 100, 300 } do
				local f = fixture()
				local data = f.profiles[f.first]
				local formId = string.format("mythling_%04d", (elementIndex - 1) * 3 + stage)
				data.mythlings.worker.typeId = formId
				expect(f.api.Sell(f.first, sell(0, "all-forms", formId, gold))).toEqual({
					ok = true,
					revision = 1,
					values = {
						workerId = "worker",
						formId = formId,
						goldGranted = gold,
						settledAt = 0,
					},
				})
				expect(data.mythlings.worker).toBeNil()
				expect(data.currency.gold).toBe(100 + gold)
				expect(data.mythlings.other.typeId).toBe("mythling_0004")
				expect(f.state.operations).toEqual({ "Inventory.SellMythling" })
				expect(f.state.clockCalls).toBe(1)
				expect(f.state.transactionCalls).toBe(1)
			end
		end
	end)

	it("allows the final owned copy and pays only once across retries and new requests", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.mythlings = { worker = data.mythlings.worker }
		savedShrines(data).second.workerIdsBySlot = {}
		local request = sell(0, "last-copy")
		local result = f.api.Sell(f.first, request)
		expect(result.ok).toBe(true)
		expect(data.mythlings).toEqual({})
		expect(data.currency.gold).toBe(125)
		local after = copy(data)
		f.state.now = 900
		expect(f.api.Sell(f.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		expect(data).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
		expect(f.api.Sell(f.first, sell(1, "sell-again")).code).toBe("WorkerNotOwned")
		expect(gameplay(data)).toEqual(gameplay(after))
	end)

	it(
		"uses the current form regardless of trained levels, acquisition route, or inactive metadata",
		function()
			for _, level in { 1, 50, 100 } do
				for _, route in { "capture", "evolution" } do
					local f = fixture()
					local data = f.profiles[f.first]
					local entry = data.mythlings.worker :: any
					entry.typeId = "mythling_0003"
					entry.level = level
					entry.xp = 19.25
					entry.pendingXp = 0.75
					entry.acquisitionRoute = route
					entry.luck = 99
					entry.traitIds = { "lucky", "insomniac" }
					entry.salePrice = 999_999
					entry.rarity = "Mythical"
					expect(f.api.Sell(f.first, sell(0, "fixed-value", "mythling_0003", 300)).ok).toBe(
						true
					)
					expect(data.currency.gold).toBe(400)
					expect(data.mythlings.worker).toBeNil()
				end
			end
		end
	)

	it("requires explicit unassignment in every slot even when the Shrine is full", function()
		for _, full in { false, true } do
			for slot = 1, 3 do
				local f = fixture()
				local data = f.profiles[f.first]
				local first = savedShrines(data).first
				first.level = 3
				first.workerIdsBySlot = { [tostring(slot)] = "worker" }
				if full then
					first.stored = 3_600
					first.progress = 0
				end
				f.state.now = 100
				local before = gameplay(data)
				expect(f.api.Sell(f.first, sell(0, "assigned")).code).toBe("WorkerAlreadyAssigned")
				expect(gameplay(data)).toEqual(before)
			end
		end
	end)

	it("preserves earned Shrine work while retiring only the sold worker's pending XP", function()
		local f = fixture()
		local data = f.profiles[f.first]
		savedShrines(data).first.workerIdsBySlot = { ["1"] = "worker" }
		local workers = ShrineWorkers.new(f.dataSource, function()
			return f.state.now
		end)
		f.state.now = 0.5
		expect(workers.Remove(f.first, {
			requestId = "0:unassign",
			expectedRevision = 0,
			shrineInstanceId = "first",
			slotId = 1,
			expectedWorkerId = "worker",
		}).ok).toBe(true)
		expect(data.mythlings.worker.pendingXp).toBe(0.5)
		f.state.now = 0.75
		expect(f.api.Sell(f.first, sell(1, "removed-worker")).ok).toBe(true)
		expect(data.mythlings.worker).toBeNil()
		expect(savedShrines(data).first.stored).toBe(7)
		expect(savedShrines(data).first.progress).toBe(0.25)
		expect(savedShrines(data).first.newWork).toBeCloseTo(0.5 * 12 * 1.05 / 3_600, 10)
		expect(data.mythlings.other.xp).toBe(0)
		expect(data.mythlings.other.pendingXp).toBe(0.75)
		expect(data.productionClock).toEqual({ lastAccruedAt = 0.75, nextBatchAt = 1 })
		f.state.now = 1
		expect(workers.Remove(f.first, {
			requestId = "2:other",
			expectedRevision = 2,
			shrineInstanceId = "second",
			slotId = 1,
			expectedWorkerId = "other",
		}).ok).toBe(true)
		expect(data.mythlings.other.xp).toBe(1)
		expect(data.mythlings.other.pendingXp).toBe(0)
		expect(savedShrines(data).first.progress).toBeCloseTo(0.25 + 0.5 * 12 * 1.05 / 3_600, 10)
		expect(savedShrines(data).first.newWork).toBe(0)
		expect(data.currency.gold).toBe(125)
	end)

	it(
		"uses an evolved form's new price and rejects pre-evolution or stale-price selections",
		function()
			local f = fixture()
			local evolution = MythlingEvolutionCommand.new(f.dataSource, function()
				return 0
			end)
			expect(evolution.Evolve(f.first, {
				requestId = "0:evolve",
				expectedRevision = 0,
				workerId = "worker",
				expectedFormId = "mythling_0001",
				expectedTargetFormId = "mythling_0002",
			}).ok).toBe(true)
			local data = f.profiles[f.first]
			local before = gameplay(data)
			expect(f.api.Sell(f.first, sell(1, "old-form")).code).toBe("FormChanged")
			expect(gameplay(data)).toEqual(before)
			expect(f.api.Sell(f.first, sell(2, "old-price", "mythling_0002", 25)).code).toBe(
				"PriceChanged"
			)
			expect(gameplay(data)).toEqual(before)
			expect(f.api.Sell(f.first, sell(3, "current-price", "mythling_0002", 100)).ok).toBe(
				true
			)
			expect(data.currency.gold).toBe(200)
			expect(data.mythlings.worker).toBeNil()
		end
	)

	it("rejects unsafe or malformed Gold without deleting the worker or settling work", function()
		for _, gold in { -1, 0.5, 2 ^ 53, MAX_SAFE_INTEGER - 24 } do
			local f = fixture()
			local data = f.profiles[f.first]
			data.currency.gold = gold
			f.state.now = 300
			local before = gameplay(data)
			expect(f.api.Sell(f.first, sell(0, "unsafe-balance")).code).toBe(
				if gold == MAX_SAFE_INTEGER - 24 then "ArithmeticOverflow" else "InvalidCurrency"
			)
			expect(gameplay(data)).toEqual(before)
		end
		local f = fixture()
		f.profiles[f.first].currency.gold = MAX_SAFE_INTEGER - 25
		expect(f.api.Sell(f.first, sell(0, "safe-limit")).ok).toBe(true)
		expect(f.profiles[f.first].currency.gold).toBe(MAX_SAFE_INTEGER)
	end)

	it("rejects malformed sale envelopes and non-positive or unsafe quoted payouts", function()
		local invalid: { any } = { false, setmetatable(sell(0, "meta"), {}) }
		for _, field in
			{ "requestId", "expectedRevision", "workerId", "expectedFormId", "expectedGoldValue" }
		do
			local raw: any = sell(0, "missing")
			raw[field] = nil
			table.insert(invalid, raw)
		end
		for _, field in
			{ "gold", "now", "player", "metadata", "signature", "operation", "quantity" }
		do
			local raw: any = sell(0, "extra")
			raw[field] = 1
			table.insert(invalid, raw)
		end
		for _, value in { -1, 0, 0.5, math.huge, 0 / 0, 2 ^ 53, "25" } do
			local raw: any = sell(0, "payout")
			raw.expectedGoldValue = value
			table.insert(invalid, raw)
		end
		for _, field in { "requestId", "workerId", "expectedFormId" } do
			local raw: any = sell(0, "id")
			raw[field] = string.rep("x", 129)
			table.insert(invalid, raw)
		end
		for _, request in invalid do
			local f = fixture()
			local before = copy(f.profiles[f.first])
			expect(f.api.Sell(f.first, request)).toEqual({
				ok = false,
				code = "InvalidRequest",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it(
		"binds every selected identity and exact safe-integer quote into receipt signatures",
		function()
			local f = fixture()
			expect(f.api.Sell(f.first, sell(0, "binding")).ok).toBe(true)
			local after = copy(f.profiles[f.first])
			local changes: { [string]: any } =
				{ workerId = "other", expectedFormId = "mythling_0002", expectedGoldValue = 100 }
			for field, value in changes do
				local request: any = sell(0, "binding")
				request[field] = value
				expect(f.api.Sell(f.first, request).code).toBe("RequestConflict")
			end
			expect(f.profiles[f.first]).toEqual(after)
			expect(f.state.clockCalls).toBe(1)
			local large = fixture()
			expect(large.api.Sell(large.first, sell(0, "large", nil, 2 ^ 52)).code).toBe(
				"PriceChanged"
			)
			expect(large.api.Sell(large.first, sell(0, "large", nil, 2 ^ 52 + 1)).code).toBe(
				"RequestConflict"
			)
			expect(large.state.clockCalls).toBe(1)
		end
	)

	it("does not execute unavailable profiles or stale revisions", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		f.state.available = false
		expect(f.api.Sell(f.first, sell(0, "unavailable")).code).toBe("DataUnavailable")
		expect(f.state.transactionCalls).toBe(0)
		f.state.available = true
		expect(f.api.Sell(f.first, sell(1, "stale")).code).toBe("StaleRevision")
		local request = sell(0, "prefix")
		request.requestId = "7:prefix"
		expect(f.api.Sell(f.first, request).code).toBe("InvalidTransaction")
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(0)
	end)

	it("replays an assigned rejection after unassignment and a later successful sale", function()
		local f = fixture()
		local data = f.profiles[f.first]
		savedShrines(data).first.workerIdsBySlot = { ["1"] = "worker" }
		local request = sell(0, "assigned")
		expect(f.api.Sell(f.first, request).code).toBe("WorkerAlreadyAssigned")
		local workers = ShrineWorkers.new(f.dataSource, function()
			return 0
		end)
		expect(workers.Remove(f.first, {
			requestId = "1:unassign",
			expectedRevision = 1,
			shrineInstanceId = "first",
			slotId = 1,
			expectedWorkerId = "worker",
		}).ok).toBe(true)
		expect(f.api.Sell(f.first, sell(2, "sell")).ok).toBe(true)
		local after = copy(data)
		expect(f.api.Sell(f.first, request)).toEqual({
			ok = false,
			code = "WorkerAlreadyAssigned",
			revision = 1,
			replayed = true,
		})
		expect(data).toEqual(after)
		expect(f.state.clockCalls).toBe(2)
	end)

	it(
		"retains payment, removal, partial batches, and retry receipts through JSON continuation",
		function()
			local f = fixture()
			f.state.now = 0.5
			local request = sell(0, "before-save")
			local result = f.api.Sell(f.first, request)
			expect(result.ok).toBe(true)
			local restored = fixture(copy(f.profiles[f.first]))
			restored.state.now = 100
			local before = copy(restored.profiles[restored.first])
			expect(restored.api.Sell(restored.first, request)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.profiles[restored.first]).toEqual(before)
			expect(restored.state.clockCalls).toBe(0)
			expect(before.currency.gold).toBe(125)
			expect(before.mythlings.worker).toBeNil()
			expect(before.mythlings.other.pendingXp).toBe(0.5)
			expect(before.productionClock).toEqual({ lastAccruedAt = 0.5, nextBatchAt = 1 })
			expect(restored.api.Sell(restored.first, sell(1, "not-owned")).code).toBe(
				"WorkerNotOwned"
			)
			expect(gameplay(restored.profiles[restored.first])).toEqual(gameplay(before))
		end
	)

	it("isolates payment, removal, and receipts to the requesting profile", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		local request = sell(0, "shared-token")
		expect(f.api.Sell(f.first, request).ok).toBe(true)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		local result = f.api.Sell(f.second, request)
		expect(result.ok).toBe(true)
		expect(result.replayed).toBeNil()
		expect(f.profiles[f.first]).toEqual(firstAfter)
		expect(f.profiles[f.second].currency.gold).toBe(125)
		expect(f.state.players).toEqual({ f.first, f.second })
	end)

	it(
		"rolls back removal, Gold, accounting, and receipt when the session ends after callback",
		function()
			local f = fixture()
			local before = copy(f.profiles[f.first])
			f.state.now = 300
			f.state.loseSessionAfterCallback = true
			expect(f.api.Sell(f.first, sell(0, "lost-session"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.clockCalls).toBe(1)
		end
	)

	it(
		"rejects invalid or backdated time without committing deletion or elapsed production",
		function()
			for _, timestamp in { -1, math.huge, 0 / 0, 9 } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.productionClock = { lastAccruedAt = 10, nextBatchAt = 11 }
				f.state.now = timestamp
				local before = gameplay(data)
				local result = f.api.Sell(f.first, sell(0, "bad-time"))
				expect(result.ok).toBe(false)
				if timestamp == 9 then
					expect(result.code).toBe("BackdatedChange")
				end
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

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
		it(`rolls back {case.code} clocks including the receipt`, function()
			local f = fixture(nil, case.clock)
			local before = copy(f.profiles[f.first])
			expect(f.api.Sell(f.first, sell(0, "clock-failure"))).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end)
	end

	it(
		"rejects unresolved workers and invalid canonical state without reinterpreting prototypes",
		function()
			for _, failure in
				{ "unknown", "legacy", "progression", "other-worker", "clock", "base" }
			do
				local f = fixture()
				local data = f.profiles[f.first]
				if failure == "unknown" then
					data.mythlings.worker =
						{ typeId = "prototype_form", variantId = "old", claimedAt = 9 }
				elseif failure == "legacy" then
					data.mythlings.worker.standId = 1
				elseif failure == "progression" then
					data.mythlings.worker.pendingXp = nil
				elseif failure == "other-worker" then
					data.mythlings.other.typeId = "unresolved"
				elseif failure == "clock" then
					data.productionClock = nil
				else
					data.base.buildSlotUpgrades = -1
				end
				local before = gameplay(data)
				expect(f.api.Sell(f.first, sell(0, "invalid-state")).ok).toBe(false)
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"preserves unrelated worker identities, inactive legacy data, Materials, jobs, and purchases",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
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
			local legacyFields = data.mythlings.other :: any
			legacyFields.luck = 77
			legacyFields.traitIds = { "insomniac", "lucky" }
			legacyFields.custom = { note = "retained" }
			local currencyFields = data.currency :: any
			currencyFields.legacyTokens = 41
			local before = gameplay(data)
			local base, records, record, assignments, owned, other, clock, currency, materials, jobs, station =
				data.base,
				savedShrines(data),
				savedShrines(data).second,
				savedShrines(data).second.workerIdsBySlot,
				data.mythlings,
				data.mythlings.other,
				data.productionClock,
				data.currency,
				data.materials,
				data.craftingJobs,
				data.base.craftingStation
			expect(f.api.Sell(f.first, sell(0, "preserve")).ok).toBe(true)
			local expected = copy(before)
			expected.mythlings.worker = nil
			expected.currency.gold = 125
			expect(gameplay(data)).toEqual(expected)
			expect(data.base).toBe(base)
			expect(savedShrines(data)).toBe(records)
			expect(savedShrines(data).second).toBe(record)
			expect(savedShrines(data).second.workerIdsBySlot).toBe(assignments)
			expect(data.mythlings).toBe(owned)
			expect(data.mythlings.other).toBe(other)
			expect(data.productionClock).toBe(clock)
			expect(data.currency).toBe(currency)
			expect(data.materials).toBe(materials)
			expect(data.craftingJobs).toBe(jobs)
			expect(data.base.craftingStation).toBe(station)
		end
	)
end)
