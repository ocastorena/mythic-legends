--!strict
-- ServerStorage/Tests/__tests__/ShopCommands.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local ShopCommands = require(ServerScriptService.Services.ShopService.ShopCommands)
local ShopCatalog = require(ServerScriptService.Services.ShopService.ShopCatalog)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }
local MAX_SAFE_INTEGER = 2 ^ 53 - 1

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function profile(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	assert(
		ProfileSchema.Prepare(data, function()
			return "shop_station"
		end, 0),
		"[ShopCommands.spec] Fixture preparation failed"
	)
	data.currency.gold = 10_000
	data.materials.fire_material = { total = 5 }
	data.mythlings.worker = {
		typeId = "mythling_0001",
		variantId = "regular",
		claimedAt = 0,
		level = 6,
		xp = 17,
		pendingXp = 0.5,
	}
	return data
end

local function job(): Types.CraftingJob
	return {
		status = "Active",
		reservations = { equipment = 1, materials = { fire_material = 5 } },
		receipt = {
			version = 1,
			recipeId = "elemental_sword_fire",
			stationId = "shop_station",
			craftingStationId = "basic_crafting_station",
			startedAt = 0,
			completesAt = 60,
			result = {
				definitionId = "elemental_sword",
				finishId = "fire",
				quantity = 1,
				instanceIds = { "promised_output" },
			},
			paid = { gold = 50, materials = { fire_material = 5 } },
		},
	}
end

local function currentOffer(now: number, kind: string, identity: string?): Types.ShopOffer
	local period = assert(ShopCatalog.Resolve(now), "[ShopCommands.spec] Expected catalogue")
	for _, offer in period.offers do
		if
			offer.kind == kind
			and (identity == nil or offer.materialId == identity or offer.definitionId == identity)
		then
			return offer
		end
	end
	error("[ShopCommands.spec] Missing requested offer")
end

local function request(
	revision: number,
	token: string,
	now: number?,
	kind: string?,
	identity: string?
): Types.BuyShopOfferRequest
	local timestamp = now or 0
	local period = assert(ShopCatalog.Resolve(timestamp), "[ShopCommands.spec] Expected catalogue")
	local offer = currentOffer(timestamp, kind or "Material", identity)
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		periodId = period.periodId,
		offerId = offer.offerId,
		offerRevision = offer.offerRevision,
		quantity = 1,
	}
end

local function fixture(saved: Types.PlayerDoc?)
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local data = saved or profile()
	local state = {
		now = 0,
		viewNow = 0,
		active = true,
		available = true,
		clockThrows = false,
		idThrows = false,
		idOverride = nil :: string?,
		loseSessionAfterCallback = false,
		prepareJobs = false,
		clockCalls = 0,
		idCalls = 0,
		transactionCalls = 0,
		callbackCalls = 0,
		operations = {} :: { string },
	}
	local jobs = CraftingJobs.new()
	local source: ShopCommands.DataSource = {
		GetLoadedData = function(requestingPlayer: Player): Types.PlayerDoc?
			return if requestingPlayer == player
					and state.active
					and state.available
				then data
				else nil
		end,
		Transact = function(requestingPlayer, envelope, mutate)
			state.transactionCalls += 1
			table.insert(state.operations, envelope.operation)
			if requestingPlayer ~= player or not state.available then
				return { ok = false, code = "DataUnavailable", revision = 0 }
			end
			return Transactions.Run(data, envelope, function(draft)
				state.callbackCalls += 1
				if state.prepareJobs then
					local prepared = jobs.SettleDueToDraft(draft, state.now)
					if not prepared.ok then
						return prepared
					end
				end
				local result = mutate(draft, state.now)
				if state.loseSessionAfterCallback then
					state.active = false
				end
				return result
			end, function()
				return state.active
			end)
		end,
	}
	local api = ShopCommands.new(source, {
		clock = function()
			state.clockCalls += 1
			if state.clockThrows then
				error("test clock failure")
			end
			return state.viewNow
		end,
		createId = function()
			state.idCalls += 1
			if state.idThrows then
				error("test ID failure")
			end
			return state.idOverride or `bought_{state.idCalls}`
		end,
	})
	return { player = player, data = data, state = state, api = api }
