--!strict
-- ServerStorage/Tests/__tests__/Transactions.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Types = require(ReplicatedStorage.Shared.Types)
local Projection = require(ServerScriptService.Services.DataService.Projection)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

type Mutator = (Types.PlayerDoc) -> Types.TransactionOutcome

local function freshData(): Types.PlayerDoc
	return (
		HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate)) :: unknown
	) :: Types.PlayerDoc
end

local function snapshot(value: unknown): any
	return HttpService:JSONDecode(HttpService:JSONEncode(value))
end

local function gameplaySnapshot(data: Types.PlayerDoc): any
	local result = snapshot(data)
	result.transactions = nil
	return result
end

local function request(
	expectedRevision: number,
	token: string,
	operation: string?,
	signature: string?
): Types.TransactionRequest
	return {
		id = `{expectedRevision}:{token}`,
		expectedRevision = expectedRevision,
		operation = operation or "TestOperation",
		signature = signature or `token={token}`,
	}
end

local function active(): boolean
	return true
end

local function receiptCount(data: Types.PlayerDoc): number
	local state = assert(data.transactions, "[Transactions.spec] Expected data.transactions")
	local count = 0
	for _ in state.receipts do
		count += 1
	end
	return count
end

describe("fresh player data", function()
	it("uses the fresh MVP namespace and scoped fresh-profile defaults", function()
		expect(Configuration.storeName).toBe("MythicLegends_MVP_v1")
		expect(Configuration.schemaVersion).toBe(4)
		expect(PlayerDataTemplate.version).toBe(Configuration.schemaVersion)
		expect(PlayerDataTemplate.currency.gold).toBe(100)
		expect(PlayerDataTemplate.consumables).toBeNil()

		local upgrades = assert(
			PlayerDataTemplate.inventoryUpgrades,
			"[Transactions.spec] Expected PlayerDataTemplate.inventoryUpgrades"
		)
		expect(upgrades).toEqual({ materials = 0, mythlings = 0, equipment = 0 })

		local sword = assert(
			PlayerDataTemplate.equipment.starter_wooden_sword,
			"[Transactions.spec] Expected PlayerDataTemplate.equipment.starter_wooden_sword"
		)
		local shield = assert(
			PlayerDataTemplate.equipment.starter_wooden_shield,
			"[Transactions.spec] Expected PlayerDataTemplate.equipment.starter_wooden_shield"
		)
		expect(sword.definitionId).toBe(Configuration.starterSwordId)
		expect(shield.definitionId).toBe(Configuration.starterShieldId)
		expect(sword.isStarterGrant).toBe(true)
		expect(shield.isStarterGrant).toBe(true)
		expect(PlayerDataTemplate.combatLoadout.primaryWeaponInstanceId).toBe(
			"starter_wooden_sword"
		)
		expect(PlayerDataTemplate.combatLoadout.shieldInstanceId).toBe("starter_wooden_shield")

		local transactions = assert(
			PlayerDataTemplate.transactions,
			"[Transactions.spec] Expected PlayerDataTemplate.transactions"
		)
		expect(transactions.revision).toBe(0)
		expect((next(transactions.receipts))).toBeNil()
		local jobs = assert(PlayerDataTemplate.craftingJobs, "[Transactions.spec] Expected jobs")
		expect((next(jobs))).toBeNil()
	end)
end)

describe("Projection.Build", function()
	it(
		"returns detached public state without private profile, jobs, receipts, or starter flags",
		function()
			local data = freshData()
			data.profile.userId = 8123
			data.materials.fire = { total = 5 }
			data.transactions = {
				revision = 7,
				receipts = {
					["0:hidden"] = {
						expectedRevision = 0,
						operation = "HiddenOperation",
						signature = "secret payload",
						result = { ok = true, revision = 1 },
					},
				},
			}
			data.craftingJobs = {
				hidden_job = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire = 5 } },
				},
			}

			local projection = Projection.Build(data)
			expect(projection.transactionRevision).toBe(7)
			expect(projection.profile).toBeNil()
			expect(projection.transactions).toBeNil()
			expect(projection.receipts).toBeNil()
			expect(projection.craftingJobs).toBeNil()
			expect(projection.equipment.starter_wooden_sword.isStarterGrant).toBeNil()
			expect(projection.equipment.starter_wooden_shield.isStarterGrant).toBeNil()

			projection.currency.gold = 999
			projection.materials.fire.total = 999
			projection.equipment.starter_wooden_sword.definitionId = "tampered"
			projection.base.stands.fake = {}
			expect(data.currency.gold).toBe(100)
			expect(data.materials.fire.total).toBe(5)
			expect(data.equipment.starter_wooden_sword.definitionId).toBe(
				Configuration.starterSwordId
			)
			expect(data.base.stands.fake).toBeNil()

			data.currency.gold = 125
			data.materials.fire.total = 8
			expect(projection.currency.gold).toBe(999)
			expect(projection.materials.fire.total).toBe(999)
		end
	)
