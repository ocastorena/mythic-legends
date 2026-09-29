--!strict
-- ServerStorage/Tests/__tests__/ShrineRemoval.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineRemoval = require(ServerScriptService.Services.BaseService.ShrineRemoval)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
local ShrineConstruction = require(ServerScriptService.Services.BaseService.ShrineConstruction)
local ShrineCollector = require(ServerScriptService.Services.ProductionService.ShrineCollector)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
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
	assert(prepared, `[ShrineRemoval.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = userId
	data.mythlings = { worker = worker("mythling_0001"), water = worker("mythling_0004") }
	data.base.shrines = { first = shrine("first", "fire_shrine", 1) }
	return data
end

local function savedShrines(data: Types.PlayerDoc): { [string]: Types.ShrineRecord }
	return (assert(data.base.shrines, "[ShrineRemoval.spec] Expected Shrine map"))
end

local function dismantle(
	revision: number,
	token: string,
	level: number?,
	shrineInstanceId: string?
): Types.DismantleShrineRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineInstanceId = shrineInstanceId or "first",
		expectedLevel = level or 1,
	}
end

local function fixture(firstProfile: Types.PlayerDoc?, clockOverride: (() -> number)?)
	-- Private helpers use identity tokens; the service facade checks connected engine Players.
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
	local dataSource: ShrineRemoval.DataSource = {
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
	local api = ShrineRemoval.new(dataSource, function(): number
		state.clockCalls += 1
		assert(state.inCallback, "[ShrineRemoval.spec] Clock must be inside transaction")
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

describe("ShrineRemoval", function()
	it("dismantles every launch element at all three levels without a refund", function()
		for _, element in { "fire", "water", "earth", "air", "light", "dark" } do
			for level = 1, 3 do
				local f = fixture()
				local data = f.profiles[f.first]
				local record = savedShrines(data).first
				record.shrineId = `{element}_shrine`
				record.level = level
				record.progress = 0.99
				local before = gameplay(data)
				f.state.now = 0.5
				expect(f.api.Dismantle(f.first, dismantle(0, "six-elements", level))).toEqual({
					ok = true,
					revision = 1,
					values = {
						shrineInstanceId = "first",
						shrineId = `{element}_shrine`,
						buildSlotId = 1,
						level = level,
						settledAt = 0.5,
					},
				})
				savedShrines(before).first = nil
				before.productionClock = { lastAccruedAt = 0.5, nextBatchAt = 1 }
				expect(gameplay(data)).toEqual(before)
				expect(f.state.operations).toEqual({ "Base.DismantleShrine" })
				expect(f.state.clockCalls).toBe(1)
				expect(f.state.transactionCalls).toBe(1)
			end
		end
	end)

	it("requires explicit worker removal and completed Material collection", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.workerIdsBySlot = { ["1"] = "worker" }
		record.stored = 1
		f.state.now = 0.5
		local before = gameplay(data)
		expect(f.api.Dismantle(f.first, dismantle(0, "occupied")).code).toBe("ShrineOccupied")
		expect(gameplay(data)).toEqual(before)
		local workers = ShrineWorkers.new(f.dataSource, function()
			return f.state.now
		end)
		expect(workers.Remove(f.first, {
			requestId = "1:unassign",
			expectedRevision = 1,
			shrineInstanceId = "first",
			slotId = 1,
			expectedWorkerId = "worker",
		}).ok).toBe(true)
		before = gameplay(data)
		expect(f.api.Dismantle(f.first, dismantle(2, "stored")).code).toBe("MaterialsStored")
		expect(gameplay(data)).toEqual(before)
		local collector = ShrineCollector.new(f.dataSource, function()
			return f.state.now
		end)
		expect(collector.Collect(f.first, {
			requestId = "3:collect",
			expectedRevision = 3,
			shrineInstanceId = "first",
			expectedMaterialId = "fire_material",
		}).ok).toBe(true)
		expect(f.api.Dismantle(f.first, dismantle(4, "empty")).ok).toBe(true)
		expect(savedShrines(data)).toEqual({})
		expect(data.materials.fire_material.total).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0.5)
	end)

	it(
		"rejects output completed by a due batch without committing settlement or removal",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local record = savedShrines(data).first
			record.progress = 0.999
			record.newWork = 0.002
			data.mythlings.worker.pendingXp = 0.5
			data.productionClock = { lastAccruedAt = 0.5, nextBatchAt = 1 }
			f.state.now = 1
			local before = gameplay(data)
			expect(f.api.Dismantle(f.first, dismantle(0, "due-output"))).toEqual({
				ok = false,
				code = "MaterialsStored",
				revision = 1,
			})
			expect(gameplay(data)).toEqual(before)
		end
	)

	it(
		"discards unfinished work before the batch but keeps due XP after the last Shrine is gone",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local record = savedShrines(data).first
			record.progress = 0.999
			record.newWork = 0.002
			data.mythlings.worker.pendingXp = 0.5
			data.productionClock = { lastAccruedAt = 0.5, nextBatchAt = 1 }
			f.state.now = 0.75
			expect(f.api.Dismantle(f.first, dismantle(0, "partial")).ok).toBe(true)
			expect(savedShrines(data)).toEqual({})
			expect(data.materials).toEqual({})
			expect(data.mythlings.worker.xp).toBe(0)
			expect(data.mythlings.worker.pendingXp).toBe(0.5)
			expect(data.productionClock).toEqual({ lastAccruedAt = 0.75, nextBatchAt = 1 })
			local continued = fixture(copy(data))
			local restored = continued.profiles[continued.first]
			expect(continued.dataSource.Transact(continued.first, {
				id = "1:settle",
				expectedRevision = 1,
				operation = "Production.SettleShrines",
				signature = "at=1",
			}, function(draft)
				local ok, code = ShrineAccounting.SettleToDraft(draft, 1)
				return { ok = ok, code = code }
			end).ok).toBe(true)
			expect(savedShrines(restored)).toEqual({})
			expect(restored.mythlings.worker.xp).toBe(0.5)
			expect(restored.mythlings.worker.pendingXp).toBe(0)
			expect(restored.materials).toEqual({})
			expect(restored.productionClock).toEqual({ lastAccruedAt = 1, nextBatchAt = 2 })
		end
	)

	it("settles the whole ledger while preserving other Shrine identities and workers", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local other = shrine("other", "water_shrine", 2)
		other.workerIdsBySlot = { ["1"] = "water" }
		other.stored = 4
		other.progress = 0.25
		savedShrines(data).other = other
		data.mythlings.worker.pendingXp = 0.25
		f.state.now = 1
		expect(f.api.Dismantle(f.first, dismantle(0, "whole-ledger")).ok).toBe(true)
		expect(savedShrines(data).first).toBeNil()
		expect(savedShrines(data).other).toBe(other)
		expect(other.level).toBe(1)
		expect(other.buildSlotId).toBe(2)
		expect(other.stored).toBe(4)
		expect(other.progress).toBeCloseTo(0.25 + 12 / 3_600)
		expect(other.workerIdsBySlot).toEqual({ ["1"] = "water" })
		expect(data.mythlings.water.xp).toBe(1)
		expect(data.mythlings.worker.xp).toBe(0.25)
		expect(data.mythlings.worker.pendingXp).toBe(0)
	end)

	it(
		"preserves purchased slots, Station, reservations, inactive legacy fields, and balances",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.base.buildSlotUpgrades = 4
			savedShrines(data).first.buildSlotId = 6
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
			data.materials = { fire_material = { total = 37 }, fire = { total = 17 } }
			data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 1 }
			data.craftingJobs = {
				active = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
				},
			}
			local before = gameplay(data)
			local base, records, station, stands, owned, materials, jobs =
				data.base,
				savedShrines(data),
				data.base.craftingStation,
				data.base.stands,
				data.mythlings,
				data.materials,
				data.craftingJobs
			expect(f.api.Dismantle(f.first, dismantle(0, "preserve")).ok).toBe(true)
			savedShrines(before).first = nil
			expect(gameplay(data)).toEqual(before)
			expect(data.base).toBe(base)
			expect(savedShrines(data)).toBe(records)
			expect(data.base.craftingStation).toBe(station)
			expect(data.base.stands).toBe(stands)
			expect(data.mythlings).toBe(owned)
			expect(data.materials).toBe(materials)
			expect(data.craftingJobs).toBe(jobs)
		end
	)

	it(
		"reuses the freed slot with a new identity and never removes that replacement on retry",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			savedShrines(data).other = shrine("other", "water_shrine", 2)
			local request = dismantle(0, "original")
			local removed = f.api.Dismantle(f.first, request)
			expect(removed.ok).toBe(true)
			local construction = ShrineConstruction.new(f.dataSource, function()
				return "replacement"
			end)
			expect(construction.Build(f.first, {
				requestId = "1:rebuild",
				expectedRevision = 1,
				shrineId = "earth_shrine",
				expectedGoldCost = 100,
			}).ok).toBe(true)
			expect(savedShrines(data).replacement.buildSlotId).toBe(1)
			local before = copy(data)
			f.state.now = 500
			expect(f.api.Dismantle(f.first, request)).toEqual({
				ok = true,
				revision = 1,
				values = removed.values,
				replayed = true,
			})
			expect(data).toEqual(before)
			expect(f.state.clockCalls).toBe(1)
			expect(f.api.Dismantle(f.first, dismantle(2, "stale-id")).code).toBe("ShrineNotOwned")
			expect(gameplay(data)).toEqual(gameplay(before))
			expect(savedShrines(data).replacement.shrineId).toBe("earth_shrine")
		end
	)

	it("rejects missing ownership, stale level, and permanent Station selections", function()
		for _, selection in { "missing", "level", "station" } do
			local f = fixture()
			local request = dismantle(0, "stale")
			local code = "ShrineNotOwned"
			if selection == "level" then
				request.expectedLevel = 2
				code = "LevelChanged"
			else
				request.shrineInstanceId = if selection == "station"
					then "station_1001"
					else "missing"
			end
			local before = gameplay(f.profiles[f.first])
			expect(f.api.Dismantle(f.first, request).code).toBe(code)
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end
	end)

	it("rejects malformed envelopes before transacting or sampling time", function()
		local invalid: { any } = { false, 1, "request", setmetatable(dismantle(0, "meta"), {}) }
		for _, field in { "requestId", "expectedRevision", "shrineInstanceId", "expectedLevel" } do
			local raw: { [string]: any } = copy(dismantle(0, "missing")) :: any
			raw[field] = nil
			table.insert(invalid, raw)
		end
		for _, field in
			{ "now", "player", "buildSlotId", "refund", "metadata", "signature", "operation" }
		do
			local raw: { [string]: any } = copy(dismantle(0, "extra")) :: any
			raw[field] = 1
			table.insert(invalid, raw)
		end
		for _, field in { "expectedRevision", "expectedLevel" } do
			for _, value in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53, "1" } do
				local raw: { [string]: any } = copy(dismantle(0, "number")) :: any
				raw[field] = value
				table.insert(invalid, raw)
			end
		end
		local zero = dismantle(0, "zero")
		zero.expectedLevel = 0
		table.insert(invalid, zero)
		for _, field in { "requestId", "shrineInstanceId" } do
			for _, value in { "", string.rep("x", 129), 10 } do
				local raw: { [string]: any } = copy(dismantle(0, "id")) :: any
				raw[field] = value
				table.insert(invalid, raw)
			end
		end
		for _, request in invalid do
			local f = fixture()
			local before = copy(f.profiles[f.first])
			expect(f.api.Dismantle(f.first, request)).toEqual({
				ok = false,
				code = "InvalidRequest",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it("requires an active loaded profile without loading one", function()
		for _, failure in { "available", "active" } do
			local f = fixture()
			if failure == "available" then
				f.state.available = false
			else
				f.state.active = false
			end
			local before = copy(f.profiles[f.first])
			expect(f.api.Dismantle(f.first, dismantle(0, "unavailable"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it("binds identity and exact safe-integer level to the receipt", function()
		local f = fixture()
		expect(f.api.Dismantle(f.first, dismantle(0, "binding")).ok).toBe(true)
		local after = copy(f.profiles[f.first])
		for _, request in { dismantle(0, "binding", 2), dismantle(0, "binding", nil, "other") } do
			expect(f.api.Dismantle(f.first, request).code).toBe("RequestConflict")
		end
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
		local large = fixture()
		expect(large.api.Dismantle(large.first, dismantle(0, "large", 2 ^ 52)).code).toBe(
			"LevelChanged"
		)
		expect(large.api.Dismantle(large.first, dismantle(0, "large", 2 ^ 52 + 1)).code).toBe(
			"RequestConflict"
		)
		expect(large.state.clockCalls).toBe(1)
	end)

	it("rejects stale revisions and mismatched request-ID prefixes before sampling time", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		expect(f.api.Dismantle(f.first, dismantle(1, "future")).code).toBe("StaleRevision")
		local request = dismantle(0, "prefix")
		request.requestId = "7:prefix"
		expect(f.api.Dismantle(f.first, request).code).toBe("InvalidTransaction")
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(0)
	end)

	it("replays a rejection after later state permits a fresh removal", function()
		local f = fixture()
		local data = f.profiles[f.first]
		savedShrines(data).first.stored = 1
		local request = dismantle(0, "stored")
		expect(f.api.Dismantle(f.first, request).code).toBe("MaterialsStored")
		savedShrines(data).first.stored = 0
		expect(f.api.Dismantle(f.first, dismantle(1, "empty")).ok).toBe(true)
		local after = copy(data)
		expect(f.api.Dismantle(f.first, request)).toEqual({
			ok = false,
			code = "MaterialsStored",
			revision = 1,
			replayed = true,
		})
		expect(data).toEqual(after)
		expect(f.state.clockCalls).toBe(2)
	end)

	it(
		"preserves removal receipts through JSON continuation without repeating settlement",
		function()
			local f = fixture()
			f.state.now = 0.5
			local request = dismantle(0, "before-save")
			local result = f.api.Dismantle(f.first, request)
			local restored = fixture(copy(f.profiles[f.first]))
			restored.state.now = 500
			local before = copy(restored.profiles[restored.first])
			expect(restored.api.Dismantle(restored.first, request)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.profiles[restored.first]).toEqual(before)
			expect(restored.state.clockCalls).toBe(0)
		end
	)

	it("isolates removal, settlement, and receipt namespaces by requesting profile", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		local request = dismantle(0, "shared-token")
		expect(f.api.Dismantle(f.first, request).ok).toBe(true)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		f.state.now = 1
		local result = f.api.Dismantle(f.second, request)
		expect(result.ok).toBe(true)
		expect(result.replayed).toBeNil()
		expect(f.profiles[f.first]).toEqual(firstAfter)
		expect(savedShrines(f.profiles[f.second])).toEqual({})
		expect(f.state.players).toEqual({ f.first, f.second })
	end)

	it(
		"rolls back removal, XP, settlement, and receipt when the session ends after callback",
		function()
			local f = fixture()
			f.profiles[f.first].mythlings.worker.pendingXp = 0.5
			local before = copy(f.profiles[f.first])
			f.state.now = 1
			f.state.loseSessionAfterCallback = true
			expect(f.api.Dismantle(f.first, dismantle(0, "lost-session"))).toEqual({
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
			local result = f.api.Dismantle(f.first, dismantle(0, "bad-clock"))
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end)
	end

	it("rejects backdated removals without rewinding accounting", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.productionClock = { lastAccruedAt = 10, nextBatchAt = 11 }
		f.state.now = 9
		local before = gameplay(data)
		expect(f.api.Dismantle(f.first, dismantle(0, "backdated")).code).toBe("BackdatedChange")
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
		it(`rolls back {case.code} clocks without removal or receipts`, function()
			local f = fixture(nil, case.clock)
			local before = copy(f.profiles[f.first])
			expect(f.api.Dismantle(f.first, dismantle(0, "clock-failure"))).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end)
	end

	it("rejects invalid canonical state without losing owned records or pending credit", function()
		for _, failure in
			{
				"base",
				"station",
				"progression",
				"legacy",
				"unknown",
				"clock",
				"stored",
				"assignment",
				"duplicate-slot",
			}
		do
			local f = fixture()
			local data = f.profiles[f.first]
			if failure == "base" then
				data.base.buildSlotUpgrades = -1
			elseif failure == "station" then
				data.base.craftingStation = nil
			elseif failure == "progression" then
				data.mythlings.worker.pendingXp = nil
			elseif failure == "legacy" then
				data.mythlings.worker.standId = 1
			elseif failure == "unknown" then
				data.mythlings.worker.typeId = "unknown_form"
				data.mythlings.worker.pendingXp = 0.5
			elseif failure == "clock" then
				data.productionClock = nil
			elseif failure == "stored" then
				savedShrines(data).first.stored = nil
			elseif failure == "assignment" then
				savedShrines(data).first.workerIdsBySlot = { ["1"] = "not-owned" }
			else
				savedShrines(data).other = shrine("other", "water_shrine", 1)
			end
			local before = gameplay(data)
			local result = f.api.Dismantle(f.first, dismantle(0, "invalid-state"))
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(gameplay(data)).toEqual(before)
		end
	end)
end)
