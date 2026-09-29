--!strict
-- ServerStorage/Tests/__tests__/ShrinePersistence.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Projection = require(ServerScriptService.Services.DataService.Projection)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local NOW = 1_000
local SUPPORTED_VERSIONS = { 4, 5, 6, 7 }

-- Dynamic copies permit malformed saved-data fixtures, including non-JSON finite-number failures.
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = copy(child)
	end
	return result
end

local function stationId(): string
	return "new_station"
end

local function neverGenerate(): string
	error("[ShrinePersistence.spec] Existing Station must be retained")
end

local function clock(): { lastAccruedAt: number, nextBatchAt: number }
	return { lastAccruedAt = NOW, nextBatchAt = NOW + Production.batchIntervalSeconds }
end

local function shrine(id: string, buildSlotId: number): any
	return {
		id = id,
		shrineId = "fire_shrine",
		buildSlotId = buildSlotId,
		level = 1,
	}
end

local function addAccounting(record: any)
	record.stored = 0
	record.progress = 0
	record.newWork = 0
	record.workerIdsBySlot = {}
end

local function savedData(version: number): any
	local data = copy(PlayerDataTemplate)
	data.version = version
	data.profile = { userId = 25, createdAt = 100, lastLoginAt = 200 }
	data.base.craftingStation = {
		id = "retained_station",
		craftingStationId = "basic_crafting_station",
	}
	data.base.shrines = { first = shrine("first", 1), second = shrine("second", 2) }
	if version == Configuration.schemaVersion then
		data.productionClock = clock()
		for _, record in data.base.shrines do
			addAccounting(record)
		end
	end
	return data
end

local function worker(): any
	return {
		typeId = "unfinalized_form",
		variantId = "legacy_variant",
		claimedAt = 55,
		level = 44,
		xp = 300,
		pendingXp = 0.75,
		luck = 7,
		traitIds = { "legacy_trait" },
	}
end

local function expectRejected(data: any, expectedCode: string?)
	local before = copy(data)
	local base, shrines, first, priorClock =
		data.base, data.base.shrines, data.base.shrines.first, data.productionClock
	local ok, code = ProfileSchema.Prepare(data, neverGenerate, NOW)
	expect(ok).toBe(false)
	if expectedCode then
		expect(code).toBe(expectedCode)
	else
		expect(type(code)).toBe("string")
	end
	expect(data).toEqual(before)
	expect(data.base).toBe(base)
	expect(data.base.shrines).toBe(shrines)
	expect(data.base.shrines.first).toBe(first)
	expect(data.productionClock).toBe(priorClock)
end

