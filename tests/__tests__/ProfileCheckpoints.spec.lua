--!strict
-- ServerStorage/Tests/__tests__/ProfileCheckpoints.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ProfileCheckpoints =
	require(ServerScriptService.Services.ProductionService.ProfileCheckpoints)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local function fixture()
	local first = (table.freeze({ UserId = 1 }) :: unknown) :: Player
	local second = (table.freeze({ UserId = 2 }) :: unknown) :: Player
	local state = {
		loaded = { [first] = true },
		calls = {} :: { Player },
		errors = {} :: { string },
		result = { ok = true, revision = 1 } :: Types.TransactionResult,
	}
	local scheduler = ProfileCheckpoints.new(
		{
			GetLoadedData = function(player): Types.PlayerDoc?
				return if state.loaded[player] then ({} :: unknown) :: Types.PlayerDoc else nil
			end,
			Checkpoint = function(player)
				table.insert(state.calls, player)
				return state.result
			end,
		},
		function()
			return { first, second }
		end,
		30,
		function(_, code)
			table.insert(state.errors, code)
		end
	)
	return scheduler, state, first, second
end

describe("ProfileCheckpoints cadence", function()
	it("checkpoints only already loaded profiles at the configured interval", function()
		local scheduler, state, first, second = fixture()
		scheduler.Step(29.5)
		expect(#state.calls).toBe(0)
		scheduler.Step(0.5)
		expect(state.calls).toEqual({ first })
		state.loaded[second] = true
		scheduler.Step(30)
		expect(state.calls).toEqual({ first, first, second })
	end)

	it(
		"coalesces a stalled heartbeat into one current checkpoint and retains fractional cadence",
		function()
			local scheduler, state = fixture()
			scheduler.Step(305)
			expect(#state.calls).toBe(1)
			scheduler.Step(24)
			expect(#state.calls).toBe(1)
			scheduler.Step(1)
			expect(#state.calls).toBe(2)
		end
	)

	it(
		"skips unloaded profiles and reports real failures without treating departure as an error",
		function()
			local scheduler, state, first = fixture()
			state.loaded[first] = nil
			scheduler.Step(30)
			expect(#state.calls).toBe(0)
			state.loaded[first] = true
			state.result = { ok = false, code = "DataUnavailable", revision = 0 }
			scheduler.Step(30)
			expect(state.errors).toEqual({})
			state.result = { ok = false, code = "InvalidProductionClock", revision = 0 }
			scheduler.Step(30)
			expect(state.errors).toEqual({ "InvalidProductionClock" })
		end
	)

	it("ignores invalid deltas instead of poisoning subsequent checkpoints", function()
		local scheduler, state = fixture()
		for _, delta in { -1, 0, math.huge, 0 / 0 } do
			scheduler.Step(delta)
		end
		scheduler.Step(30)
		expect(#state.calls).toBe(1)
	end)
end)
