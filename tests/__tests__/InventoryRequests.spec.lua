--!strict
-- ServerStorage/Tests/__tests__/InventoryRequests.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local InventoryRequests = require(ServerScriptService.Services.InventoryService.InventoryRequests)
local MaterialDisposalCommand =
	require(ServerScriptService.Services.InventoryService.MaterialDisposalCommand)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
type Action =
	"EvolveMythling"
	| "SellMythling"
	| "SellEquipment"
	| "SellMaterial"
	| "DiscardMaterial"
	| "UpgradeCapacity"
local ACTIONS: { Action } = {
	"EvolveMythling",
	"SellMythling",
	"SellEquipment",
	"SellMaterial",
	"DiscardMaterial",
	"UpgradeCapacity",
}

local function fixture(sell: InventoryRequests.Command?)
	-- Only the injected availability predicate authorizes this opaque test identity.
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		available = true,
		allowed = true,
		remaining = nil :: number?,
		calls = {} :: { string },
		payload = nil :: unknown,
		result = { ok = true, revision = 8, values = { changed = true } } :: Types.TransactionResult,
	}
	local function command(action: Action): InventoryRequests.Command
		return function(caller, payload)
			expect(caller).toBe(player)
			table.insert(state.calls, action)
			state.payload = payload
			return state.result
		end
	end
	local commands: InventoryRequests.Commands = {
		EvolveMythling = command("EvolveMythling"),
		SellMythling = command("SellMythling"),
		SellEquipment = command("SellEquipment"),
		SellMaterial = sell or command("SellMaterial"),
		DiscardMaterial = command("DiscardMaterial"),
		UpgradeCapacity = command("UpgradeCapacity"),
	}
	local api = InventoryRequests.new({
		commands = commands,
		isAvailable = function(caller)
			expect(caller).toBe(player)
			table.insert(state.calls, "available")
			return state.available
		end,
		allowRequest = function(caller)
			expect(caller).toBe(player)
			table.insert(state.calls, "allow")
			local remaining = state.remaining
			if not state.allowed or (remaining ~= nil and remaining < 1) then
				return false
			end
			if remaining then
				state.remaining = remaining - 1
			end
			return true
		end,
	})
	return { player = player, state = state, api = api }
end

