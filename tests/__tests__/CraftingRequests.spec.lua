--!strict
-- ServerStorage/Tests/__tests__/CraftingRequests.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Configuration = require(ReplicatedStorage.Shared.Configurations.CraftingRequests)
local CraftingRequests = require(ServerScriptService.Services.CraftingService.CraftingRequests)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local ROUTES = { "GetStation", "StartJob", "CancelJob" }

local function fixture()
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		available = true,
		remaining = Configuration.requestBurst,
		calls = {} :: { string },
		payload = nil :: unknown,
		result = { ok = true, revision = 7, values = { jobId = "job" } } :: Types.TransactionResult,
		view = {
			ok = true,
			revision = 6,
			view = {
				sampledAt = 12.5,
				stationInstanceId = "station",
				craftingStationId = "basic_crafting_station",
				busy = false,
				recipes = {},
			},
		} :: Types.CraftingStationViewResult,
	}
	local function record(caller: Player, input: unknown, route: string)
		expect(caller).toBe(player)
		table.insert(state.calls, route)
		state.payload = input
	end
	local api = CraftingRequests.new({
		isAvailable = function(caller)
			expect(caller).toBe(player)
			table.insert(state.calls, "available")
			return state.available
		end,
		allowRequest = function(caller)
			expect(caller).toBe(player)
			table.insert(state.calls, "allow")
			if state.remaining == 0 then
				return false
			end
			state.remaining -= 1
			return true
		end,
		getStation = function(caller, input)
			record(caller, input, "GetStation")
			return state.view
		end,
		startJob = function(caller, input)
			record(caller, input, "StartJob")
			return state.result
		end,
		cancelJob = function(caller, input)
			record(caller, input, "CancelJob")
			return state.result
		end,
	})
	local routes: { [string]: (Player, unknown) -> unknown } = {
		GetStation = api.GetStation,
		StartJob = api.StartJob,
		CancelJob = api.CancelJob,
	}
	return { player = player, state = state, api = api, routes = routes }
end

describe("CraftingRequests", function()
	it("rejects unavailable callers before rate admission or any protected work", function()
		local f = fixture()
		f.state.available = false
		for _, route in ROUTES do
			table.clear(f.state.calls)
			expect(f.routes[route](f.player, {})).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.state.calls).toEqual({ "available" })
		end
		expect(f.state.remaining).toBe(Configuration.requestBurst)
		expect(f.state.payload).toBeNil()
	end)

	it("shares one admission budget across reads, starts, and cancellations", function()
		local f = fixture()
		expect(Configuration.requestBurst).toBe(12)
		expect(Configuration.requestRefillPerSecond).toBe(4)
		expect(table.isfrozen(Configuration)).toBe(true)
		for index = 1, Configuration.requestBurst do
			local route = ROUTES[(index - 1) % #ROUTES + 1]
			table.clear(f.state.calls)
			f.routes[route](f.player, { requestId = "unchanged" })
			expect(f.state.calls).toEqual({ "available", "allow", route })
		end
		for _, route in ROUTES do
			table.clear(f.state.calls)
			expect(f.routes[route](f.player, {})).toEqual({
				ok = false,
				code = "RateLimited",
				revision = 0,
			})
			expect(f.state.calls).toEqual({ "available", "allow" })
		end
	end)

	it(
		"forwards raw payloads without dropping forbidden fields or fabricating snapshots",
		function()
			for _, route in ROUTES do
				local f = fixture()
				local inputs: { unknown } = {
					false,
					42,
					"invalid",
					{ stationInstanceId = "station", targetUserId = 2002, unexpected = {} },
					setmetatable({}, {}),
				}
				for _, input in inputs do
					table.clear(f.state.calls)
					f.routes[route](f.player, input)
					expect(f.state.payload).toBe(input)
					expect(f.state.calls).toEqual({ "available", "allow", route })
				end
				f.routes[route](f.player, nil)
				expect(f.state.payload).toBeNil()
			end
		end
	)

	it(
		"returns views and immutable committed receipts unchanged, without access prechecks",
		function()
			local f = fixture()
			f.state.view = FreezeUtil.DeepFreeze(f.state.view)
			expect(f.api.GetStation(f.player, { stationInstanceId = "station" })).toBe(f.state.view)
			for _, route in { "StartJob", "CancelJob" } do
				table.clear(f.state.calls)
				local receipt: Types.TransactionResult = {
					ok = true,
					revision = 3,
					replayed = true,
					values = { jobId = "old_job", status = "Completed", goldRefunded = 0 },
				}
				FreezeUtil.DeepFreeze(receipt)
				f.state.result = receipt
				local original =
					{ requestId = "0:original", expectedRevision = 0, jobId = "old_job" }
				expect(f.routes[route](f.player, original)).toBe(f.state.result)
				expect(f.state.payload).toBe(original)
				expect(f.state.calls).toEqual({ "available", "allow", route })
			end
		end
	)

	it("keeps domain failures small and does not request a replacement view", function()
		for _, code in
			{ "InvalidRequest", "DataUnavailable", "StationChanged", "OutOfRange", "StaleRevision" }
		do
			local f = fixture()
			f.state.result = { ok = false, code = code, revision = 9 }
			for _, route in { "StartJob", "CancelJob" } do
				table.clear(f.state.calls)
				expect(f.routes[route](f.player, {})).toBe(f.state.result)
				expect(f.state.calls).toEqual({ "available", "allow", route })
			end
		end
	end)
end)
