--!strict
-- ServerStorage/Tests/__tests__/ProfileSettlements.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ProfileSettlements = require(ServerScriptService.Services.DataService.ProfileSettlements)
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

local function fixture(clockOverride: (() -> number)?)
	local state = { active = true, current = true, now = 20.5, clockCalls = 0, ids = 0 }
	local profile: ProfileSettlements.Profile = {
		Data = copy(PlayerDataTemplate),
		IsActive = function(): boolean
			return state.active
		end,
	}
	local api = ProfileSettlements.new(function()
		state.clockCalls += 1
		return if clockOverride then clockOverride() else state.now
	end, function()
		state.ids += 1
		return `boundary_{state.ids}`
	end)
	return {
		api = api,
		profile = profile,
		state = state,
		isCurrent = function(): boolean
			return state.current
		end,
	}
end

describe("ProfileSettlements", function()
	it("runs all hooks in registration order on one detached draft and timestamp", function()
		local f = fixture()
		local data = f.profile.Data
		local observed: { string } = {}
		local sharedDraft: Types.PlayerDoc? = nil
		f.api.Register("Production", function(draft, timestamp, boundary)
			table.insert(observed, "Production")
			expect(draft).never.toBe(data)
			expect(timestamp).toBe(20.5)
			expect(boundary).toBe("Ready")
			sharedDraft = draft
			draft.currency.gold = 101
			return { ok = true }
		end)
		f.api.Register("Crafting", function(draft, timestamp, boundary)
			table.insert(observed, "Crafting")
			expect(draft).toBe(sharedDraft)
			expect(draft.currency.gold).toBe(101)
			expect(data.currency.gold).toBe(100)
			expect(timestamp).toBe(20.5)
			expect(boundary).toBe("Ready")
			draft.materials.fire_material = { total = 2 }
			return { ok = true }
		end)
		f.api.Seal()
		expect(f.api.Run(f.profile, "Ready", f.isCurrent)).toEqual({ ok = true, revision = 1 })
		expect(observed).toEqual({ "Production", "Crafting" })
		expect(data.currency.gold).toBe(101)
		expect(data.materials.fire_material.total).toBe(2)
		expect(f.state.clockCalls).toBe(1)
		local transactions = assert(data.transactions, "[ProfileSettlements.spec] Expected receipt")
		expect(transactions.revision).toBe(1)
		expect(transactions.receipts["0:boundary_1"].operation).toBe("Data.ProfileReady")
	end)

	it(
		"passes the distinct Ready, Checkpoint, and Release boundaries through the same contract",
		function()
			local f = fixture()
			local calls: { { boundary: ServerTypes.ProfileBoundary, timestamp: number } } = {}
			f.api.Register("Recorder", function(draft, timestamp, boundary)
				table.insert(calls, { boundary = boundary, timestamp = timestamp })
				draft.currency.gold += 1
				return { ok = true }
			end)
			for index, boundary in { "Ready", "Checkpoint", "Release" } do
				f.state.now = index
				expect(f.api.Run(f.profile, boundary :: ServerTypes.ProfileBoundary).ok).toBe(true)
			end
			expect(calls).toEqual({
				{ boundary = "Ready", timestamp = 1 },
				{ boundary = "Checkpoint", timestamp = 2 },
				{ boundary = "Release", timestamp = 3 },
			})
			expect(f.profile.Data.currency.gold).toBe(103)
			expect(f.state.clockCalls).toBe(3)
			expect(
				assert(f.profile.Data.transactions, "[ProfileSettlements.spec] Expected receipts").revision
			).toBe(3)
		end
	)

	it(
		"validates registration without reserving rejected owners and closes registration once sealed",
		function()
			local f = fixture()
			local settle: ServerTypes.ProfileSettlement = function()
				return { ok = true }
			end
			for _, owner in { "", string.rep("x", 65), 1, false } do
				expect(function()
					f.api.Register(owner :: any, settle)
				end).toThrow()
			end
			expect(function()
				f.api.Register("valid", false :: any)
			end).toThrow()
			f.api.Register("valid", settle)
			expect(function()
				f.api.Register("valid", settle)
			end).toThrow()
			f.api.Register(string.rep("x", 64), settle)
			f.api.Seal()
			f.api.Seal()
			expect(function()
				f.api.Register("late", settle)
			end).toThrow()
			expect(f.api.Run(f.profile, "Ready").ok).toBe(true)
		end
	)

	it(
		"automatically closes registration before the first hook can change its own iteration",
		function()
			local f = fixture()
			local denied = false
			f.api.Register("first", function()
				local registered = pcall(function()
					f.api.Register("during-run", function()
						return { ok = true }
					end)
				end)
				denied = not registered
				return { ok = true }
			end)
			expect(f.api.Run(f.profile, "Ready").ok).toBe(true)
			expect(denied).toBe(true)
			expect(function()
				f.api.Register("after-run", function()
					return { ok = true }
				end)
			end).toThrow()
		end
	)

	it(
		"discards all earlier edits when a later hook rejects and never invokes subsequent hooks",
		function()
			local f = fixture()
			local before = gameplay(f.profile.Data)
			local calls: { string } = {}
			f.api.Register("first", function(draft)
				table.insert(calls, "first")
				draft.currency.gold = 999
				return { ok = true }
			end)
			f.api.Register("second", function(draft)
				table.insert(calls, "second")
				draft.materials.fire_material = { total = 10 }
				return { ok = false, code = "UnresolvedProduction" }
			end)
			f.api.Register("third", function()
				table.insert(calls, "third")
				return { ok = true }
			end)
			expect(f.api.Run(f.profile, "Checkpoint")).toEqual({
				ok = false,
				code = "UnresolvedProduction",
				revision = 1,
			})
			expect(gameplay(f.profile.Data)).toEqual(before)
			expect(calls).toEqual({ "first", "second" })
			expect(f.state.clockCalls).toBe(1)
		end
	)

	local failingHooks: { { code: string, hook: ServerTypes.ProfileSettlement } } = {
		{
			code = "MutationFailed",
			hook = function()
				error("intentional hook failure")
			end,
		},
		{
			code = "MutationYielded",
			hook = function()
				coroutine.yield()
				return { ok = true }
			end,
		},
		{
			code = "MutationFailed",
			hook = function()
				return ({} :: any) :: Types.TransactionOutcome
			end,
		},
	}
	for index, case in failingHooks do
		it(`rolls back all hooks and receipts on failure case {index}`, function()
			local f = fixture()
			local before = copy(f.profile.Data)
			f.api.Register("first", function(draft)
				draft.currency.gold = 999
				return { ok = true }
			end)
			f.api.Register("broken", case.hook)
			expect(f.api.Run(f.profile, "Ready")).toEqual({
				ok = false,
				code = case.code,
				revision = 0,
			})
			expect(f.profile.Data).toEqual(before)
		end)
	end

	it("rejects inactive or replaced profiles before sampling time", function()
		for _, inactive in { true, false } do
			local f = fixture()
			local before = copy(f.profile.Data)
			f.state.active = not inactive
			f.state.current = inactive
			f.api.Register("must-not-run", function()
				error("inactive hook must not run")
			end)
			expect(f.api.Run(f.profile, "Ready", f.isCurrent)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profile.Data).toEqual(before)
			expect(f.state.clockCalls).toBe(0)
		end
	end)

	it(
		"rolls back all hooks if the session ends or the profile is replaced during settlement",
		function()
			for _, endSession in { true, false } do
				local f = fixture()
				local before = copy(f.profile.Data)
				f.api.Register("first", function(draft)
					draft.currency.gold = 999
					return { ok = true }
				end)
				f.api.Register("session-change", function(draft)
					draft.materials.fire_material = { total = 10 }
					if endSession then
						f.state.active = false
					else
						f.state.current = false
					end
					return { ok = true }
				end)
				expect(f.api.Run(f.profile, "Checkpoint", f.isCurrent)).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
				expect(f.profile.Data).toEqual(before)
			end
		end
	)

	it(
		"rejects invalid boundaries and timestamps without running hooks or changing gameplay",
		function()
			local invalidBoundary = fixture()
			local before = copy(invalidBoundary.profile.Data)
			expect(invalidBoundary.api.Run(invalidBoundary.profile, "Reset" :: any)).toEqual({
				ok = false,
				code = "InvalidBoundary",
				revision = 0,
			})
			expect(invalidBoundary.profile.Data).toEqual(before)
			expect(invalidBoundary.state.clockCalls).toBe(0)
			for _, timestamp in { -1, math.huge, 0 / 0, 2 ^ 53 } do
				local f = fixture()
				f.state.now = timestamp
				local original = gameplay(f.profile.Data)
				local calls = 0
				f.api.Register("must-not-run", function()
					calls += 1
					return { ok = true }
				end)
				expect(f.api.Run(f.profile, "Ready").code).toBe("InvalidTimestamp")
				expect(gameplay(f.profile.Data)).toEqual(original)
				expect(calls).toBe(0)
			end
		end
	)

	it(
		"contains a throwing clock inside the transaction and leaves the profile and receipts unchanged",
		function()
			local f = fixture(function(): number
				error("intentional clock failure")
			end)
			local before = copy(f.profile.Data)
			expect(f.api.Run(f.profile, "Ready")).toEqual({
				ok = false,
				code = "MutationFailed",
				revision = 0,
			})
			expect(f.profile.Data).toEqual(before)
		end
	)

	it("finalizes exactly once by profile identity across competing shutdown callers", function()
		local f = fixture()
		local calls = 0
		f.api.Register("release", function(draft, timestamp, boundary)
			expect(boundary).toBe("Release")
			expect(timestamp).toBe(20.5)
			calls += 1
			draft.currency.gold += 1
			return { ok = true }
		end)
		local result = f.api.Finalize(f.profile, f.isCurrent)
		expect(result).toEqual({ ok = true, revision = 1 })
		local after = copy(f.profile.Data)
		f.state.active = false
		f.state.current = false
		f.state.now = 500
		expect(f.api.Finalize(f.profile, f.isCurrent)).toEqual(result)
		expect(f.profile.Data).toEqual(after)
		expect(calls).toBe(1)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.ids).toBe(1)
	end)

	it(
		"does not confuse a newly loaded profile for the same user with a finalized session",
		function()
			local f = fixture()
			local calls = 0
			f.api.Register("release", function(draft)
				calls += 1
				draft.currency.gold += 1
				return { ok = true }
			end)
			expect(f.api.Finalize(f.profile).ok).toBe(true)
			local replacement: ProfileSettlements.Profile = {
				Data = copy(f.profile.Data),
				IsActive = function(): boolean
					return true
				end,
			}
			expect(f.api.Finalize(replacement)).toEqual({ ok = true, revision = 2 })
			expect(calls).toBe(2)
			expect(f.profile.Data.currency.gold).toBe(101)
			expect(replacement.Data.currency.gold).toBe(102)
		end
	)

	it("caches a failed finalization without rerunning settlement at a later timestamp", function()
		local f = fixture()
		local calls = 0
		f.api.Register("reject", function(draft)
			calls += 1
			draft.currency.gold = 999
			return { ok = false, code = "UnresolvedProduction", values = { affected = "original" } }
		end)
		local result = f.api.Finalize(f.profile)
		local expected = copy(result)
		local after = copy(f.profile.Data)
		expect(result.code).toBe("UnresolvedProduction")
		-- A consumer may inspect/annotate its result; it must not rewrite the stored resolution.
		local values = assert(result.values, "[ProfileSettlements.spec] Expected failure detail")
		values.affected = "changed"
		f.state.now = 500
		local replay = f.api.Finalize(f.profile)
		expect(replay).toEqual(expected)
		expect(replay).never.toBe(result)
		expect(f.profile.Data).toEqual(after)
		expect(calls).toBe(1)
		expect(f.state.clockCalls).toBe(1)
	end)

	it("leaves session closing to its owning service after committing Ready and Release", function()
		local f = fixture()
		local endCalls = 0
		local extended = f.profile :: any
		extended.EndSession = function()
			endCalls += 1
		end
		f.api.Register("ready", function(draft)
			draft.currency.gold = 321
			return { ok = true }
		end)
		expect(f.api.Run(f.profile, "Ready").ok).toBe(true)
		expect(f.profile.Data.currency.gold).toBe(321)
		expect(endCalls).toBe(0)
		expect(f.api.Finalize(f.profile).ok).toBe(true)
		expect(endCalls).toBe(0)
	end)
end)
