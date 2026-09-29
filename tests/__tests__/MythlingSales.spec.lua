--!strict
-- ServerStorage/Tests/__tests__/MythlingSales.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local MythlingSales = require(ServerScriptService.Domain.Inventory.MythlingSales)
local MythlingEvolution = require(ServerScriptService.Domain.Production.MythlingEvolution)
local ShrineAccrual = require(ServerScriptService.Domain.Production.ShrineAccrual)
local ShrineAssignments = require(ServerScriptService.Domain.Production.ShrineAssignments)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }
local GOLD_VALUES = { 25, 100, 300 }
local MAX_SAFE_INTEGER = 2 ^ 53 - 1

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): MythlingSales.Metadata
	local definitions: MythlingSales.Metadata = { forms = {}, shrines = {} }
	for _, elementId in ELEMENTS do
		for form, goldValue in GOLD_VALUES do
			definitions.forms[`test_{elementId}_{form}`] = {
				element = elementId,
				baseYieldPerHour = form * 3_600,
				sale = { gold = goldValue },
			}
		end
		definitions.shrines[`test_{elementId}_shrine`] = {
			element = elementId,
			materialId = `test_{elementId}_material`,
			levels = {
				[1] = { capacity = 300, workerSlots = 1 },
				[2] = { capacity = 1_200, workerSlots = 2 },
				[3] = { capacity = 3_600, workerSlots = 3 },
			},
		}
	end
	return definitions
end

local function accountingMetadata(definitions: MythlingSales.Metadata): ShrineAccrual.Metadata
	local accounting: ShrineAccrual.Metadata = { forms = {}, shrines = definitions.shrines }
	for id, definition in definitions.forms do
		accounting.forms[id] = definition
	end
	return accounting
end

local function state(): MythlingSales.State
	local production: MythlingSales.State = {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		shrines = {},
		workers = {},
	}
	for _, elementId in ELEMENTS do
		production.workers[`worker_{elementId}`] = {
			formId = `test_{elementId}_1`,
			level = 1,
			xp = 0,
			pendingXp = 0,
		}
		production.shrines[`shrine_{elementId}`] = {
			shrineId = `test_{elementId}_shrine`,
			level = 1,
			workerIdsBySlot = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}
	end
	return production
end

local function request(elementId: string?, form: number?): MythlingSales.Request
	return {
		workerId = `worker_{elementId or "fire"}`,
		expectedFormId = `test_{elementId or "fire"}_{form or 1}`,
		expectedGoldValue = GOLD_VALUES[form or 1],
	}
end

local function sell(
	production: MythlingSales.State,
	gold: number,
	now: number,
	saleRequest: MythlingSales.Request?,
	definitions: MythlingSales.Metadata?
): MythlingSales.Result
	local result, saleError = MythlingSales.Sell(
		production,
		gold,
		now,
		saleRequest or request(),
		definitions or metadata()
	)
	assert(result, `[MythlingSales.spec] Expected sale success: {tostring(saleError)}`)
	expect(saleError).toBeNil()
	return result
end

local function expectRejected(
	production: MythlingSales.State,
	gold: number,
	now: number,
	saleRequest: any,
	expectedCode: string,
	definitions: MythlingSales.Metadata?
)
	local before = copy(production)
	local result, saleError =
		MythlingSales.Sell(production, gold, now, saleRequest, definitions or metadata())
	expect(result).toBeNil()
	expect(saleError).toBe(expectedCode)
	expect(production).toEqual(before)
end

local function accrue(production: MythlingSales.State, now: number): MythlingSales.State
	local result, accrualError =
		ShrineAccrual.Accrue(production, now, accountingMetadata(metadata()))
	assert(result, `[MythlingSales.spec] Expected accrual success: {tostring(accrualError)}`)
	return result
end

