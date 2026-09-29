--!strict
-- ServerStorage/Tests/__tests__/ShrineUpgradePurchase.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineUpgradePurchase =
	require(ServerScriptService.Services.BaseService.ShrineUpgradePurchase)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
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
	assert(prepared, `[ShrineUpgradePurchase.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = userId
	data.currency.gold = 16_000
	data.materials = { fire_material = { total = 4_400 } }
	data.mythlings = { worker = worker("mythling_0001"), removed = worker("mythling_0003") }
	local first = shrine("first", "fire_shrine", 1)
	first.workerIdsBySlot = { ["1"] = "worker" }
	data.base.shrines = { first = first }
	return data
end

local function savedShrines(data: Types.PlayerDoc): { [string]: Types.ShrineRecord }
	return (assert(data.base.shrines, "[ShrineUpgradePurchase.spec] Expected Shrine map"))
end

local function upgrade(revision: number, token: string, level: number?): Types.UpgradeShrineRequest
	local previousLevel = level or 1
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineInstanceId = "first",
		expectedLevel = previousLevel,
		expectedMaterialId = "fire_material",
		expectedGoldCost = if previousLevel == 1 then 1_000 else 15_000,
		expectedMaterialQuantity = if previousLevel == 1 then 400 else 4_000,
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
	local dataSource: ShrineUpgradePurchase.DataSource = {
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
	local api = ShrineUpgradePurchase.new(dataSource, function(): number
		state.clockCalls += 1
		assert(state.inCallback, "[ShrineUpgradePurchase.spec] Clock must be inside transaction")
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

describe("ShrineUpgradePurchase", function()
	it(
		"purchases both configured levels for every launch element in atomic transactions",
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
				local materialId = `{content[1]}_material`
				data.materials = { [materialId] = { total = 4_400 } }
				data.mythlings.worker.typeId = content[2]
				local record = savedShrines(data).first
				record.shrineId = `{content[1]}_shrine`
				local f = fixture(data)
				f.state.now = 1
				for previousLevel = 1, 2 do
					local request = upgrade(previousLevel - 1, "six-elements", previousLevel)
					request.expectedMaterialId = materialId
					expect(f.api.Upgrade(f.first, request)).toEqual({
						ok = true,
						revision = previousLevel,
						values = {
							shrineInstanceId = "first",
							previousLevel = previousLevel,
							level = previousLevel + 1,
							materialId = materialId,
							goldSpent = request.expectedGoldCost,
							materialsSpent = request.expectedMaterialQuantity,
							settledAt = 1,
						},
					})
					expect(record.level).toBe(previousLevel + 1)
					expect(record.workerIdsBySlot).toEqual({ ["1"] = "worker" })
					expect(record.stored).toBe(5)
					expect(record.progress).toBeCloseTo(12 / 3_600)
					expect(data.mythlings.worker.xp).toBe(1)
				end
				expect(data.materials).toEqual({})
				expect(data.currency.gold).toBe(0)
				expect(f.state.operations).toEqual({ "Base.UpgradeShrine", "Base.UpgradeShrine" })
				expect(f.state.clockCalls).toBe(2)
				expect(f.state.transactionCalls).toBe(2)
			end
		end
	)

	it("retains pending work and XP without prematurely ending the accounting batch", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.progress = 0.997
		f.state.now = 0.5
		expect(f.api.Upgrade(f.first, upgrade(0, "partial")).ok).toBe(true)
		expect(record.stored).toBe(5)
		expect(record.progress).toBe(0.997)
		expect(record.newWork).toBeCloseTo(12 * 0.5 / 3_600)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.worker.pendingXp).toBe(0.5)
		expect(data.productionClock).toEqual({ lastAccruedAt = 0.5, nextBatchAt = 1 })
		f.state.now = 1
		expect(f.api.Upgrade(f.first, upgrade(1, "boundary", 2)).ok).toBe(true)
		expect(record.stored).toBe(6)
		expect(record.progress).toBeCloseTo(0.997 + 12 / 3_600 - 1)
		expect(record.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.worker.pendingXp).toBe(0)
		expect(data.productionClock).toEqual({ lastAccruedAt = 1, nextBatchAt = 2 })
	end)

	it("settles the old full capacity and resumes only after the purchase timestamp", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.stored = 300
		f.state.now = 1_000
		expect(f.api.Upgrade(f.first, upgrade(0, "full")).ok).toBe(true)
		expect(record.stored).toBe(300)
		expect(record.progress).toBe(0)
		expect(record.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(0)
		f.state.now = 1_300
		expect(f.api.Upgrade(f.first, upgrade(1, "resumed", 2)).ok).toBe(true)
		expect(record.stored).toBe(301)
		expect(record.progress).toBeCloseTo((120 * 12 + 180 * 12.12) / 3_600 - 1)
		expect(data.mythlings.worker.level).toBe(2)
		expect(data.mythlings.worker.xp).toBe(180)
	end)

	it("keeps filling-batch XP and discards old-capacity overflow before upgrading", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.stored = 299
		record.progress = 0.999
		f.state.now = 300
		expect(f.api.Upgrade(f.first, upgrade(0, "fills")).ok).toBe(true)
		expect(record.level).toBe(2)
		expect(record.stored).toBe(300)
		expect(record.progress).toBe(0)
		expect(record.newWork).toBe(0)
		expect(data.mythlings.worker.xp).toBe(1)
	end)

	it(
		"settles all Shrines and unassigned pending XP while changing only the selected level",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local second = shrine("second", "water_shrine", 2)
			second.workerIdsBySlot = { ["1"] = "water" }
			savedShrines(data).second = second
			data.mythlings.water = worker("mythling_0004")
			data.mythlings.removed.pendingXp = 0.25
			f.state.now = 1
			expect(f.api.Upgrade(f.first, upgrade(0, "whole-ledger")).ok).toBe(true)
			expect(second.level).toBe(1)
			expect(second.stored).toBe(5)
			expect(second.progress).toBeCloseTo(12 / 3_600)
			expect(second.workerIdsBySlot).toEqual({ ["1"] = "water" })
			expect(data.mythlings.water.xp).toBe(1)
			expect(data.mythlings.removed.xp).toBe(0.25)
			expect(data.mythlings.removed.pendingXp).toBe(0)
			expect(data.materials).toEqual({ fire_material = { total = 4_000 } })
		end
	)

	it("retains both existing workers when unlocking the final empty assignment slot", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local record = savedShrines(data).first
		record.level = 2
		record.workerIdsBySlot = { ["1"] = "worker", ["2"] = "removed" }
		f.state.now = 1
		expect(f.api.Upgrade(f.first, upgrade(0, "two-workers", 2)).ok).toBe(true)
		expect(record.level).toBe(3)
		expect(record.workerIdsBySlot).toEqual({ ["1"] = "worker", ["2"] = "removed" })
		expect(record.progress).toBeCloseTo((12 + 32) / 3_600)
		expect(data.mythlings.worker.xp).toBe(1)
		expect(data.mythlings.removed.xp).toBe(1)
	end)

	it(
		"permits explicit assignment into the new slot and collection through existing commands",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local workers = ShrineWorkers.new(f.dataSource, function()
				return f.state.now
			end)
			local collector = ShrineCollector.new(f.dataSource, function()
				return f.state.now
			end)
			expect(f.api.Upgrade(f.first, upgrade(0, "upgrade")).ok).toBe(true)
			expect(savedShrines(data).first.workerIdsBySlot).toEqual({ ["1"] = "worker" })
			expect(workers.Assign(f.first, {
				requestId = "1:staff-new-slot",
				expectedRevision = 1,
				shrineInstanceId = "first",
				slotId = 2,
				workerId = "removed",
			}).ok).toBe(true)
			f.state.now = 1
			expect(collector.Collect(f.first, {
				requestId = "2:collect",
				expectedRevision = 2,
				shrineInstanceId = "first",
				expectedMaterialId = "fire_material",
			})).toEqual({
				ok = true,
				revision = 3,
				values = {
					shrineInstanceId = "first",
					materialId = "fire_material",
					collected = 5,
					remaining = 0,
					settledAt = 1,
				},
			})
			expect(savedShrines(data).first.level).toBe(2)
			expect(savedShrines(data).first.workerIdsBySlot).toEqual({
				["1"] = "worker",
				["2"] = "removed",
			})
			expect(savedShrines(data).first.progress).toBeCloseTo((12 + 32) / 3_600)
			expect(data.mythlings.worker.xp).toBe(1)
			expect(data.mythlings.removed.xp).toBe(1)
			expect(data.currency.gold).toBe(15_000)
			expect(data.materials.fire_material.total).toBe(4_005)
			expect(f.state.operations).toEqual({
				"Base.UpgradeShrine",
				"Base.AssignShrineWorker",
				"Production.CollectShrine",
			})
		end
	)

	it(
		"rejects unowned, stale-level, stale-Material, stale-price, and terminal selections",
		function()
			for _, failure in { "owner", "level", "material", "gold", "quantity", "maximum" } do
				local f = fixture()
				local data = f.profiles[f.first]
				local request = upgrade(0, "stale")
				local expectedCode = "PriceChanged"
				if failure == "owner" then
					request.shrineInstanceId = "not_owned"
					expectedCode = "ShrineNotOwned"
				elseif failure == "level" then
					request.expectedLevel = 2
					expectedCode = "LevelChanged"
				elseif failure == "material" then
					request.expectedMaterialId = "water_material"
					expectedCode = "MaterialChanged"
				elseif failure == "gold" then
					request.expectedGoldCost = 999
				elseif failure == "quantity" then
					request.expectedMaterialQuantity = 399
				else
					savedShrines(data).first.level = 3
					request.expectedLevel = 3
					expectedCode = "MaxLevel"
				end
				f.state.now = 300
				local before = gameplay(data)
				expect(f.api.Upgrade(f.first, request)).toEqual({
					ok = false,
					code = expectedCode,
					revision = 1,
				})
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"rejects insufficient Gold or collected matching Materials without committing work",
		function()
			for _, failure in { "gold", "quantity", "missing", "other-element" } do
				local f = fixture()
				local data = f.profiles[f.first]
				local expectedCode = "InsufficientMaterials"
				if failure == "gold" then
					data.currency.gold = 999
					expectedCode = "InsufficientGold"
				elseif failure == "quantity" then
					data.materials.fire_material.total = 399
				elseif failure == "missing" then
					data.materials = {}
				else
					data.materials = { water_material = { total = 4_400 } }
				end
				f.state.now = 300
				local before = gameplay(data)
				expect(f.api.Upgrade(f.first, upgrade(0, "unaffordable")).code).toBe(expectedCode)
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it("never uses uncollected output or outstanding crafting refunds as payment", function()
		for _, reserve in { false, true } do
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire_material.total = 399
			savedShrines(data).first.stored = 300
			if reserve then
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { fire_material = 1_000 } },
					},
				}
			end
			local before = gameplay(data)
			expect(f.api.Upgrade(f.first, upgrade(0, "not-payment")).code).toBe(
				"InsufficientMaterials"
			)
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it("spends owned Materials without releasing matching or other-type reservations", function()
		for _, materialId in { "fire_material", "water_material" } do
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire_material.total = 400
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
			expect(f.api.Upgrade(f.first, upgrade(0, "reserved")).ok).toBe(true)
			expect(data.materials.fire_material).toBeNil()
			expect(data.craftingJobs).toBe(jobs)
			expect(data.craftingJobs).toEqual(jobsBefore)
		end
	end)

	it("rejects malformed request envelopes before entering a transaction", function()
		local invalidRequests: { any } =
			{ false, 1, "request", setmetatable(upgrade(0, "meta"), {}) }
		for _, field in
			{
				"requestId",
				"expectedRevision",
				"shrineInstanceId",
				"expectedLevel",
				"expectedMaterialId",
				"expectedGoldCost",
				"expectedMaterialQuantity",
			}
		do
			local raw: { [string]: any } = copy(upgrade(0, "missing")) :: any
			raw[field] = nil
			table.insert(invalidRequests, raw)
		end
		for _, field in
			{ "now", "level", "player", "gold", "materials", "metadata", "signature", "operation" }
		do
			local raw: { [string]: any } = copy(upgrade(0, "extra")) :: any
			raw[field] = 1
			table.insert(invalidRequests, raw)
		end
		for _, field in
			{ "expectedRevision", "expectedLevel", "expectedGoldCost", "expectedMaterialQuantity" }
		do
			for _, value in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53, "1" } do
				local raw: { [string]: any } = copy(upgrade(0, "number")) :: any
				raw[field] = value
				table.insert(invalidRequests, raw)
			end
		end
		local zeroLevel = upgrade(0, "zero-level")
		zeroLevel.expectedLevel = 0
		table.insert(invalidRequests, zeroLevel)
		for _, field in { "requestId", "shrineInstanceId", "expectedMaterialId" } do
			for _, value in { "", string.rep("x", 129), 10 } do
				local raw: { [string]: any } = copy(upgrade(0, "id")) :: any
				raw[field] = value
				table.insert(invalidRequests, raw)
			end
		end
		for _, request in invalidRequests do
			local f = fixture()
			local before = copy(f.profiles[f.first])
			expect(f.api.Upgrade(f.first, request)).toEqual({
				ok = false,
				code = "InvalidRequest",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it("requires a loaded active profile without attempting to load one", function()
		for _, stateKey in { "available", "active" } do
			local f = fixture()
			if stateKey == "available" then
				f.state.available = false
			else
				f.state.active = false
			end
			local before = copy(f.profiles[f.first])
			expect(f.api.Upgrade(f.first, upgrade(0, "unavailable"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it("replays a success without resampling time or paying and upgrading again", function()
		local f = fixture()
		local request = upgrade(0, "retry")
		f.state.now = 0.5
		local result = f.api.Upgrade(f.first, request)
		local after = copy(f.profiles[f.first])
		f.state.now = 500
		expect(f.api.Upgrade(f.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.callbackCalls).toBe(1)
	end)

	it("binds every selected identity and price field into its receipt signature", function()
		local f = fixture()
		expect(f.api.Upgrade(f.first, upgrade(0, "binding")).ok).toBe(true)
		local after = copy(f.profiles[f.first])
		local changes: { [string]: any } = {
			shrineInstanceId = "other",
			expectedLevel = 2,
			expectedMaterialId = "water_material",
			expectedGoldCost = 999,
			expectedMaterialQuantity = 399,
		}
		for field, value in changes do
			local request: any = upgrade(0, "binding")
			request[field] = value
			expect(f.api.Upgrade(f.first, request).code).toBe("RequestConflict")
		end
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.clockCalls).toBe(1)
	end)

	it("distinguishes adjacent safe whole values in rejected selection receipts", function()
		for _, field in { "expectedLevel", "expectedGoldCost", "expectedMaterialQuantity" } do
			local f = fixture()
			local request: any = upgrade(0, "large-number")
			request[field] = 2 ^ 52
			local rejected = f.api.Upgrade(f.first, request)
			expect(rejected.ok).toBe(false)
			expect(rejected.revision).toBe(1)
			local after = copy(f.profiles[f.first])
			request[field] += 1
			expect(f.api.Upgrade(f.first, request).code).toBe("RequestConflict")
			expect(f.profiles[f.first]).toEqual(after)
			expect(f.state.clockCalls).toBe(1)
		end
	end)

	it("rejects stale revisions and mismatched request-ID prefixes before sampling time", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		expect(f.api.Upgrade(f.first, upgrade(1, "future")).code).toBe("StaleRevision")
		local request = upgrade(0, "wrong-prefix")
		request.requestId = "7:wrong-prefix"
		expect(f.api.Upgrade(f.first, request).code).toBe("InvalidTransaction")
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(0)
	end)

	it("replays rejected payment receipts after later funds allow a fresh purchase", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.currency.gold = 999
		local request = upgrade(0, "poor")
		expect(f.api.Upgrade(f.first, request).code).toBe("InsufficientGold")
		data.currency.gold = 1_000
		expect(f.api.Upgrade(f.first, upgrade(1, "funded")).ok).toBe(true)
		local after = copy(data)
		expect(f.api.Upgrade(f.first, request)).toEqual({
			ok = false,
			code = "InsufficientGold",
			revision = 1,
			replayed = true,
		})
		expect(data).toEqual(after)
		expect(f.state.clockCalls).toBe(2)
	end)

	it(
		"retains receipts, purchased levels, and partial batches through JSON continuation",
		function()
			local f = fixture()
			savedShrines(f.profiles[f.first]).first.progress = 0.997
			f.state.now = 0.5
			local request = upgrade(0, "before-save")
			local result = f.api.Upgrade(f.first, request)
			local restored = fixture(copy(f.profiles[f.first]))
			restored.state.now = 1
			expect(restored.api.Upgrade(restored.first, request)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.state.clockCalls).toBe(0)
			expect(restored.api.Upgrade(restored.first, upgrade(1, "continued", 2)).ok).toBe(true)
			local data = restored.profiles[restored.first]
			expect(data.currency.gold).toBe(0)
			expect(data.materials).toEqual({})
			expect(savedShrines(data).first.level).toBe(3)
			expect(savedShrines(data).first.stored).toBe(6)
			expect(savedShrines(data).first.progress).toBeCloseTo(0.997 + 12 / 3_600 - 1)
			expect(data.mythlings.worker.xp).toBe(1)
			expect(data.mythlings.worker.pendingXp).toBe(0)
		end
	)

	it("isolates ownership, payment, accounting, and receipts to the requesting player", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		local request = upgrade(0, "shared-token")
		expect(f.api.Upgrade(f.first, request).ok).toBe(true)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		f.state.now = 1
		local result = f.api.Upgrade(f.second, request)
		expect(result.ok).toBe(true)
		expect(result.replayed).toBeNil()
		expect(f.profiles[f.first]).toEqual(firstAfter)
		expect(f.profiles[f.second].currency.gold).toBe(15_000)
		expect(f.profiles[f.second].materials.fire_material.total).toBe(4_000)
		expect(f.state.players).toEqual({ f.first, f.second })
	end)

	it(
		"rolls back payment, upgrade, settlement, and receipt if the session ends after callback",
		function()
			local f = fixture()
			local before = copy(f.profiles[f.first])
			f.state.now = 300
			f.state.loseSessionAfterCallback = true
			expect(f.api.Upgrade(f.first, upgrade(0, "lost-session"))).toEqual({
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
			local result = f.api.Upgrade(f.first, upgrade(0, "bad-clock"))
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end)
	end

	it("rejects backdated upgrades without rewinding the accounting cursor", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.productionClock = { lastAccruedAt = 10, nextBatchAt = 11 }
		f.state.now = 9
		local before = gameplay(data)
		expect(f.api.Upgrade(f.first, upgrade(0, "backdated")).code).toBe("BackdatedChange")
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
		it(`rolls back {case.code} clocks without payment or receipts`, function()
			local f = fixture(nil, case.clock)
			local before = copy(f.profiles[f.first])
			expect(f.api.Upgrade(f.first, upgrade(0, "clock-failure"))).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end)
	end

	it(
		"atomically rejects invalid canonical, currency, Inventory, and reservation state",
		function()
			for _, failure in
				{
					"base",
					"progression",
					"legacy",
					"unknown",
					"material",
					"currency",
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
					data.materials.fire_material.total = -1
				elseif failure == "currency" then
					data.currency.gold = -1
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
				local result = f.api.Upgrade(f.first, upgrade(0, "invalid-state"))
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"preserves live identities, unrelated metadata, inactive legacy fields, and purchased state",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire = { total = 17 }
			data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 0 }
			data.base.buildSlotUpgrades = 1
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
			local currencyFields = data.currency :: any
			currencyFields.legacyTokens = 41
			local materialFields = data.materials.fire_material :: any
			materialFields.custom = { note = "retained" }
			local before = gameplay(data)
			local base, records, record, assignments, owned, firstWorker, clock, materials, fire, station, currency =
				data.base,
				savedShrines(data),
				savedShrines(data).first,
				savedShrines(data).first.workerIdsBySlot,
				data.mythlings,
				data.mythlings.worker,
				data.productionClock,
				data.materials,
				data.materials.fire_material,
				data.base.craftingStation,
				data.currency
			expect(f.api.Upgrade(f.first, upgrade(0, "preserve")).ok).toBe(true)
			local expected = copy(before)
			savedShrines(expected).first.level = 2
			expected.materials.fire_material.total = 4_000
			expected.currency.gold = 15_000
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
			expect(data.base.craftingStation).toBe(station)
			expect(data.currency).toBe(currency)
		end
	)
end)
