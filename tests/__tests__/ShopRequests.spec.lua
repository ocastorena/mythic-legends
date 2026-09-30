--!strict
-- ServerStorage/Tests/__tests__/ShopRequests.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local ShopRequests = require(ServerScriptService.Services.ShopService.ShopRequests)
local ShopCommands = require(ServerScriptService.Services.ShopService.ShopCommands)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function fixture()
	-- The adapter treats Player as an opaque identity passed to its injected authorization gate.
	local player = (table.freeze({}) :: unknown) :: Player
	local state = {
		available = true,
		allowed = true,
		calls = {} :: { string },
		payload = nil :: unknown,
		transaction = { ok = true, revision = 5, values = { quantity = 1 } } :: Types.TransactionResult,
		shop = {
			ok = true,
			revision = 6,
			view = {
				sampledAt = 3600,
				periodId = 1,
				startsAt = 3600,
				refreshAt = 7200,
				featuredElement = "Water",
				offers = {},
				upgrades = {},
			},
		} :: Types.ShopViewResult,
	}
	local api = ShopRequests.new({
		isAvailable = function(caller: Player): boolean
			expect(caller).toBe(player)
			table.insert(state.calls, "available")
			return state.available
		end,
		allowRequest = function(caller: Player): boolean
			expect(caller).toBe(player)
			table.insert(state.calls, "allow")
			return state.allowed
		end,
		getShop = function(caller: Player): Types.ShopViewResult
			expect(caller).toBe(player)
			table.insert(state.calls, "get")
			return state.shop
		end,
		buyOffer = function(caller: Player, payload: unknown): Types.TransactionResult
			expect(caller).toBe(player)
			table.insert(state.calls, "buy")
			state.payload = payload
			return state.transaction
		end,
	})
	return { player = player, state = state, api = api }
end