describe("MythlingSales", function()
	it("uses each synthetic form's 25, 100, or 300 Gold value across all six elements", function()
		for _, elementId in ELEMENTS do
			for form, goldValue in GOLD_VALUES do
				local production = state()
				local workerId = `worker_{elementId}`
				production.workers[workerId].formId = `test_{elementId}_{form}`
				local result = sell(production, 100, 0, request(elementId, form))
				expect(result).toEqual({
					production = result.production,
					gold = 100 + goldValue,
					workerId = workerId,
					formId = `test_{elementId}_{form}`,
					goldGranted = goldValue,
				})
				expect(result.production.workers[workerId]).toBeNil()
				expect(production.workers[workerId]).never.toBeNil()
			end
		end
	end)

	it("removes only the selected instance and allows sale of the final owned Mythling", function()
		local production = state()
		production.workers.fire_duplicate = copy(production.workers.worker_fire)
		local result = sell(production, 0, 0)
		expect(result.production.workers.fire_duplicate).toEqual(production.workers.fire_duplicate)
		expect(result.production.workers.worker_water).toEqual(production.workers.worker_water)
		local finalCopy = state()
		finalCopy.workers = { worker_fire = finalCopy.workers.worker_fire }
		local finalSale = sell(finalCopy, 0, 0)
		expect(finalSale.production.workers).toEqual({})
		expect(finalSale.gold).toBe(25)
		expect(finalSale.production.shrines).toEqual(finalCopy.shrines)
	end)

	it(
		"ignores XP, inactive legacy values, acquisition route, and rarity when resolving value",
		function()
			for _, level in { 1, 50, 100 } do
				for _, route in { "capture", "evolution", "retained" } do
					local production = state()
					production.workers.worker_fire.level = level
					production.workers.worker_fire.xp = 19.25
					production.workers.worker_fire.pendingXp = 0.75
					local legacy = production.workers.worker_fire :: any
					legacy.luck = 99
					legacy.traitId = "legacy_lucky"
					legacy.acquisitionRoute = route
					legacy.salePrice = 999_999
					local definitions = metadata()
					local definition = definitions.forms.test_fire_1 :: any
					definition.rarity = "Mythical"
					definition.evolutionStage = 3
					definition.sale.gold = 57
					local quoted = request()
					quoted.expectedGoldValue = 57
					local result = sell(production, 10, 0, quoted, definitions)
					expect(result.goldGranted).toBe(57)
					expect(result.gold).toBe(67)
				end
			end
		end
	)

	it("uses the evolved current form and rejects a selection quoted before evolution", function()
		local production = state()
		production.workers.worker_fire.level = 6
		local definitions = metadata()
		local evolutionMetadata: MythlingEvolution.Metadata = {
			forms = {},
			shrines = definitions.shrines,
		}
		for id, form in definitions.forms do
			evolutionMetadata.forms[id] =
				{ element = form.element, baseYieldPerHour = form.baseYieldPerHour }
		end
		evolutionMetadata.forms.test_fire_1.evolution =
			{ targetFormId = "test_fire_2", requiredLevel = 6 }
		local evolved, evolutionError = MythlingEvolution.Evolve(production, 0, {
			workerId = "worker_fire",
			expectedFormId = "test_fire_1",
			expectedTargetFormId = "test_fire_2",
		}, evolutionMetadata)
		assert(
			evolved,
			`[MythlingSales.spec] Expected evolution fixture: {tostring(evolutionError)}`
		)
		expectRejected(evolved, 0, 0, request(), "FormChanged")
		local evolvedSale = sell(evolved, 0, 0, request("fire", 2))
		local caught = state()
		caught.workers.worker_fire.formId = "test_fire_2"
		local caughtSale = sell(caught, 0, 0, request("fire", 2))
		expect(evolvedSale.goldGranted).toBe(100)
		expect(caughtSale.goldGranted).toBe(evolvedSale.goldGranted)
	end)

	it(
		"rejects assignments in any slot before any sale or elapsed settlement is committed",
		function()
			for slot = 1, 3 do
				local production = state()
				production.shrines.shrine_fire.level = 3
				production.shrines.shrine_fire.workerIdsBySlot[tostring(slot)] = "worker_fire"
				production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
				expectRejected(production, 100, 10, request(), "WorkerAlreadyAssigned")
			end
		end
	)

	it("requires unassignment even when full but never requires collection before sale", function()
		local production = state()
		production.shrines.shrine_fire.stored = 300
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		expectRejected(production, 0, 10, request(), "WorkerAlreadyAssigned")
		local removed, removalError = ShrineAssignments.Remove(production, 0, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}, accountingMetadata(metadata()))
		assert(
			removed,
			`[MythlingSales.spec] Expected full-Shrine removal: {tostring(removalError)}`
		)
		local result = sell(removed, 0, 10)
		expect(result.gold).toBe(25)
		expect(result.production.shrines.shrine_fire.stored).toBe(300)
		expect(result.production.shrines.shrine_fire.workerIdsBySlot).toEqual({})
		expect(result.production.workers.worker_fire).toBeNil()
		expect(result.production.nextBatchAt).toBe(11)
	end)

	it("requires unassignment and preserves earned Shrine work through a mid-batch sale", function()
		local production = state()
		production.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		production.shrines.shrine_fire.progress = 0.25
		production.shrines.shrine_fire.stored = 7
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		local removed, removalError = ShrineAssignments.Remove(production, 0.5, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}, accountingMetadata(metadata()))
		assert(removed, `[MythlingSales.spec] Expected unassignment: {tostring(removalError)}`)
		local result = sell(removed, 0, 0.75)
		expect(result.production.workers.worker_fire).toBeNil()
		expect(result.production.shrines.shrine_fire.stored).toBe(7)
		expect(result.production.shrines.shrine_fire.progress).toBe(0.25)
		expect(result.production.shrines.shrine_fire.newWork).toBe(0.5)
		expect(result.production.workers.worker_water.pendingXp).toBe(0.75)
		expect(result.production.workers.worker_water.xp).toBe(0)
		expect(result.production.lastAccruedAt).toBe(0.75)
		expect(result.production.nextBatchAt).toBe(1)
		local settled = accrue(result.production, 1)
		expect(settled.shrines.shrine_fire.stored).toBe(7)
		expect(settled.shrines.shrine_fire.progress).toBe(0.75)
		expect(settled.workers.worker_water.xp).toBe(1)
		expect(settled.workers.worker_fire).toBeNil()
	end)

	it(
		"settles due output and XP without changing the sale price or redirecting sold XP",
		function()
			local production = state()
			production.shrines.shrine_fire.progress = 0.25
			production.shrines.shrine_fire.newWork = 1.25
			production.workers.worker_fire.level = 5
			production.workers.worker_fire.xp = 599.5
			production.workers.worker_fire.pendingXp = 0.5
			production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
			production.workers.worker_water.pendingXp = 0.25
			local result = sell(production, 100, 1)
			expect(result.gold).toBe(125)
			expect(result.production.shrines.shrine_fire.stored).toBe(1)
			expect(result.production.shrines.shrine_fire.progress).toBe(0.5)
			expect(result.production.shrines.shrine_fire.newWork).toBe(0)
			expect(result.production.workers.worker_water.xp).toBe(1.25)
			expect(result.production.workers.worker_water.pendingXp).toBe(0)
			expect(result.production.workers.worker_fire).toBeNil()
			expect(result.production.nextBatchAt).toBe(2)
		end
	)

	it(
		"rejects stale prices, unknown IDs, and retries without selling a replacement instance",
		function()
			local production = state()
			local stale = request()
			stale.expectedGoldValue = 100
			expectRejected(production, 0, 0, stale, "PriceChanged")
			local missing = request()
			missing.workerId = "not_owned"
			expectRejected(production, 0, 0, missing, "WorkerNotOwned")
			local result = sell(production, 0, 0)
			expectRejected(result.production, result.gold, 0, request(), "WorkerNotOwned")
			result.production.workers.replacement_fire = copy(production.workers.worker_fire)
			expectRejected(result.production, result.gold, 0, request(), "WorkerNotOwned")
			expect(result.production.workers.replacement_fire).toEqual(
				production.workers.worker_fire
			)
		end
	)

	it("rejects malformed, extended, or non-plain sale requests", function()
		local production = state()
		expectRejected(production, 0, 0, nil, "InvalidRequest")
		expectRejected(production, 0, 0, "sell", "InvalidRequest")
		for _, field in { "workerId", "expectedFormId" } do
			for _, badValue in { "", string.rep("x", 129), 3, false } do
				local malformed = request() :: any
				malformed[field] = badValue
				expectRejected(production, 0, 0, malformed, "InvalidRequest")
			end
		end
		for _, badValue in { 0, -1, 1.5, math.huge, 0 / 0, 2 ^ 53, "25" } do
			local malformed = request() :: any
			malformed.expectedGoldValue = badValue
			expectRejected(production, 0, 0, malformed, "InvalidRequest")
		end
		for _, field in { "workerId", "expectedFormId", "expectedGoldValue" } do
			local missing = request() :: any
			missing[field] = nil
			expectRejected(production, 0, 0, missing, "InvalidRequest")
		end
		local extra = request() :: any
		extra.quantity = 2
		expectRejected(production, 0, 0, extra, "InvalidRequest")
		expectRejected(production, 0, 0, setmetatable(request(), {}), "InvalidRequest")
	end)

	it("rejects malformed currency and allows only safe whole-Gold sums", function()
		for _, invalidGold in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53 } do
			expectRejected(state(), invalidGold, 0, request(), "InvalidCurrency")
		end
		expectRejected(state(), "100" :: any, 0, request(), "InvalidCurrency")
		expectRejected(state(), nil :: any, 0, request(), "InvalidCurrency")
		local atLimit = sell(state(), MAX_SAFE_INTEGER - 25, 0)
		expect(atLimit.gold).toBe(MAX_SAFE_INTEGER)
		expectRejected(state(), MAX_SAFE_INTEGER - 24, 0, request(), "ArithmeticOverflow")
		local definitions = metadata()
		definitions.forms.test_fire_1.sale = { gold = MAX_SAFE_INTEGER }
		local maximumQuote = request()
		maximumQuote.expectedGoldValue = MAX_SAFE_INTEGER
		expect(sell(state(), 0, 0, maximumQuote, definitions).gold).toBe(MAX_SAFE_INTEGER)
		expectRejected(state(), 1, 0, maximumQuote, "ArithmeticOverflow", definitions)
	end)

	it("distinguishes unsellable forms from malformed sale definitions", function()
		local unavailable = metadata()
		unavailable.forms.test_fire_1.sale = nil
		expectRejected(state(), 0, 0, request(), "NotSellable", unavailable)
		local badSales: { any } = {
			false,
			"sell",
			{},
			{ gold = 0 },
			{ gold = -1 },
			{ gold = 1.5 },
			{ gold = math.huge },
			{ gold = 0 / 0 },
			{ gold = 2 ^ 53 },
			{ gold = "25" },
			setmetatable({ gold = 25 }, {}),
		}
		for _, badSale in badSales do
			local definitions = metadata()
			local dynamicForm = definitions.forms.test_fire_1 :: any
			dynamicForm.sale = badSale
			expectRejected(state(), 0, 0, request(), "InvalidSaleDefinition", definitions)
		end
	end)

	it(
		"rejects malformed metadata and propagates invalid accounting and backdated changes",
		function()
			local production = state()
			local before = copy(production)
			local badMetadata: { any } =
				{ false, {}, { forms = false, shrines = {} }, setmetatable(metadata(), {}) }
			for _, definitions in badMetadata do
				local result, saleError =
					MythlingSales.Sell(production, 0, 0, request(), definitions)
				expect(result).toBeNil()
				expect(saleError).toBe("InvalidMetadata")
				expect(production).toEqual(before)
			end
			production.shrines.shrine_fire.progress = -0.1
			expectRejected(production, 0, 0, request(), "InvalidShrine")
			production.shrines.shrine_fire.progress = 0
			production.lastAccruedAt = 10
			production.nextBatchAt = 11
			expectRejected(production, 0, 9, request(), "BackdatedChange")
		end
	)

	it("does not remove a worker or grant Gold when pending XP settlement overflows", function()
		local production = state()
		production.workers.worker_fire.xp = 1
		production.workers.worker_fire.pendingXp = MAX_SAFE_INTEGER
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		expectRejected(production, 100, 1, request(), "ArithmeticOverflow")
		expect(production.workers.worker_fire).never.toBeNil()
		expect(production.shrines.shrine_water.stored).toBe(0)
	end)

	it(
		"matches online and offline settlement through JSON reconnect without replaying sales",
		function()
			local production = state()
			production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
			local online = copy(production)
			for second = 1, 10 do
				online = accrue(online, second)
			end
			local onlineSale = sell(online, 100, 10.5)
			local offlineSale = sell(copy(production), 100, 10.5)
			expect(offlineSale).toEqual(onlineSale)
			local restored = copy(offlineSale)
			expect(restored).toEqual(offlineSale)
			expectRejected(restored.production, restored.gold, 10.5, request(), "WorkerNotOwned")
			expect(accrue(restored.production, 20)).toEqual(accrue(offlineSale.production, 20))
			expect(restored.production.workers.worker_water.xp).toBe(10)
			expect(restored.production.workers.worker_water.pendingXp).toBe(0.5)
		end
	)

	it("accepts frozen inputs and detaches every retained accounting record", function()
		local production = state()
		local definitions = metadata()
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		local before = copy(production)
		local metadataBefore = copy(definitions)
		FreezeUtil.DeepFreeze(production)
		FreezeUtil.DeepFreeze(definitions)
		local result = sell(production, 100, 0, request(), definitions)
		expect(production).toEqual(before)
		expect(definitions).toEqual(metadataBefore)
		expect(result.production).never.toBe(production)
		expect(result.production.workers).never.toBe(production.workers)
		expect(result.production.shrines).never.toBe(production.shrines)
		for id, worker in result.production.workers do
			expect(worker).never.toBe(production.workers[id])
		end
		for id, shrine in result.production.shrines do
			expect(shrine).never.toBe(production.shrines[id])
			expect(shrine.workerIdsBySlot).never.toBe(production.shrines[id].workerIdsBySlot)
		end
		result.production.workers.worker_water.xp = 99
		result.production.shrines.shrine_water.workerIdsBySlot["1"] = nil
		expect(production.workers.worker_water.xp).toBe(0)
		expect(production.shrines.shrine_water.workerIdsBySlot["1"]).toBe("worker_water")
	end)

	it("forwards configured batch timing, activity XP, and level scaling to settlement", function()
		local production = state()
		production.nextBatchAt = 2
		production.workers.worker_water.level = 2
		production.shrines.shrine_water.workerIdsBySlot["1"] = "worker_water"
		local result, saleError = MythlingSales.Sell(
			production,
			100,
			2,
			request(),
			metadata(),
			{ batchIntervalSeconds = 2, baseXpPerSecond = 3 },
			{ levelCap = 100, xpPerLevel = 120, yieldGainPerLevel = 0.2 }
		)
		assert(result, `[MythlingSales.spec] Expected configured sale: {tostring(saleError)}`)
		expect(result.gold).toBe(125)
		expect(result.production.nextBatchAt).toBe(4)
		expect(result.production.shrines.shrine_water.stored).toBe(2)
		expect(result.production.shrines.shrine_water.progress).toBeCloseTo(0.4, 10)
		expect(result.production.workers.worker_water.xp).toBe(6)
	end)
end)
