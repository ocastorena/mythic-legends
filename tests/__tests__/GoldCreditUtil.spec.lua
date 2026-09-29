--!strict
-- ServerStorage/Tests/__tests__/GoldCreditUtil.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local GoldCreditUtil = require(ServerScriptService.Shared.GoldCreditUtil)
local MaterialDisposalCommand =
	require(ServerScriptService.Services.InventoryService.MaterialDisposalCommand)
local MythlingSaleCommand =
	require(ServerScriptService.Services.InventoryService.MythlingSaleCommand)
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

local function profile(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local ready, problem = ProfileSchema.Prepare(data, function()
		return "gold_station"
	end, 0)
	assert(ready, `[GoldCreditUtil.spec] Invalid fixture: {tostring(problem)}`)
	return data
end

local function job(gold: number, status: ("Active" | "Completed" | "Cancelled")?): Types.CraftingJob
	return {
		status = status or "Active",
		reservations = { equipment = 1, materials = { fire_material = 5 } },
		receipt = {
			version = 1,
			recipeId = "elemental_sword_fire",
			stationId = "gold_station",
			craftingStationId = "basic_crafting_station",
			startedAt = 0,
			completesAt = 60,
			result = {
				definitionId = "elemental_sword",
				finishId = "fire",
				quantity = 1,
				instanceIds = { "crafted_result" },
			},
			paid = { gold = gold, materials = { fire_material = 5 } },
		},
	} :: Types.CraftingJob
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function source(data: Types.PlayerDoc): (MaterialDisposalCommand.DataSource, Player)
	-- Private commands accept opaque identities; their public facade owns engine-Player validation.
	local player = (table.freeze({ UserId = 501 }) :: unknown) :: Player
	return {
		GetLoadedData = function(requester)
			return if requester == player then data else nil
		end,
		Transact = function(requester, request, mutate)
			assert(requester == player, "[GoldCreditUtil.spec] Wrong profile")
			return Transactions.Run(data, request, function(draft)
				return mutate(draft, 0)
			end, function()
				return true
			end)
		end,
	},
		player
end

describe("GoldCreditUtil", function()
	it(
		"counts only active known paid Gold and preserves legacy jobs without invented claims",
		function()
			local data = profile()
			data.craftingJobs = {
				first = job(50),
				second = job(75),
				free = job(0),
				completed = job(MAX_SAFE_INTEGER, "Completed"),
				cancelled = job(MAX_SAFE_INTEGER, "Cancelled"),
				legacy = { status = "Active", reservations = { equipment = 1, materials = {} } },
			}
			local before = copy(data)
			local reserved, problem = GoldCreditUtil.GetRefundReserve(data)
			expect(reserved).toBe(125)
			expect(problem).toBeNil()
			expect(data).toEqual(before)
			expect(GoldCreditUtil.CreditToDraft(data, 10)).toBeNil()
			before.currency.gold += 10
			expect(data).toEqual(before)
		end
	)

	it("accepts absent or empty legacy job maps and never creates bookkeeping", function()
		local data = profile()
		local reserved, problem = GoldCreditUtil.GetRefundReserve(data)
		expect(reserved).toBe(0)
		expect(problem).toBeNil()
		local legacy: any = data -- The old load boundary permits a missing job collection.
		legacy.craftingJobs = nil
		expect(GoldCreditUtil.CreditToDraft(data, 0)).toBeNil()
		expect(GoldCreditUtil.CreditToDraft(data, 1)).toBeNil()
		expect(data.currency.gold).toBe(101)
		expect(legacy.craftingJobs).toBeNil()
	end)

	it("credits up to the exact safe bound while preserving every outstanding refund", function()
		local data = profile()
		data.currency.gold = MAX_SAFE_INTEGER - 101
		data.craftingJobs = { first = job(100) }
		local currency: any = data.currency
		currency.legacyTokens = 9
		local jobs = data.craftingJobs
		local before = copy(data)
		expect(GoldCreditUtil.CreditToDraft(data, 1)).toBeNil()
		before.currency.gold += 1
		expect(data).toEqual(before)
		expect(data.currency).toBe(currency)
		expect(data.craftingJobs).toBe(jobs)
		expect(GoldCreditUtil.CreditToDraft(data, 0)).toBeNil()
		expect(GoldCreditUtil.CreditToDraft(data, 1)).toBe("ArithmeticOverflow")
		expect(data).toEqual(before)
	end)

	it("rejects unsafe current balance plus refunds even for a zero credit", function()
		local data = profile()
		data.currency.gold = MAX_SAFE_INTEGER
		data.craftingJobs = { active = job(1) }
		local before = copy(data)
		expect(GoldCreditUtil.CreditToDraft(data, 0)).toBe("ArithmeticOverflow")
		expect(data).toEqual(before)
	end)

	it("rejects an overflowing sum of otherwise valid claims without mutation", function()
		local data = profile()
		data.currency.gold = 0
		data.craftingJobs = { first = job(MAX_SAFE_INTEGER), second = job(1) }
		local before = copy(data)
		local reserved, problem = GoldCreditUtil.GetRefundReserve(data)
		expect(reserved).toBeNil()
		expect(problem).toBe("ArithmeticOverflow")
		expect(GoldCreditUtil.CreditToDraft(data, 0)).toBe("ArithmeticOverflow")
		expect(data).toEqual(before)
	end)

	it("rejects malformed currency or credit amounts before any write", function()
		for _, value in { -1, 0.5, math.huge, -math.huge, 0 / 0, 2 ^ 53, "1", false, {} } do
			local data = profile()
			table.freeze(data.currency)
			expect(GoldCreditUtil.CreditToDraft(data, value :: any)).toBe("InvalidCurrency")
			expect(data.currency.gold).toBe(100)
			local invalid: any = profile() -- Intentionally invalid saved state at the boundary.
			invalid.currency.gold = value
			table.freeze(invalid.currency)
			expect(GoldCreditUtil.CreditToDraft(invalid, 1)).toBe("InvalidCurrency")
		end
		for _, value in { false, "currency", {}, setmetatable({ gold = 100 }, {}) } do
			local data: any = profile()
			data.currency = value
			expect(GoldCreditUtil.CreditToDraft(data, 1)).toBe("InvalidCurrency")
			expect(data.currency).toBe(value)
		end
		local missing: any = profile()
		missing.currency = nil
		expect(GoldCreditUtil.CreditToDraft(missing, 1)).toBe("InvalidCurrency")
		expect(GoldCreditUtil.CreditToDraft(profile(), nil :: any)).toBe("InvalidCurrency")
	end)

	it(
		"fails closed for malformed jobs and versioned refund claims without touching Gold",
		function()
			local invalidJobs: { any } = {
				false,
				"jobs",
				setmetatable({}, {}),
				{ active = false },
				{ active = setmetatable(job(10), {}) },
				{ active = { status = "Pending" } },
				{ active = { status = "Active", receipt = false } },
				{ active = { status = "Active", receipt = {} } },
				{ active = { status = "Active", receipt = { version = 2, paid = { gold = 10 } } } },
				{ active = { status = "Active", receipt = { version = 1, paid = false } } },
				{ active = { status = "Active", receipt = { version = 1, paid = {} } } },
				{
					active = {
						status = "Active",
						receipt = setmetatable({ version = 1, paid = { gold = 10 } }, {}),
					},
				},
				{
					active = {
						status = "Active",
						receipt = { version = 1, paid = setmetatable({ gold = 10 }, {}) },
					},
				},
			}
			for _, gold in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53, "50", false } do
				table.insert(invalidJobs, {
					active = {
						status = "Active",
						receipt = { version = 1, paid = { gold = gold } },
					},
				})
			end
			for _, jobs in invalidJobs do
				local data: any = profile()
				data.craftingJobs = jobs
				table.freeze(data.currency)
				local reserved, problem = GoldCreditUtil.GetRefundReserve(data)
				expect(reserved).toBeNil()
				expect(problem).toBe("InvalidCraftingState")
				expect(GoldCreditUtil.CreditToDraft(data, 1)).toBe("InvalidCraftingState")
				expect(data.craftingJobs).toBe(jobs)
				expect(data.currency.gold).toBe(100)
			end
		end
	)

	it("releases a cancelled job's own claim before refunding its exact paid Gold", function()
		local data = profile()
		data.currency.gold = MAX_SAFE_INTEGER - 150
		data.craftingJobs = { cancelling = job(100), other = job(50) }
		local before = copy(data)
		expect(GoldCreditUtil.CreditToDraft(data, 100)).toBe("ArithmeticOverflow")
		expect(data).toEqual(before)
		local jobs = assert(data.craftingJobs, "[GoldCreditUtil.spec] Missing crafting jobs")
		jobs.cancelling.status = "Cancelled"
		expect(GoldCreditUtil.CreditToDraft(data, 100)).toBeNil()
		expect(data.currency.gold).toBe(MAX_SAFE_INTEGER - 50)
		local reserved = GoldCreditUtil.GetRefundReserve(data)
		expect(reserved).toBe(50)
		expect(jobs.other).toEqual(before.craftingJobs and before.craftingJobs.other)
	end)

	it("preserves headroom when starting a job replaces owned Gold with an equal claim", function()
		local data = profile()
		data.currency.gold = MAX_SAFE_INTEGER - 100
		data.craftingJobs = { existing = job(100) }
		expect(GoldCreditUtil.CreditToDraft(data, 0)).toBeNil()
		data.currency.gold -= 50
		local jobs = assert(data.craftingJobs, "[GoldCreditUtil.spec] Missing crafting jobs")
		jobs.started = job(50)
		expect(GoldCreditUtil.CreditToDraft(data, 0)).toBeNil()
		local reserved = GoldCreditUtil.GetRefundReserve(data)
		expect(reserved).toBe(150)
		expect(GoldCreditUtil.CreditToDraft(data, 1)).toBe("ArithmeticOverflow")
	end)
end)

