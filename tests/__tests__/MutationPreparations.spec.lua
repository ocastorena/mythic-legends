--!strict
-- ServerStorage/Tests/__tests__/MutationPreparations.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local MutationPreparations = require(ServerScriptService.Services.DataService.MutationPreparations)
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

local function request(): Types.TransactionRequest
	return {
		id = "0:preparation",
		expectedRevision = 0,
		operation = "Test.PreparedMutation",
		signature = "prepared-command",
	}
end

describe("MutationPreparations", function()
	it("validates owners and callbacks without reserving a rejected owner", function()
		local api = MutationPreparations.new()
		local prepare: ServerTypes.MutationPreparation = function()
			return { ok = true }
		end
		for _, owner in { "", string.rep("x", 65), 1, false, {} } do
			expect(function()
				api.Register(owner :: any, prepare)
			end).toThrow()
		end
		expect(function()
			api.Register(nil :: any, prepare)
		end).toThrow()
		for _, invalid in { false, 1, "callback", {} } do
			expect(function()
				api.Register("available", invalid :: any)
			end).toThrow()
		end
		expect(function()
			api.Register("available", nil :: any)
		end).toThrow()
		api.Register("available", prepare)
		api.Register(string.rep("x", 64), prepare)
		expect(function()
			api.Register("available", prepare)
		end).toThrow()
		expect(api.ApplyToDraft(copy(PlayerDataTemplate), 0)).toEqual({ ok = true })
	end)

	it(
		"seals registration explicitly and preserves repeated empty success without changing the draft",
		function()
			local api = MutationPreparations.new()
			local data = copy(PlayerDataTemplate)
			local before = copy(data)
			api.Seal()
			api.Seal()
			expect(function()
				api.Register("late", function()
					return { ok = true }
				end)
			end).toThrow()
			for _, timestamp in { 0, 20.5, 2 ^ 53 - 1 } do
				expect(api.ApplyToDraft(data, timestamp)).toEqual({ ok = true })
			end
			expect(data).toEqual(before)
		end
	)

	it("automatically seals before a hook can register another hook", function()
		local api = MutationPreparations.new()
		local denied = false
		api.Register("first", function()
			denied = not pcall(function()
				api.Register("during-run", function()
					return { ok = true }
				end)
			end)
			return { ok = true }
		end)
		expect(api.ApplyToDraft(copy(PlayerDataTemplate), 1).ok).toBe(true)
		expect(denied).toBe(true)
		expect(function()
			api.Register("after-run", function()
				return { ok = true }
			end)
		end).toThrow()
	end)

	it("runs hooks in order on the command's same detached draft and shared timestamp", function()
		local api = MutationPreparations.new()
		local data = copy(PlayerDataTemplate)
		local calls: { string } = {}
		local firstDraft: Types.PlayerDoc? = nil
		api.Register("first", function(draft, timestamp)
			table.insert(calls, "first")
			firstDraft = draft
			expect(draft).never.toBe(data)
			expect(timestamp).toBe(20.5)
			draft.currency.gold = 101
			return { ok = true, values = { privateHookValue = "not-the-command-result" } }
		end)
		api.Register("second", function(draft, timestamp)
			table.insert(calls, "second")
			expect(draft).toBe(firstDraft)
			expect(draft.currency.gold).toBe(101)
			expect(data.currency.gold).toBe(100)
			expect(timestamp).toBe(20.5)
			draft.materials.fire_material = { total = 2 }
			return { ok = true }
		end)
		local result = Transactions.Run(data, request(), function(draft)
			local prepared = api.ApplyToDraft(draft, 20.5)
			if not prepared.ok then
				return prepared
			end
			table.insert(calls, "command")
			expect(prepared).toEqual({ ok = true })
			expect(draft).toBe(firstDraft)
			draft.currency.gold += 10
			return { ok = true, values = { command = "committed" } }
		end, function()
			return true
		end)
		expect(calls).toEqual({ "first", "second", "command" })
		expect(result).toEqual({ ok = true, revision = 1, values = { command = "committed" } })
		expect(data.currency.gold).toBe(111)
		expect(data.materials.fire_material.total).toBe(2)
		local transactions =
			assert(data.transactions, "[MutationPreparations.spec] Expected receipt")
		expect(transactions.receipts["0:preparation"].operation).toBe("Test.PreparedMutation")
	end)

	it("returns the original failed outcome and stops before later hooks", function()
		local api = MutationPreparations.new()
		local calls: { string } = {}
		local outcome: Types.TransactionOutcome = {
			ok = false,
			code = "UnresolvedCrafting",
			values = { jobId = "blocked" },
		}
		api.Register("first", function()
			table.insert(calls, "first")
			return { ok = true }
		end)
		api.Register("blocked", function()
			table.insert(calls, "blocked")
			return outcome
		end)
		api.Register("never", function()
			table.insert(calls, "never")
			return { ok = true }
		end)
		expect(api.ApplyToDraft(copy(PlayerDataTemplate), 5)).toBe(outcome)
		expect(calls).toEqual({ "first", "blocked" })
	end)

	it(
		"rejects invalid timestamps before hooks run and closes registration even on rejection",
		function()
			local function rejected(timestamp: any)
				local api = MutationPreparations.new()
				local data = copy(PlayerDataTemplate)
				local before = copy(data)
				local calls = 0
				api.Register("must-not-run", function()
					calls += 1
					return { ok = true }
				end)
				expect(api.ApplyToDraft(data, timestamp)).toEqual({
					ok = false,
					code = "InvalidTimestamp",
				})
				expect(calls).toBe(0)
				expect(data).toEqual(before)
				expect(function()
					api.Register("late", function()
						return { ok = true }
					end)
				end).toThrow()
			end
			for _, timestamp in { -1, math.huge, -math.huge, 0 / 0, 2 ^ 53, "1", false, {} } do
				rejected(timestamp)
			end
			rejected(nil)
		end
	)

	it("rejects outcomes without a table and boolean ok flag", function()
		for _, outcome in { false, 1, "outcome", {}, { ok = 1 }, { ok = "true" } } do
			local api = MutationPreparations.new()
			api.Register("invalid", function()
				return outcome :: any
			end)
			expect(function()
				api.ApplyToDraft(copy(PlayerDataTemplate), 1)
			end).toThrow()
		end
		local missing = MutationPreparations.new()
		missing.Register("missing", function()
			return nil :: any
		end)
		expect(function()
			missing.ApplyToDraft(copy(PlayerDataTemplate), 1)
		end).toThrow()
	end)

	local failures: { { label: string, code: string, revision: number, hook: ServerTypes.MutationPreparation } } =
		{
			{
				label = "domain rejection",
				code = "UnresolvedCrafting",
				revision = 1,
				hook = function()
					return { ok = false, code = "UnresolvedCrafting" }
				end,
			},
			{
				label = "throw",
				code = "MutationFailed",
				revision = 0,
				hook = function()
					error("intentional preparation failure")
				end,
			},
			{
				label = "yield",
				code = "MutationYielded",
				revision = 0,
				hook = function()
					coroutine.yield()
					return { ok = true }
				end,
			},
			{
				label = "invalid outcome",
				code = "MutationFailed",
				revision = 0,
				hook = function()
					return ({} :: any) :: Types.TransactionOutcome
				end,
			},
		}
	for _, failure in failures do
		it(`rolls back all staged preparation edits on {failure.label}`, function()
			local api = MutationPreparations.new()
			local data = copy(PlayerDataTemplate)
			local before = copy(data)
			local calls: { string } = {}
			api.Register("first", function(draft)
				table.insert(calls, "first")
				draft.currency.gold = 999
				return { ok = true }
			end)
			api.Register("broken", function(draft, timestamp)
				table.insert(calls, "broken")
				draft.materials.fire_material = { total = 5 }
				return failure.hook(draft, timestamp)
			end)
			api.Register("never", function()
				table.insert(calls, "never")
				return { ok = true }
			end)
			local result = Transactions.Run(data, request(), function(draft)
				local prepared = api.ApplyToDraft(draft, 20.5)
				if not prepared.ok then
					return prepared
				end
				table.insert(calls, "command")
				draft.currency.gold = 1_000
				return { ok = true }
			end, function()
				return true
			end)
			expect(result).toEqual({ ok = false, code = failure.code, revision = failure.revision })
			expect(calls).toEqual({ "first", "broken" })
			if failure.revision == 0 then
				expect(data).toEqual(before)
			else
				expect(gameplay(data)).toEqual(gameplay(before))
				local after = copy(data)
				local replay = Transactions.Run(data, request(), function()
					error("a recorded rejection must not rerun preparation")
				end, function()
					return true
				end)
				expect(replay.replayed).toBe(true)
				expect(replay.code).toBe(failure.code)
				expect(data).toEqual(after)
			end
		end)
	end
end)
