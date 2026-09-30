--!strict
-- ServerStorage/Tests/__tests__/ProductionRequests.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Configuration = require(ReplicatedStorage.Shared.Configurations.ProductionRequests)
local ProductionRequests =
	require(ServerScriptService.Services.ProductionService.ProductionRequests)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function fixture()
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		available = true,
		remaining = Configuration.requestBurst,
		calls = {} :: { string },
		payload = nil :: unknown,
		result = { ok = true, revision = 7, values = { collected = 3 } } :: Types.TransactionResult,
	}
	local api = ProductionRequests.new({
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
		collectShrine = function(caller, input)
			expect(caller).toBe(player)
			table.insert(state.calls, "collect")
			state.payload = input
			return state.result
		end,
	})
	return { player = player, state = state, api = api }
end

describe("ProductionRequests", function()
	it("rejects unavailable callers before admission or protected work", function()
		local f = fixture()
		f.state.available = false
		expect(f.api.CollectShrine(f.player, {})).toEqual({
			ok = false,
			code = "DataUnavailable",
			revision = 0,
		})
		expect(f.state.calls).toEqual({ "available" })
		expect(f.state.remaining).toBe(Configuration.requestBurst)
		expect(f.state.payload).toBeNil()
	end)

	it("shares the configured collection budget across selected Shrine identities", function()
		local f = fixture()
		expect(Configuration.requestBurst).toBe(12)
		expect(Configuration.requestRefillPerSecond).toBe(4)
		expect(table.isfrozen(Configuration)).toBe(true)
		for index = 1, Configuration.requestBurst do
			table.clear(f.state.calls)
			f.api.CollectShrine(f.player, { shrineInstanceId = `shrine_{index}` })
			expect(f.state.calls).toEqual({ "available", "allow", "collect" })
		end
		table.clear(f.state.calls)
		expect(f.api.CollectShrine(f.player, { shrineInstanceId = "different" })).toEqual({
			ok = false,
			code = "RateLimited",
			revision = 0,
		})
		expect(f.state.calls).toEqual({ "available", "allow" })
	end)

	it("forwards raw payloads without accepting or stripping forbidden fields", function()
		local f = fixture()
		local inputs: { unknown } = {
			false,
			42,
			"invalid",
			{ shrineInstanceId = "first", targetUserId = 2002, amount = 999, unexpected = {} },
			setmetatable({}, {}),
		}
		for _, input in inputs do
			table.clear(f.state.calls)
			expect(f.api.CollectShrine(f.player, input)).toBe(f.state.result)
			expect(f.state.payload).toBe(input)
			expect(f.state.calls).toEqual({ "available", "allow", "collect" })
		end
		f.api.CollectShrine(f.player, nil)
		expect(f.state.payload).toBeNil()
	end)

	it(
		"returns immutable committed retries unchanged without a location or amount precheck",
		function()
			local f = fixture()
			local receipt: Types.TransactionResult = {
				ok = true,
				revision = 3,
				replayed = true,
				values = {
					shrineInstanceId = "removed_shrine",
					materialId = "fire_material",
					collected = 3,
					remaining = 0,
					settledAt = 2.5,
				},
			}
			FreezeUtil.DeepFreeze(receipt)
			f.state.result = receipt
			local original = {
				requestId = "0:original",
				expectedRevision = 0,
				shrineInstanceId = "removed_shrine",
				expectedMaterialId = "fire_material",
			}
			expect(f.api.CollectShrine(f.player, original)).toBe(receipt)
			expect(f.state.payload).toBe(original)
			expect(f.state.calls).toEqual({ "available", "allow", "collect" })
		end
	)

	it(
		"returns domain failures without fabricating an extra view or changing the result",
		function()
			for _, code in
				{
					"InvalidRequest",
					"DataUnavailable",
					"ShrineNotOwned",
					"OutOfRange",
					"StaleRevision",
					"NothingToCollect",
					"InventoryFull",
				}
			do
				local f = fixture()
				f.state.result = { ok = false, code = code, revision = 9 }
				expect(f.api.CollectShrine(f.player, {})).toBe(f.state.result)
				expect(f.state.calls).toEqual({ "available", "allow", "collect" })
			end
		end
	)
end)
