--!strict
-- ServerStorage/Tests/__tests__/ShrineCollector.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineCollector = require(ServerScriptService.Services.ProductionService.ShrineCollector)
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
		stored = 5,
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
	assert(prepared, `[ShrineCollector.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = userId
	data.mythlings = { worker = worker("mythling_0001"), removed = worker("mythling_0003") }
	local first = shrine("first", "fire_shrine", 1)
	first.workerIdsBySlot = { ["1"] = "worker" }
	data.base.shrines = { first = first }
	return data
end

local function savedShrines(data: Types.PlayerDoc): { [string]: Types.ShrineRecord }
	return (assert(data.base.shrines, "[ShrineCollector.spec] Expected Shrine map"))
end

local function collect(
	revision: number,
	token: string,
	shrineInstanceId: string?,
	expectedMaterialId: string?
): Types.CollectShrineRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineInstanceId = shrineInstanceId or "first",
		expectedMaterialId = expectedMaterialId or "fire_material",
	}
end

local function fillMaterialSlots(data: Types.PlayerDoc, count: number)
	-- Retained, non-launch Material IDs still occupy their own Inventory slots.
	for index = 1, count do
		data.materials[`legacy_{index}`] = { total = 1_000 }
	end
end

local function fixture(firstProfile: Types.PlayerDoc?, clockOverride: (() -> number)?)
	-- Private command tests use distinct identity tokens; engine Players are checked at the facade.
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
	local dataSource: ShrineCollector.DataSource = {
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
	local api = ShrineCollector.new(dataSource, function(): number
		state.clockCalls += 1
		assert(state.inCallback, "[ShrineCollector.spec] Clock must be sampled inside transaction")
		return if clockOverride then clockOverride() else state.now
	end)
	return { first = first, second = second, profiles = profiles, state = state, api = api }
end

describe("ShrineCollector", function()
	it(
		"atomically settles and collects the configured Material for all six launch elements",
		function()
			for _, content in
				{
					{ "fire", "mythling_0001" },
					{ "water", "mythling_0004" },
					{ "earth", "mythling_0007" },
					{ "air", "mythling_0010" },
					{ "light", "mythling_0013" },
					{ "dark", "mythling_0016" },
				}
			do
				local data = profile(1001)
				data.mythlings.worker.typeId = content[2]
				savedShrines(data).first.shrineId = `{content[1]}_shrine`
				local f = fixture(data)
				f.state.now = 1
				local materialId = `{content[1]}_material`
				expect(f.api.Collect(f.first, collect(0, "six-elements", nil, materialId))).toEqual({
					ok = true,
					revision = 1,
					values = {
						shrineInstanceId = "first",
						materialId = materialId,
						collected = 5,
						remaining = 0,
						settledAt = 1,
					},
				})
				expect(data.materials).toEqual({ [materialId] = { total = 5 } })
				expect(savedShrines(data).first.stored).toBe(0)
				expect(savedShrines(data).first.progress).toBeCloseTo(12 / 3_600)
				expect(data.mythlings.worker.xp).toBe(1)
				expect(f.state.operations).toEqual({ "Production.CollectShrine" })
				expect(f.state.clockCalls).toBe(1)
				expect(f.state.transactionCalls).toBe(1)
			end
		end
	)

	it("preserves unfinished work and pending XP without forcing an early batch", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.progress = 0.997
		f.state.now = 0.5
		expect(f.api.Collect(f.first, collect(0, "partial-batch")).ok).toBe(true)
		expect(data.materials.fire_material.total).toBe(5)
		expect(record.progress).toBe(0.997)
		expect(record.newWork).toBeCloseTo(12 * 0.5 / 3_600)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.worker.pendingXp).toBe(0.5)
		expect(data.productionClock).toEqual({ lastAccruedAt = 0.5, nextBatchAt = 1 })
		f.state.now = 1
		local result = f.api.Collect(f.first, collect(1, "boundary"))
		expect(result.ok).toBe(true)
		expect(assert(result.values).collected).toBe(1)
		expect(data.materials.fire_material.total).toBe(6)
		expect(record.progress).toBeCloseTo(0.997 + 12 / 3_600 - 1)
		expect(record.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(data.productionClock).toEqual({ lastAccruedAt = 1, nextBatchAt = 2 })
	end)

	it(
		"partially transfers only matching stack room and retains the uncollected whole output",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire_material = { total = 999 }
			fillMaterialSlots(data, 11)
			local result = f.api.Collect(f.first, collect(0, "partial"))
			expect(result.ok).toBe(true)
			expect(assert(result.values).collected).toBe(1)
			expect(assert(result.values).remaining).toBe(4)
			expect(data.materials.fire_material.total).toBe(1_000)
			expect(savedShrines(data).first.stored).toBe(4)
			for index = 1, 11 do
				expect(data.materials[`legacy_{index}`]).toEqual({ total = 1_000 })
			end
		end
	)

	it("rejects a full Inventory even when a different Material's stack has room", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.materials.water_material = { total = 999 }
		fillMaterialSlots(data, 11)
		f.state.now = 60
		local before = gameplay(data)
		expect(f.api.Collect(f.first, collect(0, "wrong-stack"))).toEqual({
			ok = false,
			code = "InventoryFull",
			revision = 1,
		})
		expect(gameplay(data)).toEqual(before)
	end)

	it(
		"derives upgraded Material capacity solely from the player's purchased upgrade state",
		function()
			for level, limit in { [0] = 12, [1] = 24, [2] = 36 } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.inventoryUpgrades = { materials = level, mythlings = 2, equipment = 2 }
				fillMaterialSlots(data, limit - 1)
				savedShrines(data).first.level = 2
				savedShrines(data).first.stored = 1_200
				local result = f.api.Collect(f.first, collect(0, "purchased-capacity"))
				expect(result.ok).toBe(true)
				expect(assert(result.values).collected).toBe(1_000)
				expect(assert(result.values).remaining).toBe(200)
				expect(data.inventoryUpgrades).toEqual({
					materials = level,
					mythlings = 2,
					equipment = 2,
				})
			end
		end
	)

	it(
		"respects matching and other-type active refund promises without consuming reservations",
		function()
			for _, materialId in { "fire_material", "water_material" } do
				local f = fixture()
				local data = f.profiles[f.first]
				savedShrines(data).first.level = 2
				savedShrines(data).first.stored = 1_200
				fillMaterialSlots(data, 10)
				data.materials.fire_material = { total = 200 }
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { [materialId] = 750 } },
					},
					complete = {
						status = "Completed",
						reservations = { equipment = 1, materials = { fire_material = 9_000 } },
					},
				}
				local jobs = data.craftingJobs
				local jobsBefore = copy(jobs)
				local expected = if materialId == "fire_material" then 1_050 else 800
				local result = f.api.Collect(f.first, collect(0, "reserved"))
				expect(result.ok).toBe(true)
				expect(assert(result.values).collected).toBe(expected)
				expect(assert(result.values).remaining).toBe(1_200 - expected)
				expect(data.materials.fire_material.total).toBe(200 + expected)
				expect(data.craftingJobs).toBe(jobs)
				expect(data.craftingJobs).toEqual(jobsBefore)
			end
		end
	)

	it("resumes after full-storage collection without earning for the paused interval", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.stored = 300
		f.state.now = 1_000
		expect(f.api.Collect(f.first, collect(0, "resume")).ok).toBe(true)
		expect(data.materials.fire_material.total).toBe(300)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(record.progress).toBe(0)
		expect(data.productionClock).toEqual({ lastAccruedAt = 1_000, nextBatchAt = 1_001 })
		f.state.now = 1_300
		expect(f.api.Collect(f.first, collect(1, "later")).ok).toBe(true)
		expect(data.materials.fire_material.total).toBe(301)
		expect(data.mythlings.worker.level).toBe(2)
		expect(data.mythlings.worker.xp).toBe(180)
		expect(record.progress).toBeCloseTo((120 * 12 + 180 * 12.12) / 3_600 - 1)
	end)

	it("keeps the filling batch's XP and discards overflow before collecting", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.stored = 299
		record.progress = 0.999
		f.state.now = 300
		expect(f.api.Collect(f.first, collect(0, "fills")).ok).toBe(true)
		expect(data.materials.fire_material.total).toBe(300)
		expect(record.stored).toBe(0)
		expect(record.progress).toBe(0)
		expect(record.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(1)
	end)

	it(
		"settles all owned Shrines and removed workers' pending XP but debits only the selection",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local second = shrine("second", "water_shrine", 2)
			second.workerIdsBySlot = { ["1"] = "water" }
			savedShrines(data).second = second
			data.mythlings.water = worker("mythling_0004")
			data.mythlings.removed.pendingXp = 0.25
			f.state.now = 1
			expect(f.api.Collect(f.first, collect(0, "whole-ledger")).ok).toBe(true)
			expect(data.materials).toEqual({ fire_material = { total = 5 } })
			expect(savedShrines(data).first.stored).toBe(0)
			expect(second.stored).toBe(5)
			expect(second.progress).toBeCloseTo(12 / 3_600)
			expect(data.mythlings.water.xp).toBe(1)
			expect(data.mythlings.removed.xp).toBe(0.25)
			expect(data.mythlings.removed.pendingXp).toBe(0)
			expect(second.workerIdsBySlot).toEqual({ ["1"] = "water" })
		end
	)

	it(
		"rejects empty storage without committing fractional work even when Inventory is full",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			savedShrines(data).first.stored = 0
			fillMaterialSlots(data, 12)
			f.state.now = 0.5
			local before = gameplay(data)
			expect(f.api.Collect(f.first, collect(0, "nothing"))).toEqual({
				ok = false,
				code = "NothingToCollect",
				revision = 1,
			})
			expect(gameplay(data)).toEqual(before)
		end
	)

	it(
		"rejects unowned Shrines and stale output selections without settlement or grants",
		function()
			for _, case in
				{
					{
						shrineId = "not_owned",
						materialId = "fire_material",
						code = "ShrineNotOwned",
					},
					{ shrineId = "first", materialId = "water_material", code = "MaterialChanged" },
				}
			do
				local f = fixture()
				f.state.now = 300
				local before = gameplay(f.profiles[f.first])
				expect(f.api.Collect(f.first, collect(0, "stale", case.shrineId, case.materialId))).toEqual({
					ok = false,
					code = case.code,
					revision = 1,
				})
				expect(gameplay(f.profiles[f.first])).toEqual(before)
			end
		end
	)

	it(
		"rejects missing, extra, malformed, and metatable request fields before transacting",
		function()
			local invalidRequests: { any } =
				{ false, 1, "request", setmetatable(collect(0, "meta"), {}) }
			for _, field in
				{ "requestId", "expectedRevision", "shrineInstanceId", "expectedMaterialId" }
			do
				local raw: { [string]: any } = copy(collect(0, "missing")) :: any
				raw[field] = nil
				table.insert(invalidRequests, raw)
			end
			for _, field in
				{
					"now",
					"ledger",
					"materials",
					"metadata",
					"quantity",
					"player",
					"signature",
					"operation",
				}
			do
				local raw: { [string]: any } = copy(collect(0, "extra")) :: any
				raw[field] = 1
				table.insert(invalidRequests, raw)
			end
			for _, revision in { -1, 0.5, math.huge, 0 / 0 } do
				local request = collect(0, "revision")
				request.expectedRevision = revision
				table.insert(invalidRequests, request)
			end
			for _, field in { "requestId", "shrineInstanceId", "expectedMaterialId" } do
				for _, value in { "", string.rep("x", 129), 10 } do
					local raw: { [string]: any } = copy(collect(0, "id")) :: any
					raw[field] = value
					table.insert(invalidRequests, raw)
				end
			end
			for _, request in invalidRequests do
				local f = fixture()
				local before = copy(f.profiles[f.first])
				expect(f.api.Collect(f.first, request)).toEqual({
					ok = false,
					code = "InvalidRequest",
					revision = 0,
				})
				expect(f.profiles[f.first]).toEqual(before)
				expect(f.state.transactionCalls).toBe(0)
				expect(f.state.clockCalls).toBe(0)
			end
		end
	)

	it("requires a loaded active profile and does not auto-load it", function()
		for _, stateKey in { "available", "active" } do
			local f = fixture()
			if stateKey == "available" then
				f.state.available = false
			else
				f.state.active = false
			end
			local before = copy(f.profiles[f.first])
			expect(f.api.Collect(f.first, collect(0, "unavailable"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it(
		"replays exact retries without resampling time, granting Materials, or advancing work",
		function()
			local f = fixture()
			local request = collect(0, "retry")
			f.state.now = 0.5
			local result = f.api.Collect(f.first, request)
			local after = copy(f.profiles[f.first])
			f.state.now = 500
			expect(f.api.Collect(f.first, request)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(f.profiles[f.first]).toEqual(after)
			expect(f.state.clockCalls).toBe(1)
			expect(f.state.callbackCalls).toBe(1)
		end
	)

	it("binds receipt signatures to both Shrine and expected Material identities", function()
		local f = fixture()
		expect(f.api.Collect(f.first, collect(0, "binding")).ok).toBe(true)
		local after = copy(f.profiles[f.first])
		for _, request in
			{
				collect(0, "binding", "other"),
				collect(0, "binding", nil, "water_material"),
			}
		do
			expect(f.api.Collect(f.first, request).code).toBe("RequestConflict")
		end
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
	end)

	it(
		"rejects stale revisions and mismatched request-ID revisions before sampling time",
		function()
			local f = fixture()
			local before = copy(f.profiles[f.first])
			expect(f.api.Collect(f.first, collect(1, "future")).code).toBe("StaleRevision")
			local request = collect(0, "wrong-prefix")
			request.requestId = "7:wrong-prefix"
			expect(f.api.Collect(f.first, request).code).toBe("InvalidTransaction")
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.clockCalls).toBe(0)
		end
	)

	it("replays a rejected receipt even after later state would permit collection", function()
		local f = fixture()
		local data = f.profiles[f.first]
		fillMaterialSlots(data, 12)
		local request = collect(0, "full")
		expect(f.api.Collect(f.first, request).code).toBe("InventoryFull")
		data.materials.legacy_12 = nil
		expect(f.api.Collect(f.first, collect(1, "new-attempt")).ok).toBe(true)
		local after = copy(data)
		expect(f.api.Collect(f.first, request)).toEqual({
			ok = false,
			code = "InventoryFull",
			revision = 1,
			replayed = true,
		})
		expect(data).toEqual(after)
		expect(f.state.clockCalls).toBe(2)
	end)

	it("retains receipts and partial-batch accounting through JSON continuation", function()
		local f = fixture()
		savedShrines(f.profiles[f.first]).first.progress = 0.997
		f.state.now = 0.5
		local request = collect(0, "before-save")
		local result = f.api.Collect(f.first, request)
		local restored = fixture(copy(f.profiles[f.first]))
		restored.state.now = 1
		expect(restored.api.Collect(restored.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		expect(restored.state.clockCalls).toBe(0)
		expect(restored.api.Collect(restored.first, collect(1, "continued")).ok).toBe(true)
		local data = restored.profiles[restored.first]
		expect(data.materials.fire_material.total).toBe(6)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(savedShrines(data).first.progress).toBeCloseTo(0.997 + 12 / 3_600 - 1)
	end)

	it(
		"uses only the selected player's source, destination, clock, and receipt namespace",
		function()
			local f = fixture()
			local secondBefore = copy(f.profiles[f.second])
			local request = collect(0, "shared-token")
			expect(f.api.Collect(f.first, request).ok).toBe(true)
			expect(f.profiles[f.second]).toEqual(secondBefore)
			local firstAfter = copy(f.profiles[f.first])
			f.state.now = 1
			local result = f.api.Collect(f.second, request)
			expect(result.ok).toBe(true)
			expect(result.replayed).toBeNil()
			expect(f.profiles[f.first]).toEqual(firstAfter)
			expect(f.profiles[f.second].materials.fire_material.total).toBe(5)
			expect(f.state.players).toEqual({ f.first, f.second })
		end
	)

	it("rolls back the whole collection if the session ends after its callback", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		f.state.now = 300
		f.state.loseSessionAfterCallback = true
		expect(f.api.Collect(f.first, collect(0, "lost-session"))).toEqual({
			ok = false,
			code = "DataUnavailable",
			revision = 0,
		})
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(1)
	end)

	for _, timestamp in { -1, math.huge, 0 / 0 } do
		it(`rejects invalid sampled time {tostring(timestamp)} without gameplay changes`, function()
			local f = fixture()
			f.state.now = timestamp
			local before = gameplay(f.profiles[f.first])
			local result = f.api.Collect(f.first, collect(0, "bad-clock"))
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end)
	end

	it("rejects backdated collection without moving the accounting cursor backwards", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.productionClock = { lastAccruedAt = 10, nextBatchAt = 11 }
		f.state.now = 9
		local before = gameplay(data)
		expect(f.api.Collect(f.first, collect(0, "backdated")).code).toBe("BackdatedChange")
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
		it(`rolls back {case.code} clocks without grants or receipts`, function()
			local f = fixture(nil, case.clock)
			local before = copy(f.profiles[f.first])
			expect(f.api.Collect(f.first, collect(0, "clock-failure"))).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end)
	end

	it(
		"rejects invalid source, destination, progression, and reservation state atomically",
		function()
			for _, failure in
				{
					"base",
					"progression",
					"legacy",
					"unknown",
					"material",
					"upgrade",
					"reservation",
					"clock",
				}
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
				elseif failure == "material" then
					data.materials.fire_material = { total = -1 }
				elseif failure == "upgrade" then
					data.inventoryUpgrades = { materials = -1 }
				elseif failure == "reservation" then
					data.craftingJobs = {
						active = {
							status = "Active",
							reservations = { equipment = 1, materials = { fire_material = -1 } },
						},
					}
				else
					data.productionClock = nil
				end
				f.state.now = 300
				local before = gameplay(data)
				local result = f.api.Collect(f.first, collect(0, "invalid-state"))
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it("preserves live identities, unrelated save data, and inactive legacy fields", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.materials.fire_material = { total = 10 }
		data.materials.fire = { total = 17 }
		data.base.stands["1"] = {
			production = {
				lastAccruedAt = 10,
				materials = { fire = { stored = 4, progress = 0.5 } },
			},
		}
		data.mythlings.legacy =
			{ typeId = "prototype_form", variantId = "old", claimedAt = 9, standId = 1 }
		-- Historical extensions remain opaque, inactive saved state.
		local legacyFields = data.mythlings.worker :: any
		legacyFields.luck = 77
		legacyFields.traitIds = { "insomniac", "lucky" }
		legacyFields.custom = { note = "retained" }
		local before = gameplay(data)
		local base, records, record, assignments, owned, firstWorker, clock, materials, fire, legacyMaterial, station, stands =
			data.base,
			savedShrines(data),
			savedShrines(data).first,
			savedShrines(data).first.workerIdsBySlot,
			data.mythlings,
			data.mythlings.worker,
			data.productionClock,
			data.materials,
			data.materials.fire_material,
			data.materials.fire,
			data.base.craftingStation,
			data.base.stands
		expect(f.api.Collect(f.first, collect(0, "preserve")).ok).toBe(true)
		local expected = copy(before)
		savedShrines(expected).first.stored = 0
		expected.materials.fire_material.total = 15
		expect(gameplay(data)).toEqual(expected)
		expect(data.base).toBe(base)
		expect(savedShrines(data)).toBe(records)
		expect(savedShrines(data).first).toBe(record)
		expect(savedShrines(data).first.workerIdsBySlot).toBe(assignments)
		expect(data.mythlings).toBe(owned)
		expect(data.mythlings.worker).toBe(firstWorker)
		expect(data.productionClock).toBe(clock)
		expect(data.materials).toBe(materials)
		expect(data.materials.fire_material).toBe(fire)
		expect(data.materials.fire).toBe(legacyMaterial)
		expect(data.base.craftingStation).toBe(station)
		expect(data.base.stands).toBe(stands)
	end)
end)