describe("ShopRequests", function()
	it(
		"composes real quotes, purchases, cross-period replay, and stale-offer refresh without saving views",
		function()
			local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
			local data = (
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate)) :: unknown
			) :: Types.PlayerDoc
			assert(
				ProfileSchema.Prepare(data, function()
					return "endpoint_station"
				end, 0),
				"[ShopRequests.spec] Fixture preparation failed"
			)
			data.currency.gold = 100
			local now, views, mutations = 0, 0, 0
			local source: ShopCommands.DataSource = {
				GetLoadedData = function(caller: Player): Types.PlayerDoc?
					return if caller == player then data else nil
				end,
				Transact = function(caller, envelope, mutate)
					expect(caller).toBe(player)
					mutations += 1
					return Transactions.Run(data, envelope, function(draft)
						return mutate(draft, now)
					end, function()
						return true
					end)
				end,
			}
			local commands = ShopCommands.new(source, {
				clock = function()
					return now
				end,
			})
			local api = ShopRequests.new({
				isAvailable = function(caller)
					return caller == player
				end,
				allowRequest = function()
					return true
				end,
				getShop = function(caller)
					views += 1
					return commands.Get(caller)
				end,
				buyOffer = function(caller, payload)
					return commands.Buy(caller, payload :: Types.BuyShopOfferRequest)
				end,
			})
			local quote = api.Get(player)
			local view = assert(quote.view, "[ShopRequests.spec] Expected quote")
			local offer = view.offers[1]
			local request: Types.BuyShopOfferRequest = {
				requestId = `{quote.revision}:purchase`,
				expectedRevision = quote.revision,
				periodId = view.periodId,
				offerId = offer.offerId,
				offerRevision = offer.offerRevision,
				quantity = 2,
			}
			local bought = api.Buy(player, request)
			expect(bought.transaction.ok).toBe(true)
			expect(bought.shop).toBeNil()
			expect(data.currency.gold).toBe(80)
			expect(data.materials[offer.materialId :: string].total).toBe(2)
			now = view.refreshAt
			local retry = api.Buy(player, request)
			expect(retry.transaction.ok).toBe(true)
			expect(retry.transaction.replayed).toBe(true)
			expect(retry.transaction.values).toEqual(bought.transaction.values)
			expect(retry.shop).toBeNil()
			expect(views).toBe(1)
			expect(data.currency.gold).toBe(80)
			expect(data.materials[offer.materialId :: string].total).toBe(2)
			local stale = table.clone(request)
			stale.requestId = `{bought.transaction.revision}:expired`
			stale.expectedRevision = bought.transaction.revision
			local expired = api.Buy(player, stale)
			expect(expired.transaction.code).toBe("OfferExpired")
			local fresh = assert(expired.shop, "[ShopRequests.spec] Expected refreshed read")
			expect((assert(fresh.view, "[ShopRequests.spec] Expected refreshed quote")).periodId).toBe(
				view.periodId + 1
			)
			expect(views).toBe(2)
			local transactionState =
				assert(data.transactions, "[ShopRequests.spec] Expected receipts")
			expect(transactionState.receipts[stale.requestId].result).toEqual(expired.transaction)
			expect((assert(data.shop, "[ShopRequests.spec] Expected stock ledger")).periodId).toBe(
				view.periodId
			)
			for _, field in { "targetUserId", "unexpected" } do
				local invalid = table.clone(stale) :: any
				invalid.requestId = `{transactionState.revision}:{field}`
				invalid.expectedRevision = transactionState.revision
				invalid[field] = 123
				local before = mutations
				expect(api.Buy(player, invalid).transaction.code).toBe("InvalidRequest")
				expect(mutations).toBe(before)
				expect(views).toBe(2)
			end
		end
	)

	it("rejects unavailable callers before admission or any protected work", function()
		local f = fixture()
		f.state.available = false
		local rejected = { ok = false, code = "DataUnavailable", revision = 0 }
		expect(f.api.Get(f.player)).toEqual(rejected)
		expect(f.api.Buy(f.player, {})).toEqual({ transaction = rejected })
		expect(f.state.calls).toEqual({ "available", "available" })
	end)

	it("shares admission for reads and buys without constructing views on rate denial", function()
		local f = fixture()
		f.state.allowed = false
		expect(f.api.Get(f.player)).toEqual({ ok = false, code = "RateLimited", revision = 0 })
		expect(f.api.Buy(f.player, {})).toEqual({
			transaction = { ok = false, code = "RateLimited", revision = 0 },
		})
		expect(f.state.calls).toEqual({ "available", "allow", "available", "allow" })
	end)

	it(
		"returns admitted views and small unavailable-profile results exactly as supplied",
		function()
			local f = fixture()
			expect(f.api.Get(f.player)).toEqual(f.state.shop)
			expect(f.state.calls).toEqual({ "available", "allow", "get" })
			table.clear(f.state.calls)
			f.state.shop = { ok = false, code = "DataUnavailable", revision = 0 }
			expect(f.api.Get(f.player)).toEqual(f.state.shop)
			expect(f.state.calls).toEqual({ "available", "allow", "get" })
		end
	)

	it("forwards the original caller and payload without sanitizing forbidden fields", function()
		local f = fixture()
		local payload = { requestId = "0:test", targetUserId = 123, unitGold = 0, unexpected = {} }
		f.state.transaction = { ok = false, code = "InvalidRequest", revision = 4 }
		expect(f.api.Buy(f.player, payload)).toEqual({ transaction = f.state.transaction })
		expect(f.state.payload).toBe(payload)
		expect(payload.targetUserId).toBe(123)
		expect(f.state.calls).toEqual({ "available", "allow", "buy" })
		for _, raw in { false, "malformed", 123 } do
			table.clear(f.state.calls)
			expect(f.api.Buy(f.player, raw).transaction.code).toBe("InvalidRequest")
			expect(f.state.payload).toBe(raw)
			expect(f.state.calls).toEqual({ "available", "allow", "buy" })
		end
	end)

	it(
		"preserves committed retries after refresh without checking a current period before Buy",
		function()
			local f = fixture()
			local receipt: Types.TransactionResult = {
				ok = true,
				revision = 2,
				replayed = true,
				values = { periodId = 0, quantity = 1, goldSpent = 10 },
			}
			f.state.transaction = FreezeUtil.DeepFreeze(receipt)
			local payload = {
				requestId = "0:original",
				expectedRevision = 0,
				periodId = 0,
				offerId = "fire_material",
				offerRevision = "original",
				quantity = 1,
			}
			local result = f.api.Buy(f.player, payload)
			expect(result).toEqual({ transaction = receipt })
			expect(result.shop).toBeNil()
			expect(f.state.payload).toBe(payload)
			expect(f.state.calls).toEqual({ "available", "allow", "buy" })
		end
	)

	it(
		"attaches fresh quote views separately from immutable expired or changed transaction receipts",
		function()
			for _, code in { "OfferExpired", "OfferChanged" } do
				local f = fixture()
				local receipt: Types.TransactionResult =
					{ ok = false, code = code, revision = 5, replayed = true }
				f.state.transaction = FreezeUtil.DeepFreeze(receipt)
				local result = f.api.Buy(f.player, {})
				expect(result).toEqual({ transaction = receipt, shop = f.state.shop })
				expect(result.transaction.revision).toBe(5)
				expect((result.shop :: Types.ShopViewResult).revision).toBe(6)
				expect(receipt).toEqual({ ok = false, code = code, revision = 5, replayed = true })
				expect(f.state.calls).toEqual({ "available", "allow", "buy", "get" })
			end
		end
	)

	it(
		"keeps failed refreshed reads separate and does not expand unrelated failures into views",
		function()
			local f = fixture()
			f.state.transaction = { ok = false, code = "OfferExpired", revision = 5 }
			f.state.shop = { ok = false, code = "DataUnavailable", revision = 0 }
			expect(f.api.Buy(f.player, {})).toEqual({
				transaction = f.state.transaction,
				shop = f.state.shop,
			})
			expect(f.state.calls).toEqual({ "available", "allow", "buy", "get" })
			for _, code in
				{
					"InvalidRequest",
					"RevisionConflict",
					"InsufficientStock",
					"DataUnavailable",
					"InventoryFull",
				}
			do
				table.clear(f.state.calls)
				f.state.transaction = { ok = false, code = code, revision = 5 }
				expect(f.api.Buy(f.player, {})).toEqual({ transaction = f.state.transaction })
				expect(f.state.calls).toEqual({ "available", "allow", "buy" })
			end
		end
	)
end)