end)

describe("Transactions.Run validation and rollback", function()
	it(
		"requires a numeric revision and an id formatted as <expectedRevision>:<unique token>",
		function()
			local invalidRequests: { any } = {
				{
					id = "missing-prefix",
					expectedRevision = 0,
					operation = "Test",
					signature = "a",
				},
				{
					id = "1:wrong-prefix",
					expectedRevision = 0,
					operation = "Test",
					signature = "a",
				},
				{ id = "0:", expectedRevision = 0, operation = "Test", signature = "a" },
				{ id = "0:nan", expectedRevision = 0 / 0, operation = "Test", signature = "a" },
				{ id = "0:operation", expectedRevision = 0, operation = 12, signature = "a" },
				{ id = "0:signature", expectedRevision = 0, operation = "Test", signature = {} },
			}

			for _, invalidRequest in invalidRequests do
				local data = freshData()
				local before = snapshot(data)
				local mutationCalls = 0
				local result = Transactions.Run(data, invalidRequest, function(_draft)
					mutationCalls += 1
					return { ok = true }
				end, active)
				expect(result.ok).toBe(false)
				expect(result.code).toBe("InvalidTransaction")
				expect(result.revision).toBe(0)
				expect(mutationCalls).toBe(0)
				expect(data).toEqual(before)
			end
		end
	)

	it("fails closed when persisted transaction bookkeeping is malformed", function()
		local corruptions: {
			{
				name: string,
				expectedRevision: number,
				apply: (any) -> (),
			}
		} =
			{
				{
					name = "revision",
					expectedRevision = -1,
					apply = function(data)
						data.transactions.revision = "invalid"
					end,
				},
				{
					name = "missing receipts",
					expectedRevision = 0,
					apply = function(data)
						data.transactions.receipts = nil
					end,
				},
				{
					name = "non-table receipts",
					expectedRevision = 0,
					apply = function(data)
						data.transactions.receipts = "invalid"
					end,
				},
			}

		for index, corruption in corruptions do
			local data = freshData()
			corruption.apply(data)
			local before = snapshot(data)
			local mutationCalls = 0
			expect(Transactions.GetRevision(data)).toBe(corruption.expectedRevision)

			local result = Transactions.Run(data, request(0, `corrupt-{index}`), function(_draft)
				mutationCalls += 1
				return { ok = true }
			end, active)
			expect(result.ok).toBe(false)
			expect(result.code).toBe("InvalidTransaction")
			expect(result.revision).toBe(corruption.expectedRevision)
			expect(mutationCalls).toBe(0)
			expect(data).toEqual(before)
		end
	end)

	it("records a stable rejection receipt while rolling back every gameplay edit", function()
		local data = freshData()
		local beforeGameplay = gameplaySnapshot(data)
		local transactionRequest = request(0, "rejected", "Spend", "amount=500")
		local result = Transactions.Run(data, transactionRequest, function(draft)
			draft.currency.gold = 0
			draft.materials.fire = { total = 500 }
			return { ok = false, code = "InsufficientGold", values = { required = 500 } }
		end, active)

		expect(result).toEqual({
			ok = false,
			code = "InsufficientGold",
			values = { required = 500 },
			revision = 1,
		})
		expect(gameplaySnapshot(data)).toEqual(beforeGameplay)
		expect(assert(data.transactions, "[Transactions.spec] Expected data.transactions").revision).toBe(
			1
		)
		expect(receiptCount(data)).toBe(1)
	end)

	local rollbackCases: { { name: string, code: string, mutate: Mutator } } = {
		{
			name = "an exception",
			code = "MutationFailed",
			mutate = function(draft)
				draft.currency.gold = 0
				error("intentional mutation failure")
			end,
		},
		{
			name = "a yield",
			code = "MutationYielded",
			mutate = function(draft)
				draft.currency.gold = 0
				coroutine.yield()
				return { ok = true }
			end,
		},
		{
			name = "a non-finite saved number",
			code = "MutationFailed",
			mutate = function(draft)
				draft.currency.gold = 0 / 0
				return { ok = true }
			end,
		},
		{
			name = "a cyclic saved table",
			code = "MutationFailed",
			mutate = function(draft)
				local cycle: any = {}
				cycle.self = cycle
				local dynamicDraft: any = draft
				dynamicDraft.cycle = cycle
				return { ok = true }
			end,
		},
		{
			name = "a nested result value",
			code = "MutationFailed",
			mutate = function(draft)
				draft.currency.gold = 0
				return { ok = true, values = { nested = {} } } :: any
			end,
		},
	}

	for index, rollbackCase in rollbackCases do
		it(`fully rolls back {rollbackCase.name}`, function()
			local data = freshData()
			local before = snapshot(data)
			local result =
				Transactions.Run(data, request(0, `rollback-{index}`), rollbackCase.mutate, active)
			expect(result.ok).toBe(false)
			expect(result.code).toBe(rollbackCase.code)
			expect(result.revision).toBe(0)
			expect(data).toEqual(before)

			local recovery = Transactions.Run(data, request(0, `recovery-{index}`), function(draft)
				draft.currency.gold += 1
				return { ok = true }
			end, active)
			expect(recovery.ok).toBe(true)
			expect(data.currency.gold).toBe(101)
		end)
	end

	it("rolls back when the profile session is lost before commit", function()
		local data = freshData()
		local before = snapshot(data)
		local activeChecks = 0
		local result = Transactions.Run(data, request(0, "lost-session"), function(draft)
			draft.currency.gold = 999
			return { ok = true }
		end, function()
			activeChecks += 1
			return activeChecks == 1
		end)

		expect(result.ok).toBe(false)
		expect(result.code).toBe("DataUnavailable")
		expect(result.revision).toBe(0)
		expect(activeChecks).toBe(2)
		expect(data).toEqual(before)
	end)

	it("rejects a nested transaction as busy without interrupting the outer commit", function()
		local data = freshData()
		local nestedResult: Types.TransactionResult? = nil
		local nestedMutationCalls = 0
		local outerResult = Transactions.Run(data, request(0, "outer"), function(draft)
			draft.currency.gold += 25
			nestedResult = Transactions.Run(data, request(0, "nested"), function(_nestedDraft)
				nestedMutationCalls += 1
				return { ok = true }
			end, active)
			return { ok = true }
		end, active)

		expect(outerResult.ok).toBe(true)
		expect(outerResult.revision).toBe(1)
		expect(assert(nestedResult, "[Transactions.spec] Expected nestedResult").ok).toBe(false)
		expect(assert(nestedResult, "[Transactions.spec] Expected nestedResult").code).toBe(
			"TransactionBusy"
		)
		expect(assert(nestedResult, "[Transactions.spec] Expected nestedResult").revision).toBe(0)
		expect(nestedMutationCalls).toBe(0)
		expect(data.currency.gold).toBe(125)
	end)
end)

