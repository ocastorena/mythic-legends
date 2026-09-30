--!strict
-- ServerStorage/Tests/__tests__/BaseRequests.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Configuration = require(ReplicatedStorage.Shared.Configurations.BaseRequests)
local BaseRequests = require(ServerScriptService.Services.BaseService.BaseRequests)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local MUTATIONS = {
	"BuildShrine",
	"ExpandBase",
	"AssignShrineWorker",
	"RemoveShrineWorker",
	"UpgradeShrine",
	"DismantleShrine",
}
local ROUTES = {
	"GetBase",
	"GetShrine",
	"BuildShrine",
	"ExpandBase",
	"AssignShrineWorker",
	"RemoveShrineWorker",
	"UpgradeShrine",
	"DismantleShrine",
}

local function fixture()
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		available = true,
		remaining = Configuration.requestBurst,
		calls = {} :: { string },
		payload = nil :: unknown,
		result = { ok = true, revision = 7, values = { goldSpent = 100 } } :: Types.TransactionResult,
		view = { ok = false, code = "BaseUnavailable", revision = 6 } :: Types.BaseViewResult,
		shrineView = { ok = false, code = "ShrineUnavailable", revision = 6 } :: Types.ShrineViewResult,
	}
	local function record(caller: Player, route: string)
		expect(caller).toBe(player)
		table.insert(state.calls, route)
	end
	local api = BaseRequests.new({
		getShrine = function(caller, input)
			record(caller, "GetShrine")
			state.payload = input
			return state.shrineView
		end,
		assignShrineWorker = function(caller, input)
			record(caller, "AssignShrineWorker")
			state.payload = input
			return state.result
		end,
		removeShrineWorker = function(caller, input)
			record(caller, "RemoveShrineWorker")
			state.payload = input
			return state.result
		end,
		upgradeShrine = function(caller, input)
			record(caller, "UpgradeShrine")
			state.payload = input
			return state.result
		end,
		dismantleShrine = function(caller, input)
			record(caller, "DismantleShrine")
			state.payload = input
			return state.result
		end,
		isAvailable = function(caller)
			record(caller, "available")
			return state.available
		end,
		allowRequest = function(caller)
			record(caller, "allow")
			if state.remaining == 0 then
				return false
			end
			state.remaining -= 1
			return true
		end,
		getBase = function(caller)
			record(caller, "GetBase")
			return state.view
		end,
		buildShrine = function(caller, input)
			record(caller, "BuildShrine")
			state.payload = input
			return state.result
		end,
		expandBase = function(caller, input)
			record(caller, "ExpandBase")
			state.payload = input
			return state.result
		end,
	})
	local routes: { [string]: (Player, unknown) -> unknown } = {
		GetBase = function(caller: Player, _input: unknown): Types.BaseViewResult
			return api.GetBase(caller)
		end,
		BuildShrine = api.BuildShrine,
		ExpandBase = api.ExpandBase,
		GetShrine = api.GetShrine,
		AssignShrineWorker = api.AssignShrineWorker,
		RemoveShrineWorker = api.RemoveShrineWorker,
		UpgradeShrine = api.UpgradeShrine,
		DismantleShrine = api.DismantleShrine,
	}
	return { player = player, state = state, api = api, routes = routes }
end

describe("BaseRequests", function()
	it("rejects unavailable callers before admission or domain work", function()
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

	it("shares its configured budget across all canonical Base and Shrine routes", function()
		local f = fixture()
		expect(Configuration.requestBurst).toBe(12)
		expect(Configuration.requestRefillPerSecond).toBe(4)
		expect(table.isfrozen(Configuration)).toBe(true)
		for index = 1, Configuration.requestBurst do
			local route = ROUTES[(index - 1) % #ROUTES + 1]
			table.clear(f.state.calls)
			f.routes[route](f.player, { requestId = "same_retry" })
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

	it("forwards mutation payloads intact, including invalid and forbidden fields", function()
		for _, route in
			{
				"BuildShrine",
				"ExpandBase",
				"GetShrine",
				"AssignShrineWorker",
				"RemoveShrineWorker",
				"UpgradeShrine",
				"DismantleShrine",
			}
		do
			local f = fixture()
			local inputs: { unknown } = {
				false,
				42,
				"invalid",
				{ requestId = "0:build", expectedGoldCost = 0, targetUserId = 2002, extra = {} },
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
	end)

	it(
		"returns the exact view and immutable receipts without prechecking current world access",
		function()
			local f = fixture()
			FreezeUtil.DeepFreeze(f.state.view)
			expect(f.api.GetBase(f.player)).toBe(f.state.view)
			FreezeUtil.DeepFreeze(f.state.shrineView)
			expect(f.api.GetShrine(f.player, { shrineInstanceId = "owned" })).toBe(
				f.state.shrineView
			)
			for _, route in MUTATIONS do
				table.clear(f.state.calls)
				local receipt: Types.TransactionResult = {
					ok = true,
					revision = 2,
					replayed = true,
					values = { shrineInstanceId = "old_shrine", goldSpent = 100 },
				}
				FreezeUtil.DeepFreeze(receipt)
				f.state.result = receipt
				local original = { requestId = "0:original", expectedRevision = 0 }
				expect(f.routes[route](f.player, original)).toBe(receipt)
				expect(f.state.payload).toBe(original)
				expect(f.state.calls).toEqual({ "available", "allow", route })
			end
		end
	)

	it("returns small domain failures without a fresh view or extra domain calls", function()
		for _, code in
			{
				"InvalidRequest",
				"DataUnavailable",
				"OutOfRange",
				"StaleRevision",
				"PriceChanged",
				"BaseFull",
			}
		do
			local f = fixture()
			f.state.result = { ok = false, code = code, revision = 8 }
			for _, route in MUTATIONS do
				table.clear(f.state.calls)
				expect(f.routes[route](f.player, {})).toBe(f.state.result)
				expect(f.state.calls).toEqual({ "available", "allow", route })
			end
		end
	end)
end)