describe("Shrine accounting persistence foundation", function()
	it("creates independent clocks once at fresh profile load without using lastLoginAt", function()
		local first, second = copy(PlayerDataTemplate), copy(PlayerDataTemplate)
		first.profile.lastLoginAt = 12
		second.profile.lastLoginAt = 900
		expect((ProfileSchema.Prepare(first, stationId, NOW))).toBe(true)
		expect((ProfileSchema.Prepare(second, stationId, NOW))).toBe(true)
		expect(first.productionClock).toEqual(clock())
		expect(second.productionClock).toEqual(clock())
		expect(first.productionClock).never.toBe(second.productionClock)
		expect(first.base.shrines).never.toBe(second.base.shrines)
		expect(PlayerDataTemplate.productionClock).toBeNil()
		local retained = first.productionClock
		expect((ProfileSchema.Prepare(first, neverGenerate, NOW + 300))).toBe(true)
		expect(first.productionClock).toBe(retained)
		expect(first.productionClock).toEqual(clock())
		expect(first.currency.gold).toBe(Configuration.startingGold)
		expect(first.materials).toEqual({})
		expect(first.mythlings).toEqual({})
	end)

	for _, version in { 4, 5, 6 } do
		it(`adds only empty accounting and a fresh clock to schema {version}`, function()
			local data = savedData(version)
			data.profile.lastLoginAt = 1
			data.currency.gold = 9876
			data.materials.fire_material = { total = 312 }
			data.mythlings.kept = worker()
			data.base.stands["1"] = {
				production = {
					lastAccruedAt = 200,
					materials = { essence = { stored = 20, progress = 0.75 } },
				},
			}
			data.craftingJobs.kept = {
				status = "Active",
				deadline = 4000,
				reservations = { equipment = 1, materials = { essence = 5 } },
			}
			data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 1 }
			data.transactions = { revision = 7, receipts = { kept = { opaque = true } } }
			data.base.shrines.first.futureField = { retained = true }
			local expected = copy(data)
			expected.version = Configuration.schemaVersion
			expected.productionClock = clock()
			for _, record in expected.base.shrines do
				addAccounting(record)
			end
			local base, shrines, first, second, owned =
				data.base,
				data.base.shrines,
				data.base.shrines.first,
				data.base.shrines.second,
				data.mythlings.kept

			expect((ProfileSchema.Prepare(data, neverGenerate, NOW))).toBe(true)
			expect(data).toEqual(expected)
			expect(data.base).toBe(base)
			expect(data.base.shrines).toBe(shrines)
			expect(data.base.shrines.first).toBe(first)
			expect(data.base.shrines.second).toBe(second)
			expect(data.mythlings.kept).toBe(owned)
			expect(first.workerIdsBySlot).never.toBe(second.workerIdsBySlot)
			expect(first.workerIdsBySlot).toEqual({})
			expect(second.workerIdsBySlot).toEqual({})
			local retainedClock = data.productionClock
			expect((ProfileSchema.Prepare(data, neverGenerate, NOW + 500))).toBe(true)
			expect(data.productionClock).toBe(retainedClock)
			expect(data).toEqual(expected)
			local reloaded = HttpService:JSONDecode(HttpService:JSONEncode(data))
			expect((ProfileSchema.Prepare(reloaded, neverGenerate, NOW + 900))).toBe(true)
			expect(reloaded).toEqual(expected)
		end)
	end

	for _, version in SUPPORTED_VERSIONS do
		it(
			`retains complete schema {version} accounting and its existing schedule exactly`,
			function()
				local data = savedData(version)
				data.productionClock =
					{ lastAccruedAt = 600.5, nextBatchAt = 600.75, futureField = 4 }
				for _, record in data.base.shrines do
					addAccounting(record)
				end
				local first = data.base.shrines.first
				first.stored = 4_000 -- Existing output is retained even above today's capacity.
				first.progress = 0.875
				first.newWork = 2.75
				first.workerIdsBySlot = { ["1"] = "kept" }
				data.mythlings.kept = worker()
				local owned, assignments, retainedClock =
					data.mythlings.kept, first.workerIdsBySlot, data.productionClock
				local expected = copy(data)
				expected.version = Configuration.schemaVersion

				expect((ProfileSchema.Prepare(data, neverGenerate, NOW))).toBe(true)
				expect(data).toEqual(expected)
				expect(data.base.shrines.first).toBe(first)
				expect(first.workerIdsBySlot).toBe(assignments)
				expect(data.productionClock).toBe(retainedClock)
				expect(data.mythlings.kept).toBe(owned)
				local reloaded = HttpService:JSONDecode(HttpService:JSONEncode(data))
				expect((ProfileSchema.Prepare(reloaded, neverGenerate, NOW + 900))).toBe(true)
				expect(reloaded).toEqual(expected)
			end
		)
	end

	it("uses an existing legacy clock while adding only absent Shrine accounting", function()
		local data = savedData(6)
		data.productionClock = { lastAccruedAt = 200.5, nextBatchAt = 200.75 }
		local retainedClock = data.productionClock
		expect((ProfileSchema.Prepare(data, neverGenerate, NOW))).toBe(true)
		expect(data.productionClock).toBe(retainedClock)
		expect(data.productionClock).toEqual({ lastAccruedAt = 200.5, nextBatchAt = 200.75 })
		expect(data.base.shrines.first.stored).toBe(0)
		expect(data.base.shrines.second.stored).toBe(0)
	end)

	it(
		"does not expose accounting fields, assignments, or the clock in the current projection",
		function()
			local data = savedData(7)
			data.base.shrines.first.stored = 40
			data.base.shrines.first.progress = 0.25
			data.base.shrines.first.newWork = 0.5
			data.base.shrines.first.workerIdsBySlot = { ["1"] = "kept" }
			data.mythlings.kept = worker()
			expect((ProfileSchema.Prepare(data, neverGenerate, NOW))).toBe(true)
			local projection = Projection.Build(data)
			expect(projection.productionClock).toBeNil()
			expect(projection.base.shrines.first).toEqual({
				id = "first",
				shrineId = "fire_shrine",
				buildSlotId = 1,
				level = 1,
			})
			expect(projection.base.shrines.first).never.toBe(data.base.shrines.first)
		end
	)

	it(
		"does not recreate a lost clock on initialized current profiles, even with fresh sentinels",
		function()
			local data = savedData(7)
			data.productionClock = nil
			expectRejected(data, "MissingProductionClock")
			data.base.shrines = {}
			expectRejected(data, "MissingProductionClock")
			data.profile.userId = 0
			data.profile.createdAt = 0
			expectRejected(data, "MissingProductionClock")
		end
	)

	for _, version in { 4, 5, 6 } do
		it(`rejects existing schema {version} accounting that has lost its schedule`, function()
			local data = savedData(version)
			addAccounting(data.base.shrines.first)
			expectRejected(data, "MissingProductionClock")
		end)
	end

	for _, version in SUPPORTED_VERSIONS do
		for _, field in { "stored", "progress", "newWork", "workerIdsBySlot" } do
			it(
				`rejects partial schema {version} accounting missing {field} without backfilling`,
				function()
					local data = savedData(version)
					addAccounting(data.base.shrines.first)
					data.base.shrines.first[field] = nil
					data.productionClock = clock()
					expectRejected(data, "InvalidShrineProduction")
				end
			)
		end
	end

	it("rejects missing accounting on an initialized current Shrine", function()
		local data = savedData(7)
		data.base.shrines.first = shrine("first", 1)
		expectRejected(data, "InvalidShrineProduction")
	end)

	it(
		"does not apply staged legacy slot or accounting defaults when another record is corrupt",
		function()
			local data = savedData(4)
			data.base.shrines.first.buildSlotId = nil
			data.base.shrines.first.level = nil
			data.base.shrines.second.stored = 12
			expectRejected(data, "InvalidShrineProduction")
		end
	)

	it("does not commit staged legacy defaults when the existing clock is malformed", function()
		local data = savedData(4)
		data.base.shrines.first.buildSlotId = nil
		data.base.shrines.first.level = nil
		data.productionClock = { lastAccruedAt = 100, nextBatchAt = 100 }
		expectRejected(data)
	end)

	it("does not repair schema 6 slot or level corruption while adding accounting", function()
		for _, field in { "buildSlotId", "level" } do
			local data = savedData(6)
			data.base.shrines.first[field] = nil
			expectRejected(data, "InvalidBase")
		end
	end)

	local invalidNumbers: { { label: string, value: unknown } } = {
		{ label = "negative", value = -1 },
		{ label = "NaN", value = 0 / 0 },
		{ label = "infinite", value = math.huge },
		{ label = "unsafe", value = 9_007_199_254_740_992 },
		{ label = "string", value = "0" },
		{ label = "boolean", value = false },
	}
	for _, field in { "stored", "progress", "newWork" } do
		for _, invalid in invalidNumbers do
			it(`rejects {invalid.label} {field} without erasing earned state`, function()
				local data = savedData(7)
				data.base.shrines.first[field] = invalid.value
				expectRejected(data, "InvalidShrineProduction")
			end)
		end
	end

	it("requires whole stored Materials and unfinished progress below one", function()
		local data = savedData(7)
		data.base.shrines.first.stored = 1.5
		expectRejected(data, "InvalidShrineProduction")
		data = savedData(7)
		data.base.shrines.first.progress = 1
		expectRejected(data, "InvalidShrineProduction")
	end)

	local invalidClocks: { { label: string, value: unknown } } = {
		{ label = "non-table", value = true },
		{ label = "missing last", value = { nextBatchAt = 1 } },
		{ label = "missing next", value = { lastAccruedAt = 0 } },
		{ label = "negative last", value = { lastAccruedAt = -1, nextBatchAt = 0 } },
		{ label = "no advancement", value = { lastAccruedAt = 10, nextBatchAt = 10 } },
		{ label = "backwards", value = { lastAccruedAt = 10, nextBatchAt = 9 } },
		{
			label = "beyond batch",
			value = { lastAccruedAt = 10, nextBatchAt = 10 + Production.batchIntervalSeconds + 0.1 },
		},
		{ label = "infinite", value = { lastAccruedAt = 0, nextBatchAt = math.huge } },
		{ label = "NaN", value = { lastAccruedAt = 0 / 0, nextBatchAt = 1 } },
	}
	for _, invalid in invalidClocks do
		it(`rejects a {invalid.label} existing accounting clock`, function()
			local data = savedData(7)
			data.productionClock = invalid.value
			expectRejected(data)
		end)
	end

	for _, invalid in invalidNumbers do
		it(`rejects a {invalid.label} initialization time atomically`, function()
			local data = savedData(6)
			local before = copy(data)
			local ok = ProfileSchema.Prepare(data, neverGenerate, invalid.value :: any)
			expect(ok).toBe(false)
			expect(data).toEqual(before)
		end)
	end

	it("accepts zero and fractional initialization times without rounding the schedule", function()
		for _, now in { 0, 100.25 } do
			local data = savedData(6)
			expect((ProfileSchema.Prepare(data, neverGenerate, now))).toBe(true)
			expect(data.productionClock).toEqual({
				lastAccruedAt = now,
				nextBatchAt = now + Production.batchIntervalSeconds,
			})
		end
	end)

	it(
		"retains canonical slot assignments within each Shrine's unlocked worker capacity",
		function()
			local data = savedData(7)
			data.base.shrines.first.level = 3
			data.base.shrines.first.workerIdsBySlot = { ["1"] = "one", ["3"] = "three" }
			data.base.shrines.second.workerIdsBySlot = { ["1"] = "other" }
			for _, id in { "one", "three", "other" } do
				data.mythlings[id] = worker()
			end
			local before = copy(data)
			expect((ProfileSchema.Prepare(data, neverGenerate, NOW))).toBe(true)
			expect(data).toEqual(before)
		end
	)

	local invalidSlots: { unknown } = { "0", "01", "1.0", "-1", "4", "two", 1 }
	for _, rawSlot in invalidSlots do
		it(`rejects noncanonical or unavailable worker slot {tostring(rawSlot)}`, function()
			local data = savedData(7)
			data.mythlings.kept = worker()
			data.base.shrines.first.workerIdsBySlot = { [rawSlot :: any] = "kept" }
			expectRejected(data)
		end)
	end

	it("rejects a numerically valid worker slot that is locked at the Shrine's level", function()
		local data = savedData(7)
		data.mythlings.kept = worker()
		data.base.shrines.first.workerIdsBySlot = { ["2"] = "kept" }
		expectRejected(data)
	end)

	it("rejects malformed or unowned worker references", function()
		local malformed: { unknown } = { false, 1, "", "not_owned" }
		for _, value in malformed do
			local data = savedData(7)
			data.base.shrines.first.workerIdsBySlot = { ["1"] = value }
			expectRejected(data)
		end
		local data = savedData(7)
		data.base.shrines.first.workerIdsBySlot = "invalid"
		expectRejected(data)
	end)

	it("rejects duplicate assignment within one Shrine and across different Shrines", function()
		local data = savedData(7)
		data.mythlings.kept = worker()
		data.base.shrines.first.level = 2
		data.base.shrines.first.workerIdsBySlot = { ["1"] = "kept", ["2"] = "kept" }
		expectRejected(data)
		data.base.shrines.first.workerIdsBySlot = { ["1"] = "kept" }
		data.base.shrines.second.workerIdsBySlot = { ["1"] = "kept" }
		expectRejected(data)
	end)

	it(
		"rejects simultaneous legacy stand and Shrine assignments without clearing either",
		function()
			local data = savedData(7)
			data.mythlings.kept = worker()
			data.mythlings.kept.standId = 1
			data.base.stands["1"] = {}
			data.base.shrines.first.workerIdsBySlot = { ["1"] = "kept" }
			expectRejected(data)
		end
	)
end)