describe("Transactions.Run receipts and commit isolation", function()
	it("rejects malformed matching saved receipts without throwing or replaying them", function()
		local cyclic: any = { ok = true, revision = 1 }
		cyclic.self = cyclic
		local malformed: { any } = {
			{},
			{ ok = "yes", revision = 1 },
			{ ok = true, revision = 0 },
			{ ok = true, revision = 2 },
			{ ok = true, revision = 0 / 0 },
			{ ok = true, revision = 1, values = { amount = math.huge } },
			setmetatable({ ok = true, revision = 1 }, {}),
			cyclic,
		}
		for _, savedResult in malformed do
			local data = freshData()
			local original = request(0, "malformed")
			data.transactions = {
				revision = 1,
				receipts = {
					[original.id] = {
						expectedRevision = 0,
						operation = original.operation,
						signature = original.signature,
						result = savedResult,
					},
				},
			}
			local calls = 0
			local result = Transactions.Run(data, original, function(_draft)
				calls += 1
				return { ok = true }
			end, active)
			expect(result).toEqual({ ok = false, code = "InvalidTransaction", revision = 1 })
			expect(calls).toBe(0)
			expect(data.currency.gold).toBe(100)
		end
	end)

	it("replays a persisted receipt after JSON restore without granting twice", function()
		local data = freshData()
		local transactionRequest = request(0, "persisted-award", "Award", "gold=25")
		local mutationCalls = 0
		local original = Transactions.Run(data, transactionRequest, function(draft)
			mutationCalls += 1
			draft.currency.gold += 25
			return { ok = true, values = { awarded = 25 } }
		end, active)
		expect(original.revision).toBe(1)
		expect(data.currency.gold).toBe(125)

		local restored = snapshot(data) :: Types.PlayerDoc
		local replay = Transactions.Run(restored, transactionRequest, function(draft)
			mutationCalls += 1
			draft.currency.gold += 25
			return { ok = true, values = { awarded = 25 } }
		end, active)

		expect(replay).toEqual({
			ok = true,
			values = { awarded = 25 },
			revision = 1,
			replayed = true,
		})
		expect(mutationCalls).toBe(1)
		expect(restored.currency.gold).toBe(125)
		expect(
			assert(restored.transactions, "[Transactions.spec] Expected restored.transactions").revision
		).toBe(1)
	end)

	it("replays the original receipt and rejects the same id with a mismatched payload", function()
		local data = freshData()
		local mutationCalls = 0
		local originalRequest = request(0, "award", "Award", "item=fire")
		local original = Transactions.Run(data, originalRequest, function(draft)
			mutationCalls += 1
			draft.currency.gold += 25
			return { ok = true, values = { awarded = 25 } }
		end, active)
		expect(original.revision).toBe(1)

		local later = Transactions.Run(data, request(1, "later"), function(draft)
			draft.currency.gold += 1
			return { ok = true }
		end, active)
		expect(later.revision).toBe(2)

		local replay = Transactions.Run(data, originalRequest, function(_draft)
			mutationCalls += 1
			return { ok = false, code = "MustNotRun" }
		end, active)
		expect(replay).toEqual({
			ok = true,
			values = { awarded = 25 },
			revision = 1,
			replayed = true,
		})
		expect(mutationCalls).toBe(1)
		expect(data.currency.gold).toBe(126)

		for _, conflictRequest in
			{
				request(0, "award", "Award", "item=water"),
				request(0, "award", "DifferentOperation", "item=fire"),
			}
		do
			local conflict = Transactions.Run(data, conflictRequest, function(_draft)
				mutationCalls += 1
				return { ok = true }
			end, active)
			expect(conflict.ok).toBe(false)
			expect(conflict.code).toBe("RequestConflict")
			expect(conflict.revision).toBe(2)
		end
		expect(mutationCalls).toBe(1)
	end)

	it("keeps rejection receipt replay stable and never reruns the callback", function()
		local data = freshData()
		local transactionRequest = request(0, "denied", "Purchase", "price=500")
		local callbackCalls = 0
		local first = Transactions.Run(data, transactionRequest, function(draft)
			callbackCalls += 1
			draft.currency.gold = 0
			return { ok = false, code = "InsufficientGold", values = { available = 100 } }
		end, active)
		local returnedValues = assert(first.values, "[Transactions.spec] Expected first.values")
		returnedValues.available = 999
		first.code = "Tampered"

		local replay = Transactions.Run(data, transactionRequest, function(_draft)
			callbackCalls += 1
			return { ok = true }
		end, active)
		expect(replay).toEqual({
			ok = false,
			code = "InsufficientGold",
			values = { available = 100 },
			revision = 1,
			replayed = true,
		})
		expect(callbackCalls).toBe(1)
		expect(data.currency.gold).toBe(100)
	end)

	it("evicts receipts at the bound and rejects stale or revision-tampered reuse", function()
		local data = freshData()
		local firstRequest = request(0, "request-0", "Increment", "index=0")
		for revision = 0, Configuration.maxRequestReceipts do
			local transactionRequest = if revision == 0
				then firstRequest
				else request(revision, `request-{revision}`, "Increment", `index={revision}`)
			local result = Transactions.Run(data, transactionRequest, function(draft)
				draft.currency.gold += 1
				return { ok = true, values = { index = revision } }
			end, active)
			expect(result.ok).toBe(true)
			expect(result.revision).toBe(revision + 1)
		end

		local state = assert(data.transactions, "[Transactions.spec] Expected data.transactions")
		expect(state.revision).toBe(Configuration.maxRequestReceipts + 1)
		expect(receiptCount(data)).toBe(Configuration.maxRequestReceipts)
		expect(state.receipts[firstRequest.id]).toBeNil()

		local stale = Transactions.Run(data, firstRequest, function(_draft)
			return { ok = true }
		end, active)
		expect(stale.ok).toBe(false)
		expect(stale.code).toBe("StaleRevision")
		expect(stale.revision).toBe(Configuration.maxRequestReceipts + 1)

		local tampered = Transactions.Run(data, {
			id = firstRequest.id,
			expectedRevision = state.revision,
			operation = firstRequest.operation,
			signature = "tampered",
		}, function(_draft)
			return { ok = true }
		end, active)
		expect(tampered.ok).toBe(false)
		expect(tampered.code).toBe("InvalidTransaction")
		expect(assert(data.transactions, "[Transactions.spec] Expected data.transactions").revision).toBe(
			Configuration.maxRequestReceipts + 1
		)
	end)

	it("detaches callback drafts, callback values, and returned results from live state", function()
		local data = freshData()
		local transactionRequest = request(0, "detached", "Award", "amount=25")
		local capturedDraft: Types.PlayerDoc? = nil
		local callbackValues: Types.TransactionValues = { amount = 25 }
		local result = Transactions.Run(data, transactionRequest, function(draft)
			capturedDraft = draft
			draft.currency.gold += 25
			return { ok = true, values = callbackValues }
		end, active)
		expect(result.ok).toBe(true)
		expect(data.currency.gold).toBe(125)

		assert(capturedDraft, "[Transactions.spec] Expected capturedDraft").currency.gold = 500
		callbackValues.amount = 700
		local returnedValues = assert(result.values, "[Transactions.spec] Expected result.values")
		returnedValues.amount = 900
		result.ok = false
		result.code = "Tampered"
		expect(data.currency.gold).toBe(125)

		local replay = Transactions.Run(data, transactionRequest, function(_draft)
			error("receipt replay must not invoke the callback")
		end, active)
		expect(replay.ok).toBe(true)
		expect(replay.code).toBeNil()
		expect(assert(replay.values, "[Transactions.spec] Expected replay.values").amount).toBe(25)
		expect(replay.revision).toBe(1)
		expect(replay.replayed).toBe(true)
	end)

	it("preserves existing section and entry references while installing a commit", function()
		local data = freshData()
		local currency = data.currency
		local materials = data.materials
		local equipment = data.equipment
		local sword = assert(
			equipment.starter_wooden_sword,
			"[Transactions.spec] Expected equipment.starter_wooden_sword"
		)
		local shield = assert(
			equipment.starter_wooden_shield,
			"[Transactions.spec] Expected equipment.starter_wooden_shield"
		)
		local base = data.base
		local stands = base.stands

		local result = Transactions.Run(data, request(0, "references"), function(draft)
			draft.currency.gold += 50
			draft.materials.fire = { total = 5 }
			draft.equipment.starter_wooden_sword.finishId = "vulcan"
			draft.base.stands["0"] = {}
			return { ok = true }
		end, active)

		expect(result.ok).toBe(true)
		expect(data.currency).toBe(currency)
		expect(data.materials).toBe(materials)
		expect(data.equipment).toBe(equipment)
		expect(data.equipment.starter_wooden_sword).toBe(sword)
		expect(data.equipment.starter_wooden_shield).toBe(shield)
		expect(data.base).toBe(base)
		expect(data.base.stands).toBe(stands)
		expect(data.currency.gold).toBe(150)
		expect(data.materials.fire.total).toBe(5)
		expect(data.equipment.starter_wooden_sword.finishId).toBe("vulcan")
	end)
end)
