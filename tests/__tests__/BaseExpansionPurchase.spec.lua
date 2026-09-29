--!strict
-- ServerStorage/Tests/__tests__/BaseExpansionPurchase.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseExpansionPurchase =
	require(ServerScriptService.Services.BaseService.BaseExpansionPurchase)
local BaseState = require(ServerScriptService.Shared.BaseState)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local MATERIALS = {
	"fire_material",
	"water_material",
	"earth_material",
	"air_material",
	"light_material",
	"dark_material",
}
local GOLD_COSTS = { 10_000, 50_000, 150_000, 500_000 }
local MATERIAL_COSTS = { 50, 100, 150, 200 }

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
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return "expansion_station"
	end, 0)
	assert(prepared, `[BaseExpansionPurchase.spec] Fixture preparation failed: {tostring(problem)}`)
	data.currency.gold = 710_000
	for _, materialId in MATERIALS do
		data.materials[materialId] = { total = 500 }
	end
	data.mythlings = {
		first = {
			typeId = "mythling_0001",
			variantId = "regular",
			claimedAt = 10,
			level = 6,
			xp = 100,
			pendingXp = 0.5,
		},
		second = {
			typeId = "mythling_0002",
			variantId = "regular",
			claimedAt = 20,
			level = 40,
			xp = 25,
			pendingXp = 0.25,
		},
	}
	data.base.shrines = {
		first = {
			id = "first",
			shrineId = "fire_shrine",
			buildSlotId = 1,
			level = 1,
			stored = 100,
			progress = 0.5,
			newWork = 0.01,
			workerIdsBySlot = { ["1"] = "first" },
		},
		second = {
			id = "second",
			shrineId = "fire_shrine",
			buildSlotId = 2,
			level = 1,
			stored = 200,
			progress = 0.25,
			newWork = 0.02,
			workerIdsBySlot = { ["1"] = "second" },
		},
	}
	return data
end

local function expand(revision: number, token: string, purchased: number?): Types.ExpandBaseRequest
	local count = purchased or 0
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		expectedUpgradeCount = count,
		expectedGoldCost = GOLD_COSTS[count + 1] or 500_000,
		expectedMaterialQuantity = MATERIAL_COSTS[count + 1] or 200,
	}
end

local function fixture(firstProfile: Types.PlayerDoc?)
	local first = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local second = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
	local profiles: { [Player]: Types.PlayerDoc } =
		{ [first] = firstProfile or profile(), [second] = profile() }
	local state = {
		active = true,
		available = true,
		loseSessionAfterCallback = false,
		transactionCalls = 0,
		callbackCalls = 0,
		operations = {} :: { string },
	}
	local dataSource: BaseExpansionPurchase.DataSource = {
		GetLoadedData = function(player: Player): Types.PlayerDoc?
			return if state.active and state.available then profiles[player] else nil
		end,
		Transact = function(player, request, mutate)
			state.transactionCalls += 1
			table.insert(state.operations, request.operation)
			local data = profiles[player]
			if not data or not state.available then
				return { ok = false, code = "DataUnavailable", revision = 0 }
			end
			return Transactions.Run(data, request, function(draft)
				state.callbackCalls += 1
				local result = mutate(draft, 0)
				if state.loseSessionAfterCallback then
					state.active = false
				end
				return result
			end, function()
				return state.active
			end)
		end,
	}
	return {
		first = first,
		second = second,
		profiles = profiles,
		state = state,
		api = BaseExpansionPurchase.new(dataSource),
	}
end