describe("InventoryRequests", function()
	it(
		"dispatches all six actions with the exact caller and unsanitized payload after admission",
		function()
			local f = fixture()
			for _, action in ACTIONS do
				table.clear(f.state.calls)
				local payload = { requestId = "7:command", targetUserId = 999, unexpected = {} }
				expect(f.api[action](f.player, payload)).toEqual(f.state.result)
				expect(f.state.payload).toBe(payload)
				expect(f.state.calls).toEqual({ "available", "allow", action })
			end
		end
	)

	it("denies unavailable and rate-limited callers before any command work", function()
		for _, action in ACTIONS do
			local f = fixture()
			f.state.available = false
			expect(f.api[action](f.player, {})).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.state.calls).toEqual({ "available" })
			table.clear(f.state.calls)
			f.state.available, f.state.allowed = true, false
			expect(f.api[action](f.player, {})).toEqual({
				ok = false,
				code = "RateLimited",
				revision = 0,
			})
			expect(f.state.calls).toEqual({ "available", "allow" })
		end
	end)

	it(
		"returns frozen replay and failure receipts unchanged without quote or ownership prechecks",
		function()
			local f = fixture()
			local results: { Types.TransactionResult } = {
				{
					ok = true,
					revision = 3,
					replayed = true,
					values = { workerId = "already_sold" },
				},
				{ ok = false, code = "RevisionConflict", revision = 9 },
				{ ok = false, code = "InvalidRequest", revision = 9 },
			}
			for _, result in results do
				f.state.result = FreezeUtil.DeepFreeze(result)
				for _, action in ACTIONS do
					table.clear(f.state.calls)
					expect(f.api[action](f.player, "untrusted")).toEqual(result)
					expect(f.state.calls).toEqual({ "available", "allow", action })
				end
			end
		end
	)

	it(
		"makes legacy deletion a nonmutating tombstone even for assigned or pending-work identities",
		function()
			local f = fixture()
			local workers = {
				assigned = { standId = 1, typeId = "mythling_0001", pendingXp = 7 },
				pending = { typeId = "mythling_0002", pendingXp = 12 },
			}
			local before = HttpService:JSONEncode(workers)
			for _, payload in { "assigned", "pending", "missing", workers, false, 123 } do
				table.clear(f.state.calls)
				expect(f.api.DeleteMythling(f.player, payload)).toEqual({
					ok = false,
					code = "UnsupportedAction",
				})
				expect(f.state.calls).toEqual({ "available", "allow" })
				expect(f.state.payload).toBeNil()
			end
			expect(HttpService:JSONEncode(workers)).toBe(before)
			f.state.available = false
			expect(f.api.DeleteMythling(f.player, "assigned")).toEqual({
				ok = false,
				code = "DataUnavailable",
			})
			f.state.available, f.state.allowed = true, false
			expect(f.api.DeleteMythling(f.player, "pending")).toEqual({
				ok = false,
				code = "RateLimited",
			})
		end
	)

	it("charges one shared admission budget for canonical actions and legacy deletion", function()
		local f = fixture()
		f.state.remaining = 1
		expect(f.api.DeleteMythling(f.player, "owned").code).toBe("UnsupportedAction")
		expect(f.api.SellMaterial(f.player, {}).code).toBe("RateLimited")
		expect(f.state.calls).toEqual({ "available", "allow", "available", "allow" })
		f.state.remaining = 1
		expect(f.api.UpgradeCapacity(f.player, {}).ok).toBe(true)
		expect(f.api.DeleteMythling(f.player, "owned").code).toBe("RateLimited")
	end)

	it(
		"composes a real atomic Material sale with duplicate replay and strict forged-field rejection",
		function()
			local data = (
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate)) :: unknown
			) :: Types.PlayerDoc
			assert(
				ProfileSchema.Prepare(data, function()
					return "inventory_station"
				end, 0),
				"[InventoryRequests.spec] Fixture preparation failed"
			)
			data.currency.gold = 100
			data.materials.fire_material = { total = 10 }
			local mutations, reads = 0, 0
			local source: MaterialDisposalCommand.DataSource = {
				GetLoadedData = function(): Types.PlayerDoc?
					reads += 1
					return data
				end,
				Transact = function(_player, envelope, mutate)
					mutations += 1
					return Transactions.Run(data, envelope, function(draft)
						return mutate(draft, 0)
					end, function()
						return true
					end)
				end,
			}
			local disposal = MaterialDisposalCommand.new(source)
			local f = fixture(function(caller, payload)
				return disposal.Sell(caller, payload :: Types.SellMaterialRequest)
			end)
			local request: Types.SellMaterialRequest = {
				requestId = "0:sale",
				expectedRevision = 0,
				materialId = "fire_material",
				quantity = 3,
				expectedOwnedQuantity = 10,
				expectedUnitGold = 2,
			}
			local sold = f.api.SellMaterial(f.player, request)
			expect(sold.ok).toBe(true)
			expect(data.currency.gold).toBe(106)
			expect(data.materials.fire_material.total).toBe(7)
			local replay = f.api.SellMaterial(f.player, request)
			expect(replay.replayed).toBe(true)
			expect(replay.values).toEqual(sold.values)
			expect(data.currency.gold).toBe(106)
			expect(data.materials.fire_material.total).toBe(7)
			local invalid = table.clone(request) :: any
			invalid.requestId, invalid.expectedRevision, invalid.targetUserId = "1:forged", 1, 999
			expect(f.api.SellMaterial(f.player, invalid).code).toBe("InvalidRequest")
			expect(mutations).toBe(2)
			local before = reads
			expect(f.api.DeleteMythling(f.player, "assigned").code).toBe("UnsupportedAction")
			f.state.allowed = false
			expect(f.api.SellMaterial(f.player, request).code).toBe("RateLimited")
			expect(reads).toBe(before)
		end
	)
end)