describe("sales preserve crafting Gold refunds", function()
	it(
		"rejects a Material sale that would consume refund headroom and keeps its quantity",
		function()
			local data = profile()
			data.currency.gold = MAX_SAFE_INTEGER - 51
			data.materials = { fire_material = { total = 1 } }
			data.craftingJobs = { active = job(50) }
			local before = gameplay(data)
			local dataSource, player = source(data)
			local api = MaterialDisposalCommand.new(dataSource)
			local request: Types.SellMaterialRequest = {
				requestId = "0:refund-safe-material",
				expectedRevision = 0,
				materialId = "fire_material",
				quantity = 1,
				expectedOwnedQuantity = 1,
				expectedUnitGold = 2,
			}
			local result = api.Sell(player, request)
			expect(result.ok).toBe(false)
			expect(result.code).toBe("ArithmeticOverflow")
			expect(gameplay(data)).toEqual(before)
			expect(api.Sell(player, request).replayed).toBe(true)
			expect(gameplay(data)).toEqual(before)
		end
	)

	it("credits the exact remaining Material-sale headroom once and preserves the claim", function()
		local data = profile()
		data.currency.gold = MAX_SAFE_INTEGER - 52
		data.materials = { fire_material = { total = 1 } }
		data.craftingJobs = { active = job(50) }
		local jobs = copy(data.craftingJobs)
		local dataSource, player = source(data)
		local api = MaterialDisposalCommand.new(dataSource)
		local request: Types.SellMaterialRequest = {
			requestId = "0:exact-material",
			expectedRevision = 0,
			materialId = "fire_material",
			quantity = 1,
			expectedOwnedQuantity = 1,
			expectedUnitGold = 2,
		}
		local result = api.Sell(player, request)
		expect(result.ok).toBe(true)
		expect(result.values and result.values.goldBalance).toBe(MAX_SAFE_INTEGER - 50)
		expect(data.materials.fire_material).toBeNil()
		expect(data.craftingJobs).toEqual(jobs)
		expect(api.Sell(player, request).replayed).toBe(true)
		expect(data.currency.gold).toBe(MAX_SAFE_INTEGER - 50)
	end)

	it(
		"rolls back staged Mythling removal and accounting if its sale consumes refund headroom",
		function()
			for _, canAfford in { false, true } do
				local data = profile()
				data.currency.gold = MAX_SAFE_INTEGER - (if canAfford then 75 else 74)
				data.craftingJobs = { active = job(50) }
				data.mythlings.worker = {
					typeId = "mythling_0001",
					variantId = "regular",
					claimedAt = 0,
					level = 1,
					xp = 0,
					pendingXp = 0,
				}
				local before = gameplay(data)
				local dataSource, player = source(data)
				local api = MythlingSaleCommand.new(dataSource, function()
					return 30
				end)
				local result = api.Sell(player, {
					requestId = "0:refund-safe-mythling",
					expectedRevision = 0,
					workerId = "worker",
					expectedFormId = "mythling_0001",
					expectedGoldValue = 25,
				})
				expect(result.ok).toBe(canAfford)
				if canAfford then
					expect(data.currency.gold).toBe(MAX_SAFE_INTEGER - 50)
					expect(data.mythlings.worker).toBeNil()
					expect(data.craftingJobs).toEqual(before.craftingJobs)
				else
					expect(result.code).toBe("ArithmeticOverflow")
					expect(gameplay(data)).toEqual(before)
				end
			end
		end
	)
end)