describe("BaseExpansionPurchase", function()
	it(
		"purchases exactly four sequential permanent slots using all six configured ingredients",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			for count = 0, 3 do
				expect(f.api.Expand(f.first, expand(count, "sequential", count))).toEqual({
					ok = true,
					revision = count + 1,
					values = {
						previousUpgradeCount = count,
						upgradeCount = count + 1,
						unlockedShrineSlots = count + 3,
						maxShrineSlots = 6,
						goldSpent = GOLD_COSTS[count + 1],
						materialsSpentPerType = MATERIAL_COSTS[count + 1],
					},
				})
				expect(data.base.buildSlotUpgrades).toBe(count + 1)
				local status = assert(
					BaseState.GetStatus(data.base),
					"[BaseExpansionPurchase.spec] Expected Base"
				)
				expect(status.unlockedShrineSlots).toBe(count + 3)
				expect(status.usedShrineSlots).toBe(2)
			end
			expect(data.currency.gold).toBe(0)
			expect(data.materials).toEqual({})
			expect(f.state.operations).toEqual({
				"Base.Expand",
				"Base.Expand",
				"Base.Expand",
				"Base.Expand",
			})
			local before = gameplay(data)
			expect(f.api.Expand(f.first, expand(4, "maximum", 4)).code).toBe("MaxBaseSlots")
			expect(gameplay(data)).toEqual(before)
		end
	)

	it(
		"allows expansion with duplicate-element Shrines or no Shrine and excludes the permanent Station",
		function()
			for _, empty in { false, true } do
				local f = fixture()
				local data = f.profiles[f.first]
				if empty then
					data.base.shrines = {}
				end
				local station = data.base.craftingStation
				local before = copy(data.base.shrines)
				expect(f.api.Expand(f.first, expand(0, "layout")).ok).toBe(true)
				expect(data.base.shrines).toEqual(before)
				expect(data.base.craftingStation).toBe(station)
				local status = assert(
					BaseState.GetStatus(data.base),
					"[BaseExpansionPurchase.spec] Expected Base"
				)
				expect(status.usedShrineSlots).toBe(if empty then 0 else 2)
				expect(status.unlockedShrineSlots).toBe(3)
				local slot = BaseState.GetLowestFreeShrineSlot(data.base)
				expect(slot).toBe(if empty then 1 else 3)
			end
		end
	)

	it("rejects skipped or stale upgrade counts and either stale price field", function()
		for _, failure in { "skip", "old", "gold", "materials" } do
			local f = fixture()
			local data = f.profiles[f.first]
			local request = expand(0, "stale")
			local code = "PriceChanged"
			if failure == "skip" then
				request.expectedUpgradeCount = 1
				code = "UpgradeCountChanged"
			elseif failure == "old" then
				data.base.buildSlotUpgrades = 1
				code = "UpgradeCountChanged"
			elseif failure == "gold" then
				request.expectedGoldCost -= 1
			else
				request.expectedMaterialQuantity -= 1
			end
			local before = gameplay(data)
			expect(f.api.Expand(f.first, request).code).toBe(code)
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it("requires every exact elemental ingredient and never substitutes an equal total", function()
		for index, missing in MATERIALS do
			local f = fixture()
			local data = f.profiles[f.first]
			for _, materialId in MATERIALS do
				data.materials[materialId].total = 50
			end
			data.materials[missing] = nil
			local substitute = MATERIALS[index % #MATERIALS + 1]
			data.materials[substitute].total += 50
			local before = gameplay(data)
			expect(f.api.Expand(f.first, expand(0, "missing-element")).code).toBe(
				"InsufficientMaterials"
			)
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it("does not spend stored Shrine output or crafting refund reservations", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.materials.fire_material.total = 49
		data.craftingJobs = {
			active = {
				status = "Active",
				reservations = { equipment = 1, materials = { fire_material = 500 } },
			},
		}
		local before = gameplay(data)
		expect(f.api.Expand(f.first, expand(0, "unowned-materials")).code).toBe(
			"InsufficientMaterials"
		)
		expect(gameplay(data)).toEqual(before)
	end)

	it(
		"preserves active refund reservations when spending owned quantities of the same Material",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.craftingJobs = {
				active = {
					status = "Active",
					reservations = {
						equipment = 1,
						materials = { fire_material = 500, water_material = 250 },
					},
				},
				completed = {
					status = "Completed",
					reservations = { equipment = 1, materials = { fire_material = 10_000 } },
				},
			}
			local jobs = data.craftingJobs
			local before = copy(jobs)
			expect(f.api.Expand(f.first, expand(0, "reserved")).ok).toBe(true)
			expect(data.materials.fire_material.total).toBe(450)
			expect(data.materials.water_material.total).toBe(450)
			expect(data.craftingJobs).toBe(jobs)
			expect(data.craftingJobs).toEqual(before)
		end
	)

	it(
		"fits every recipe in six pre-purchase Material slots without requiring Inventory upgrades",
		function()
			for count = 0, 3 do
				local f = fixture()
				local data = f.profiles[f.first]
				data.base.buildSlotUpgrades = count
				for _, materialId in MATERIALS do
					data.materials[materialId].total = MATERIAL_COSTS[count + 1]
				end
				expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({
					used = 6,
					limit = 12,
				})
				expect(f.api.Expand(f.first, expand(0, "recipe-fits", count)).ok).toBe(true)
				expect(data.inventoryUpgrades).toEqual({
					materials = 0,
					mythlings = 0,
					equipment = 0,
				})
				expect(data.materials).toEqual({})
			end
		end
	)

	it(
		"checks the recipe against existing Material capacity including immutable refund reservations",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.craftingJobs = {
				active = {
					status = "Active",
					reservations = { equipment = 1, materials = { water_material = 7_000 } },
				},
			}
			local before = gameplay(data)
			expect(f.api.Expand(f.first, expand(0, "reserved-capacity")).code).toBe(
				"MaterialCapacityTooSmall"
			)
			expect(gameplay(data)).toEqual(before)
			data.inventoryUpgrades = { materials = 1, mythlings = 0, equipment = 0 }
			expect(f.api.Expand(f.first, expand(1, "capacity-owned")).ok).toBe(true)
			expect(data.craftingJobs).toEqual(before.craftingJobs)
		end
	)

	it(
		"rejects insufficient Gold or malformed payment state without changing any purchase inputs",
		function()
			for _, failure in
				{
					"poor",
					"currency",
					"material",
					"reservation",
					"base",
					"upgrade",
					"station",
					"version",
				}
			do
				local f = fixture()
				local data = f.profiles[f.first]
				if failure == "poor" then
					data.currency.gold = 9_999
				elseif failure == "currency" then
					data.currency.gold = -1
				elseif failure == "material" then
					data.materials.fire_material.total = -1
				elseif failure == "reservation" then
					data.craftingJobs = {
						active = {
							status = "Active",
							reservations = { equipment = 1, materials = { fire_material = -1 } },
						},
					}
				elseif failure == "base" then
					data.base.buildSlotUpgrades = -1
				elseif failure == "upgrade" then
					data.inventoryUpgrades = { materials = -1 }
				elseif failure == "version" then
					data.version = 3
				else
					data.base.craftingStation = nil
				end
				local before = gameplay(data)
				local result = f.api.Expand(f.first, expand(0, "bad-payment"))
				expect(result.ok).toBe(false)
				if failure == "poor" then
					expect(result.code).toBe("InsufficientGold")
				elseif failure == "currency" then
					expect(result.code).toBe("InvalidCurrency")
				elseif failure == "version" then
					expect(result.code).toBe("UnsupportedVersion")
				end
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"can spend a fitting recipe while retaining unrelated legacy over-capacity holdings",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.retained_legacy = { total = 13_000 }
			expect(InventoryCapacity.GetUsage(data, "materials")).toEqual({ used = 19, limit = 12 })
			expect(f.api.Expand(f.first, expand(0, "retained-overflow")).ok).toBe(true)
			expect(data.materials.retained_legacy.total).toBe(13_000)
			expect(data.base.buildSlotUpgrades).toBe(1)
			for _, materialId in MATERIALS do
				expect(data.materials[materialId].total).toBe(450)
			end
		end
	)

	it("rejects malformed request envelopes before entering a transaction", function()
		local invalid: { any } = { false, "purchase", setmetatable(expand(0, "meta"), {}) }
		for _, field in
			{
				"requestId",
				"expectedRevision",
				"expectedUpgradeCount",
				"expectedGoldCost",
				"expectedMaterialQuantity",
			}
		do
			local request: any = expand(0, "missing")
			request[field] = nil
			table.insert(invalid, request)
		end
		for _, field in
			{
				"player",
				"gold",
				"materials",
				"materialId",
				"upgradeCount",
				"unlockedShrineSlots",
				"signature",
				"operation",
			}
		do
			local request: any = expand(0, "extra")
			request[field] = 1
			table.insert(invalid, request)
		end
		for _, field in
			{
				"expectedRevision",
				"expectedUpgradeCount",
				"expectedGoldCost",
				"expectedMaterialQuantity",
			}
		do
			for _, value in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53, "1" } do
				local request: any = expand(0, "number")
				request[field] = value
				table.insert(invalid, request)
			end
		end
		for _, request in invalid do
			local f = fixture()
			local before = copy(f.profiles[f.first])
			expect(f.api.Expand(f.first, request).code).toBe("InvalidRequest")
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.transactionCalls).toBe(0)
		end
	end)

	it("replays the original purchase without charging or unlocking another slot", function()
		local f = fixture()
		local request = expand(0, "retry")
		local result = f.api.Expand(f.first, request)
		expect(result.ok).toBe(true)
		local after = copy(f.profiles[f.first])
		expect(f.api.Expand(f.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.callbackCalls).toBe(1)
	end)

	it("binds all quote fields exactly, including adjacent large safe integers", function()
		local f = fixture()
		expect(f.api.Expand(f.first, expand(0, "binding")).ok).toBe(true)
		local after = copy(f.profiles[f.first])
		for _, field in { "expectedUpgradeCount", "expectedGoldCost", "expectedMaterialQuantity" } do
			local changed: any = expand(0, "binding")
			changed[field] += 1
			expect(f.api.Expand(f.first, changed).code).toBe("RequestConflict")
			local large = fixture()
			local request: any = expand(0, "large")
			request[field] = 2 ^ 52
			expect(large.api.Expand(large.first, request).ok).toBe(false)
			request[field] += 1
			expect(large.api.Expand(large.first, request).code).toBe("RequestConflict")
			expect(large.state.callbackCalls).toBe(1)
		end
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.callbackCalls).toBe(1)
	end)

	it(
		"retains a rejected quote receipt after sufficient funds make a later purchase valid",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.currency.gold = 9_999
			local request = expand(0, "poor")
			expect(f.api.Expand(f.first, request).code).toBe("InsufficientGold")
			data.currency.gold = 10_000
			expect(f.api.Expand(f.first, expand(1, "funded")).ok).toBe(true)
			local after = copy(data)
			expect(f.api.Expand(f.first, request)).toEqual({
				ok = false,
				code = "InsufficientGold",
				revision = 1,
				replayed = true,
			})
			expect(data).toEqual(after)
		end
	)

	it(
		"preserves purchased slots and receipts through JSON continuation and Shrine removal",
		function()
			local f = fixture()
			local request = expand(0, "before-save")
			local result = f.api.Expand(f.first, request)
			local saved = copy(f.profiles[f.first])
			-- A persisted layout may be empty; permanent slot purchases do not follow occupancy.
			saved.base.shrines = {}
			local restored = fixture(saved)
			expect(restored.api.Expand(restored.first, request)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.state.callbackCalls).toBe(0)
			expect(restored.api.Expand(restored.first, expand(1, "next", 1)).ok).toBe(true)
			local data = restored.profiles[restored.first]
			expect(data.base.buildSlotUpgrades).toBe(2)
			local status = assert(
				BaseState.GetStatus(data.base),
				"[BaseExpansionPurchase.spec] Expected restored Base"
			)
			expect(status.unlockedShrineSlots).toBe(4)
			expect(status.usedShrineSlots).toBe(0)
			expect(data.currency.gold).toBe(650_000)
			for _, materialId in MATERIALS do
				expect(data.materials[materialId].total).toBe(350)
			end
		end
	)

	it("rejects unavailable profiles and stale revisions without trying the purchase", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		f.state.available = false
		expect(f.api.Expand(f.first, expand(0, "unavailable")).code).toBe("DataUnavailable")
		expect(f.state.transactionCalls).toBe(0)
		f.state.available = true
		expect(f.api.Expand(f.first, expand(1, "stale")).code).toBe("StaleRevision")
		expect(f.state.callbackCalls).toBe(0)
		expect(f.profiles[f.first]).toEqual(before)
	end)

	it(
		"rolls back Gold, all six debits, purchased capacity, and receipt on session loss",
		function()
			local f = fixture()
			local before = copy(f.profiles[f.first])
			f.state.loseSessionAfterCallback = true
			expect(f.api.Expand(f.first, expand(0, "lost-session"))).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.profiles[f.first]).toEqual(before)
		end
	)

	it("isolates the request to the authenticated profile", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		local request = expand(0, "shared-token")
		expect(f.api.Expand(f.first, request).ok).toBe(true)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		local result = f.api.Expand(f.second, request)
		expect(result.ok).toBe(true)
		expect(result.replayed).toBeNil()
		expect(f.profiles[f.first]).toEqual(firstAfter)
	end)

	it(
		"preserves live identities and all existing accounting without settling production",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.legacy_material = { total = 11 }
			local fire = data.materials.fire_material :: any
			fire.custom = { retained = true }
			local currency = data.currency :: any
			currency.legacyTokens = 17
			local firstWorker = data.mythlings.first :: any
			firstWorker.luck = 77
			firstWorker.traitIds = { "lucky", "insomniac" }
			local before = gameplay(data)
			local base, shrines, station, workers, clock, materials =
				data.base,
				data.base.shrines,
				data.base.craftingStation,
				data.mythlings,
				data.productionClock,
				data.materials
			expect(f.api.Expand(f.first, expand(0, "preserve")).ok).toBe(true)
			local expected = copy(before)
			expected.base.buildSlotUpgrades = 1
			expected.currency.gold -= 10_000
			for _, materialId in MATERIALS do
				expected.materials[materialId].total -= 50
			end
			expect(gameplay(data)).toEqual(expected)
			expect(data.base).toBe(base)
			expect(data.base.shrines).toBe(shrines)
			expect(data.base.craftingStation).toBe(station)
			expect(data.mythlings).toBe(workers)
			expect(data.mythlings.first).toBe(firstWorker)
			expect(data.productionClock).toBe(clock)
			expect(data.materials).toBe(materials)
			expect(data.materials.fire_material).toBe(fire)
			expect(data.currency).toBe(currency)
		end
	)
end)
