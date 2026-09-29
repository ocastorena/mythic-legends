--!strict
-- ServerStorage/Tests/__tests__/CraftingDueJobs.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local DueJobs = require(ServerScriptService.Services.CraftingService.DueJobs)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function profile(completesAt: number): Types.PlayerDoc
	local data: Types.PlayerDoc = HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate))
	-- This is only a scheduling hint; the transaction preparation owns full receipt validation.
	local raw = data :: any
	raw.craftingJobs.job =
		{ status = "Active", receipt = { version = 1, completesAt = completesAt } }
	return data
end

local function fixture(interval: number?)
	local first = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local second = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
	local unavailable = (table.freeze({ UserId = 1003 }) :: unknown) :: Player
	local data: { [Player]: Types.PlayerDoc } = { [first] = profile(60), [second] = profile(61) }
	local state = {
		now = 60,
		clockCalls = 0,
		playerCalls = 0,
		reads = 0,
		ok = true,
		code = "Failed" :: string?,
		players = { first, second, unavailable },
		updates = {} :: { { player: Player, operation: string, outcome: Types.TransactionOutcome } },
		failures = {} :: { { player: Player, code: string? } },
	}
	local source: DueJobs.DataSource = {
		GetLoadedData = function(player: Player): Types.PlayerDoc?
			state.reads += 1
			return data[player]
		end,
		Update = function(player, operation, mutate)
			local outcome = mutate(data[player], state.now)
			table.insert(
				state.updates,
				{ player = player, operation = operation, outcome = outcome }
			)
			return { ok = state.ok, code = if state.ok then nil else state.code, revision = 1 }
		end,
	}
	local function players(): { Player }
		state.playerCalls += 1
		return state.players
	end
	local scheduler = DueJobs.new(source, players, interval or 1, function(): number
		state.clockCalls += 1
		return state.now
	end, function(player, code)
		table.insert(state.failures, { player = player, code = code })
	end)
	return {
		scheduler = scheduler,
		source = source,
		players = players,
		data = data,
		state = state,
		first = first,
		second = second,
	}
end

describe("Crafting DueJobs", function()
	it(
		"checks loaded profiles only once the interval elapses and requests canonical due work",
		function()
			local f = fixture()
			f.scheduler.Step(0.25)
			f.scheduler.Step(0.5)
			expect(f.state.clockCalls).toBe(0)
			expect(f.state.reads).toBe(0)
			f.scheduler.Step(0.25)
			expect(f.state.clockCalls).toBe(1)
			expect(f.state.reads).toBe(3)
			expect(f.state.updates).toEqual({
				{ player = f.first, operation = "Crafting.Resolve", outcome = { ok = true } },
			})
			f.state.now = 61
			f.scheduler.Step(1)
			expect(#f.state.updates).toBe(3)
			expect(f.state.updates[3].player).toBe(f.second)
		end
	)

	it("coalesces a delayed tick instead of replaying missed intervals serially", function()
		local f = fixture()
		f.state.now = 10_000
		f.scheduler.Step(100.5)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.playerCalls).toBe(1)
		expect(#f.state.updates).toBe(2)
		f.scheduler.Step(0.49)
		expect(#f.state.updates).toBe(2)
		f.scheduler.Step(0.01)
		expect(f.state.clockCalls).toBe(2)
		expect(#f.state.updates).toBe(4)
	end)

	it("ignores early, resolved, opaque legacy and malformed scheduling hints", function()
		local malformed: { any } = {
			false,
			{},
			{ status = "Active" },
			{ status = "Active", receipt = false },
			{ status = "Active", receipt = { version = 2, completesAt = 0 } },
			{ status = "Completed", receipt = { version = 1, completesAt = 0 } },
			{ status = "Cancelled", receipt = { version = 1, completesAt = 0 } },
			{ status = "Active", receipt = { version = 1, completesAt = 61 } },
			{ status = "Active", receipt = { version = 1, completesAt = "0" } },
			{ status = "Active", receipt = { version = 1, completesAt = 0 / 0 } },
		}
		for _, value in malformed do
			local f = fixture()
			f.state.players = { f.first }
			local raw = f.data[f.first] :: any
			raw.craftingJobs = { job = value }
			f.scheduler.Step(1)
			expect(#f.state.updates).toBe(0)
		end
		for _, value in { false, "jobs" } do
			local f = fixture()
			local raw = f.data[f.first] :: any
			raw.craftingJobs = value
			f.scheduler.Step(1)
			expect(#f.state.updates).toBe(0)
		end
	end)

	it(
		"deduplicates unchanged failures and resets reporting after success or a profile is unavailable",
		function()
			local f = fixture()
			f.state.players = { f.first }
			f.state.ok = false
			f.scheduler.Step(1)
			f.scheduler.Step(1)
			expect(#f.state.updates).toBe(2)
			expect(#f.state.failures).toBe(1)
			f.state.code = "ChangedFailure"
			f.scheduler.Step(1)
			expect(#f.state.failures).toBe(2)
			f.state.ok = true
			f.scheduler.Step(1)
			f.state.ok = false
			f.scheduler.Step(1)
			expect(#f.state.failures).toBe(3)
			local saved = f.data[f.first]
			f.data[f.first] = nil
			f.scheduler.Step(1)
			f.data[f.first] = saved
			f.scheduler.Step(1)
			expect(#f.state.failures).toBe(4)
			expect(f.state.failures[4]).toEqual({ player = f.first, code = "ChangedFailure" })
		end
	)

	it("deduplicates missing failure codes and resets when no active job is due", function()
		local f = fixture()
		f.state.players = { f.first }
		f.state.ok = false
		f.state.code = nil
		f.scheduler.Step(1)
		f.scheduler.Step(1)
		expect(#f.state.failures).toBe(1)
		f.state.now = 59
		f.scheduler.Step(1)
		f.state.now = 60
		f.scheduler.Step(1)
		expect(#f.state.failures).toBe(2)
	end)

	it("rejects invalid intervals and ignores invalid deltas or clock samples", function()
		local f = fixture()
		for _, interval in { 0, -1, math.huge, 0 / 0 } do
			expect(function()
				DueJobs.new(f.source, f.players, interval)
			end).toThrow()
		end
		for _, delta in { -1, math.huge, 0 / 0, "1" } do
			f.scheduler.Step(delta :: any)
		end
		expect(f.state.clockCalls).toBe(0)
		for _, now in { -1, math.huge, 0 / 0, 2 ^ 53 } do
			f.state.now = now
			f.scheduler.Step(1)
		end
		expect(f.state.playerCalls).toBe(0)
		expect(#f.state.updates).toBe(0)
		f.state.now = 60
		f.scheduler.Step(1)
		expect(#f.state.updates).toBe(1)
	end)
end)