end

local function viewOffer(view: Types.ShopView, offerId: string): Types.ShopOfferView
	for _, offer in view.offers do
		if offer.offerId == offerId then
			return offer
		end
	end
	error("[ShopCommands.spec] Missing view offer")
end

describe("ShopCommands read-only view", function()
	it(
		"returns detached views, including upgrades, without exposing saved receipts or stock maps",
		function()
			local f = fixture()
			local selected = currentOffer(0, "Material")
			f.data.shop = { periodId = 0, purchased = { [selected.stockKey] = 3, retired = 9 } }
			local before = copy(f.data)
			local view = assert(f.api.Get(f.player).view, "[ShopCommands.spec] Expected view")
			expect(#view.upgrades).toBe(3)
			expect((view :: any).purchased).toBeNil()
			expect((view :: any).transactions).toBeNil()
			view.offers[1].remainingStock = 999
			view.offers[1].unitGold = 0
			view.upgrades[1].materials[1].ownedQuantity = 999
			local refreshed =
				assert(f.api.Get(f.player).view, "[ShopCommands.spec] Expected repeated view")
			expect(viewOffer(refreshed, selected.offerId).remainingStock).toBe(7)
			expect(viewOffer(refreshed, selected.offerId).unitGold).toBe(10)
			expect(f.data).toEqual(before)
		end
	)

	it(
		"fails closed for malformed bookkeeping or stock and never erases future usage on a view",
		function()
			local cases: { { code: string, mutate: (any) -> () } } = {
				{
					code = "InvalidTransaction",
					mutate = function(data)
						data.transactions.revision = -1
					end,
				},
				{
					code = "InvalidShopState",
					mutate = function(data)
						data.shop = {}
					end,
				},
				{
					code = "ShopClockBehind",
					mutate = function(data)
						data.shop = { periodId = 1, purchased = { retained = 1 } }
					end,
				},
				{
					code = "InvalidInventoryUpgrade",
					mutate = function(data)
						data.inventoryUpgrades.equipment = 3
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				case.mutate(f.data)
				local before = copy(f.data)
				local result = f.api.Get(f.player)
				expect(result.ok).toBe(false)
				expect(result.code).toBe(case.code)
				expect(result.view).toBeNil()
				expect(f.data).toEqual(before)
				expect(f.state.transactionCalls).toBe(0)
			end
		end
	)

	it(
		"lists all six Materials and one matching Featured pair without creating stock or transactions",
		function()
			for index, element in ELEMENTS do
				local f = fixture()
				f.state.viewNow = (index - 1) * 3_600
				local before = copy(f.data)
				local result = f.api.Get(f.player)
				expect(result.ok).toBe(true)
				expect(result.revision).toBe(0)
				local view = assert(result.view, "[ShopCommands.spec] Expected view")
				expect(#view.offers).toBe(8)
				expect(view.sampledAt).toBe(f.state.viewNow)
				expect(view.refreshAt - view.startsAt).toBe(3_600)
				local materials, equipment = 0, 0
				for _, offer in view.offers do
					if offer.kind == "Material" then
						materials += 1
						expect(offer.unitGold).toBe(10)
						expect(offer.remainingStock).toBe(10)
						expect(offer.maxPurchasable).toBe(10)
					else
						equipment += 1
						expect(offer.finishId).toBe(element)
						expect(offer.unitGold).toBe(150)
						expect(offer.remainingStock).toBe(1)
						expect(offer.maxPurchasable).toBe(1)
					end
				end
				expect(materials).toBe(6)
				expect(equipment).toBe(2)
				expect(f.data).toEqual(before)
				expect(f.state.transactionCalls).toBe(0)
				expect(f.state.idCalls).toBe(0)
				expect(f.state.clockCalls).toBe(1)
			end
		end
	)

	it(
		"keeps exhausted offers listed across reconnect and views later restock without writing it",
		function()
			local f = fixture()
			local selected = currentOffer(0, "Material")
			local buy = request(0, "exhaust")
			buy.quantity = 10
			expect(f.api.Buy(f.player, buy).ok).toBe(true)
			local restored = fixture(copy(f.data))
			local before = copy(restored.data)
			local exhausted =
				assert(restored.api.Get(restored.player).view, "[ShopCommands.spec] Expected view")
			expect(#exhausted.offers).toBe(8)
			expect(viewOffer(exhausted, selected.offerId).remainingStock).toBe(0)
			expect(viewOffer(exhausted, selected.offerId).maxPurchasable).toBe(0)
			for _, timestamp in { 3_600, 21_600, 3_600_000 } do
				restored.state.viewNow = timestamp
				local view = assert(
					restored.api.Get(restored.player).view,
					"[ShopCommands.spec] Expected later view"
				)
				local offer = currentOffer(timestamp, "Material", selected.materialId)
				expect(viewOffer(view, offer.offerId).remainingStock).toBe(10)
				expect(restored.data).toEqual(before)
			end
		end
	)

	it("shows personal affordability and reserved capacity without consuming either", function()
		local f = fixture()
		f.data.currency.gold = 25
		local material = currentOffer(0, "Material")
		local gear = currentOffer(0, "Equipment")
		local view = assert(f.api.Get(f.player).view, "[ShopCommands.spec] Expected view")
		expect(viewOffer(view, material.offerId).maxPurchasable).toBe(2)
		expect(viewOffer(view, gear.offerId).maxPurchasable).toBe(0)
		expect(f.data.currency.gold).toBe(25)
		expect(f.data.shop).toBeNil()
	end)
end)

describe("ShopCommands atomic delivery", function()
	it(
		"buys exact quantities of all six Materials and preserves unrelated mutable data and identities",
		function()
			for _, element in ELEMENTS do
				local f = fixture()
				local id = `{element}_material`
				f.data.materials[id] = (
					{ total = 7, retained = "opaque" } :: unknown
				) :: Types.MaterialEntry
				local entry, materials, currency, equipment, loadout, worker =
					f.data.materials[id],
					f.data.materials,
					f.data.currency,
					f.data.equipment,
					f.data.combatLoadout,
					f.data.mythlings.worker
				local before = gameplay(f.data)
				local selected = currentOffer(0, "Material", id)
				local buy = request(0, "all-elements", 0, "Material", id)
				buy.quantity = 6
				local result = f.api.Buy(f.player, buy)
				expect(result).toEqual({
					ok = true,
					revision = 1,
					values = {
						offerId = selected.offerId,
						offerRevision = selected.offerRevision,
						periodId = 0,
						quantity = 6,
						unitGold = 10,
						goldSpent = 60,
						goldBalance = 9_940,
						remainingStock = 4,
						materialId = id,
					},
				})
				before.currency.gold = 9_940
				before.materials[id].total = 13
				before.shop = { periodId = 0, purchased = { [selected.stockKey] = 6 } }
				expect(gameplay(f.data)).toEqual(before)
				expect(f.data.materials).toBe(materials)
				expect(f.data.materials[id]).toBe(entry)
				expect(f.data.currency).toBe(currency)
				expect(f.data.equipment).toBe(equipment)
				expect(f.data.combatLoadout).toBe(loadout)
				expect(f.data.mythlings.worker).toBe(worker)
				expect(f.state.operations).toEqual({ "Shop.BuyOffer" })
				expect(f.state.clockCalls).toBe(0)
				expect(f.state.idCalls).toBe(0)
			end
		end
	)

	it(
		"grants all twelve fixed Featured variants without equipping, XP, jobs, or copied metadata",
		function()
			for index, finish in ELEMENTS do
				for _, definition in { "elemental_sword", "elemental_shield" } do
					local f = fixture()
					f.state.now = (index - 1) * 3_600
					local before = gameplay(f.data)
					local selected = currentOffer(f.state.now, "Equipment", definition)
					local result = f.api.Buy(
						f.player,
						request(0, "featured", f.state.now, "Equipment", definition)
					)
					expect(result.ok).toBe(true)
					expect(result.revision).toBe(1)
					expect(result.values).toEqual({
						offerId = selected.offerId,
						offerRevision = selected.offerRevision,
						periodId = index - 1,
						quantity = 1,
						unitGold = 150,
						goldSpent = 150,
						goldBalance = 9_850,
						remainingStock = 0,
						instanceId = "bought_1",
						definitionId = definition,
						finishId = finish,
					})
					before.currency.gold = 9_850
					before.shop = { periodId = index - 1, purchased = { [selected.stockKey] = 1 } }
					before.equipment.bought_1 =
						{ definitionId = definition, finishId = finish, isStarterGrant = false }
					expect(gameplay(f.data)).toEqual(before)
					expect(f.state.idCalls).toBe(1)
					expect(f.state.clockCalls).toBe(0)
				end
			end
		end
	)

	it(
		"replaces old personal usage only on a committed new-period purchase without resetting upgrades",
		function()
			local f = fixture()
			local old = currentOffer(0, "Material")
			f.data.shop = { periodId = 0, purchased = { [old.stockKey] = 9, retired = 5 } }
			f.data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 1 }
			f.state.now = 100 * 3_600
			local selected = currentOffer(f.state.now, "Material")
			expect(f.api.Buy(f.player, request(0, "new-period", f.state.now)).ok).toBe(true)
			expect(f.data.shop).toEqual({ periodId = 100, purchased = { [selected.stockKey] = 1 } })
			expect(f.data.inventoryUpgrades).toEqual({ materials = 1, mythlings = 2, equipment = 1 })
			assert(f.data.shop, "[ShopCommands.spec] Expected stock").purchased.retired = 8
			expect(f.api.Buy(f.player, request(1, "same-period", f.state.now)).ok).toBe(true)
			expect(assert(f.data.shop, "[ShopCommands.spec] Expected stock").purchased.retired).toBe(
				8
			)
		end
	)

	it("uses transaction time rather than the view clock at a refresh boundary", function()
		local f = fixture()
		f.state.viewNow = 3_599.99
		expect(f.api.Get(f.player).ok).toBe(true)
		local before = gameplay(f.data)
		f.state.now = 3_600
		expect(f.api.Buy(f.player, request(0, "expired")).code).toBe("OfferExpired")
		expect(gameplay(f.data)).toEqual(before)
		expect(f.state.clockCalls).toBe(1)
		expect(f.api.Buy(f.player, request(1, "current", 3_600)).ok).toBe(true)
	end)
end)

describe("ShopCommands capacity and rejection", function()
	it("requires the entire quantity to fit owned-plus-refund Material capacity", function()
		local f = fixture()
		f.data.materials = { fire_material = { total = 995 }, water_material = { total = 11_000 } }
		f.data.craftingJobs = {
			active = {
				status = "Active",
				reservations = { equipment = 0, materials = { fire_material = 3 } },
			},
		}
		local before = gameplay(f.data)
		local buy = request(0, "no-room", 0, "Material", "fire_material")
		buy.quantity = 3
		expect(f.api.Buy(f.player, buy).code).toBe("InventoryFull")
		expect(gameplay(f.data)).toEqual(before)
		buy = request(1, "exact-room", 0, "Material", "fire_material")
		buy.quantity = 2
		expect(f.api.Buy(f.player, buy).ok).toBe(true)
		expect(f.data.materials.fire_material.total).toBe(997)
		expect(f.data.craftingJobs).toEqual(before.craftingJobs)
	end)

	it(
		"counts protected equipped starters and promised outputs against Equipment capacity",
		function()
			local f = fixture()
			for index = 1, 9 do
				f.data.equipment[`retained_{index}`] = { definitionId = "legacy" }
			end
			f.data.craftingJobs = { active = job() }
			local before = gameplay(f.data)
			expect(f.api.Buy(f.player, request(0, "full", 0, "Equipment")).code).toBe(
				"InventoryFull"
			)
			expect(gameplay(f.data)).toEqual(before)
			expect(f.state.idCalls).toBe(0)
			f.data.inventoryUpgrades = { equipment = 1 }
			expect(f.api.Buy(f.player, request(1, "upgraded", 0, "Equipment")).ok).toBe(true)
			expect(f.data.craftingJobs).toEqual(before.craftingJobs)
		end
	)

	it(
		"rejects unavailable stock, Gold, catalogue selections, and future saved periods atomically",
		function()
			local cases: { { code: string, mutate: (any, any) -> () } } = {
				{
					code = "InsufficientGold",
					mutate = function(data, _buy)
						data.currency.gold = 9
					end,
				},
				{
					code = "InsufficientStock",
					mutate = function(_data, buy)
						buy.quantity = 11
					end,
				},
				{
					code = "OfferNotFound",
					mutate = function(_data, buy)
						buy.offerId = "unknown"
					end,
				},
				{
					code = "OfferChanged",
					mutate = function(_data, buy)
						buy.offerRevision ..= "changed"
					end,
				},
				{
					code = "OfferExpired",
					mutate = function(_data, buy)
						buy.periodId = 1
					end,
				},
				{
					code = "ShopClockBehind",
					mutate = function(data, _buy)
						data.shop = { periodId = 1, purchased = {} }
					end,
				},
				{
					code = "InvalidShopState",
					mutate = function(data, _buy)
						data.shop = { periodId = 0 }
					end,
				},
				{
					code = "InvalidInventoryUpgrade",
					mutate = function(data, _buy)
						data.inventoryUpgrades.materials = 3
					end,
				},
				{
					code = "InvalidInventoryUpgrade",
					mutate = function(data, _buy)
						data.inventoryUpgrades.equipment = -1
					end,
				},
				{
					code = "InvalidCurrency",
					mutate = function(data, _buy)
						data.currency.gold = -1
					end,
				},
				{
					code = "InvalidCurrency",
					mutate = function(data, _buy)
						data.currency.gold = 2 ^ 53
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data, _buy)
						data.materials.fire_material.total = -1
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data, _buy)
						data.equipment = false
					end,
				},
				{
					code = "InvalidReservations",
					mutate = function(data, _buy)
						data.craftingJobs = {
							bad = {
								status = "Active",
								reservations = { equipment = -1, materials = {} },
							},
						}
					end,
				},
				{
					code = "UnsupportedVersion",
					mutate = function(data, _buy)
						data.version = 6
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				local buy = request(0, "rejected")
				case.mutate(f.data, buy)
				local before = gameplay(f.data)
				expect(f.api.Buy(f.player, buy).code).toBe(case.code)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.state.idCalls).toBe(0)
			end
		end
	)

	it(
		"rejects closed-envelope and unsafe numeric violations before opening a transaction",
		function()
			local malformed: { (any) -> () } = {
				function(buy)
					buy.extra = true
				end,
				function(buy)
					buy.requestId = ""
				end,
				function(buy)
					buy.requestId = string.rep("x", 129)
				end,
				function(buy)
					buy.expectedRevision = -1
				end,
				function(buy)
					buy.expectedRevision = 2 ^ 53
				end,
				function(buy)
					buy.periodId = -1
				end,
				function(buy)
					buy.periodId = 0.5
				end,
				function(buy)
					buy.periodId = math.huge
				end,
				function(buy)
					buy.quantity = 0
				end,
				function(buy)
					buy.quantity = -1
				end,
				function(buy)
					buy.quantity = 1.5
				end,
				function(buy)
					buy.quantity = 2 ^ 53
				end,
				function(buy)
					buy.quantity = 0 / 0
				end,
				function(buy)
					buy.quantity = "1"
				end,
				function(buy)
					buy.offerId = ""
				end,
				function(buy)
					buy.offerRevision = ""
				end,
				function(buy)
					buy.offerId = string.rep("x", 129)
				end,
				function(buy)
					buy.offerRevision = string.rep("x", 129)
				end,
			}
			for _, mutate in malformed do
				local f = fixture()
				local buy = request(0, "invalid")
				mutate(buy)
				local before = copy(f.data)
				expect(f.api.Buy(f.player, buy).code).toBe("InvalidRequest")
				expect(f.data).toEqual(before)
				expect(f.state.transactionCalls).toBe(0)
			end
		end
	)

	it(
		"does not overwrite owned, promised, or retained job identities when generating Featured gear",
		function()
			for _, id in
				{
					"starter_wooden_sword",
					"active_job",
					"promised_output",
					"",
					string.rep("x", 129),
				}
			do
				local f = fixture()
				f.data.craftingJobs = { active_job = job() }
				f.state.idOverride = id
				local before = gameplay(f.data)
				expect(f.api.Buy(f.player, request(0, "identity", 0, "Equipment")).code).toBe(
					"InstanceIdConflict"
				)
				expect(gameplay(f.data)).toEqual(before)
			end
			for _, status in { "Completed", "Cancelled" } do
				local f = fixture()
				local retained = job()
				retained.status = status :: "Completed" | "Cancelled"
				retained.reservations = { equipment = 0, materials = {} }
				f.data.craftingJobs = { old = retained }
				f.state.idOverride = "promised_output"
				expect(f.api.Buy(f.player, request(0, "retained-id", 0, "Equipment")).code).toBe(
					"InstanceIdConflict"
				)
			end
		end
	)

	it(
		"fails closed for absent profiles and view-clock failures without taking a transaction",
		function()
			local f = fixture()
			f.state.available = false
			expect(f.api.Get(f.player).code).toBe("DataUnavailable")
			expect(f.api.Buy(f.player, request(0, "unloaded")).code).toBe("DataUnavailable")
			expect(f.state.clockCalls).toBe(0)
			expect(f.state.transactionCalls).toBe(0)
			f.state.available = true
			for _, timestamp in { -1, math.huge, 0 / 0 } do
				f.state.viewNow = timestamp
				expect(f.api.Get(f.player).code).toBe("InvalidTimestamp")
			end
			f.state.clockThrows = true
			expect(f.api.Get(f.player).code).toBe("InvalidTimestamp")
			expect(f.state.transactionCalls).toBe(0)
		end
	)
end)

describe("ShopCommands retries and rollback", function()
	it("preserves every safe-integer digit in quoted period and quantity signatures", function()
		for _, field in { "periodId", "quantity" } do
			local f = fixture()
			local first: any = request(0, "exact-digits")
			first[field] = MAX_SAFE_INTEGER
			local rejected = f.api.Buy(f.player, first)
			expect(rejected.code).toBe(
				if field == "periodId" then "OfferExpired" else "InsufficientStock"
			)
			local changed = copy(first)
			changed[field] = MAX_SAFE_INTEGER - 1
			expect(f.api.Buy(f.player, changed).code).toBe("RequestConflict")
			expect(f.state.callbackCalls).toBe(1)
		end
	end)

	it("does not roll over old stock when a current-period purchase is rejected", function()
		local f = fixture()
		f.data.shop = { periodId = 0, purchased = { retained = 8 } }
		f.data.currency.gold = 9
		f.state.now = 3_600
		local before = gameplay(f.data)
		expect(f.api.Buy(f.player, request(0, "failed-refresh", 3_600)).code).toBe(
			"InsufficientGold"
		)
		expect(gameplay(f.data)).toEqual(before)
	end)

	it("rolls back generator failures and never reads the view clock during a purchase", function()
		local f = fixture()
		f.state.idThrows = true
		local before = copy(f.data)
		expect(f.api.Buy(f.player, request(0, "id-failure", 0, "Equipment")).code).toBe(
			"MutationFailed"
		)
		expect(f.data).toEqual(before)
		f.state.idThrows = false
		f.state.clockThrows = true
		expect(f.api.Buy(f.player, request(0, "clock-independent", 0, "Equipment")).ok).toBe(true)
		expect(f.state.clockCalls).toBe(0)
	end)

	it(
		"replays a serialized receipt after refresh without generating another ID or consuming stock",
		function()
			local f = fixture()
			local buy = request(0, "once", 0, "Equipment")
			local first = f.api.Buy(f.player, buy)
			expect(first.ok).toBe(true)
			local restored = fixture(copy(f.data))
			restored.state.now = 3_600
			local before = copy(restored.data)
			local replay = restored.api.Buy(restored.player, buy)
			expect(replay).toEqual({
				ok = true,
				revision = first.revision,
				values = first.values,
				replayed = true,
			})
			expect(restored.data).toEqual(before)
			expect(restored.state.callbackCalls).toBe(0)
			expect(restored.state.idCalls).toBe(0)
			local changed = copy(buy)
			changed.quantity = 2
			expect(restored.api.Buy(restored.player, changed).code).toBe("RequestConflict")
			expect(restored.api.Buy(restored.player, request(0, "stale", 3_600)).code).toBe(
				"StaleRevision"
			)
			expect(restored.data).toEqual(before)
		end
	)

	it(
		"binds every quoted field to the receipt and does not rerun an evicted old request",
		function()
			local f = fixture()
			local buy = request(0, "receipt")
			expect(f.api.Buy(f.player, buy).ok).toBe(true)
			for _, field in { "offerId", "offerRevision", "periodId", "quantity" } do
				local altered: any = copy(buy)
				altered[field] = if type(altered[field]) == "string"
					then altered[field] .. "x"
					else altered[field] + 1
				expect(f.api.Buy(f.player, altered).code).toBe("RequestConflict")
			end
			for revision = 1, PlayerData.maxRequestReceipts do
				local result = Transactions.Run(f.data, {
					id = `{revision}:advance`,
					expectedRevision = revision,
					operation = "Test",
					signature = "",
				}, function()
					return { ok = true }
				end, function()
					return true
				end)
				expect(result.ok).toBe(true)
			end
			local before = copy(f.data)
			expect(f.api.Buy(f.player, buy).code).toBe("StaleRevision")
			expect(f.data).toEqual(before)
		end
	)

	it(
		"rolls back delivery, Gold, stock, and receipts when the session ends after the callback",
		function()
			local f = fixture()
			f.state.loseSessionAfterCallback = true
			local before = copy(f.data)
			expect(f.api.Buy(f.player, request(0, "session", 0, "Equipment")).code).toBe(
				"DataUnavailable"
			)
			expect(f.data).toEqual(before)
			expect(f.state.idCalls).toBe(1)
		end
	)

	it(
		"composes due crafting and the purchase in one rollback boundary without equipping output",
		function()
			local f = fixture()
			f.data.craftingJobs = { active_job = job() }
			f.state.prepareJobs = true
			f.state.now = 60
			f.data.currency.gold = 9
			local before = gameplay(f.data)
			expect(f.api.Buy(f.player, request(0, "rejected-due")).code).toBe("InsufficientGold")
			expect(gameplay(f.data)).toEqual(before)
			f.data.currency.gold = 10
			local loadout = copy(f.data.combatLoadout)
			expect(f.api.Buy(f.player, request(1, "accepted-due")).ok).toBe(true)
			expect(f.data.equipment.promised_output).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
			expect(
				assert(f.data.craftingJobs, "[ShopCommands.spec] Expected jobs").active_job.status
			).toBe("Completed")
			expect(f.data.combatLoadout).toEqual(loadout)
			expect(f.data.currency.gold).toBe(0)
		end
	)

	it(
		"accepts maximum safe Gold without rounding a normal purchase or spending refund headroom",
		function()
			local f = fixture()
			f.data.currency.gold = MAX_SAFE_INTEGER
			expect(f.api.Buy(f.player, request(0, "safe-gold")).ok).toBe(true)
			expect(f.data.currency.gold).toBe(MAX_SAFE_INTEGER - 10)
			local guarded = fixture()
			guarded.data.currency.gold = MAX_SAFE_INTEGER
			guarded.data.craftingJobs = { active = job() }
			local before = gameplay(guarded.data)
			expect(guarded.api.Buy(guarded.player, request(0, "unsafe-reserve")).code).toBe(
				"ArithmeticOverflow"
			)
			expect(gameplay(guarded.data)).toEqual(before)
		end
	)
end)
