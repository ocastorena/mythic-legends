--!strict
-- ServerStorage/Tests/__tests__/CapacityUpgradePurchase.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local CapacityUpgradePurchase =
	require(ServerScriptService.Services.InventoryService.CapacityUpgradePurchase)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local CATEGORIES: { InventoryCapacity.Category } = { "materials", "mythlings", "equipment" }
local MATERIALS = {
	"fire_material",
	"water_material",
	"earth_material",
	"air_material",
	"light_material",
	"dark_material",
}

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
		return "capacity_station"
	end, 0)
	assert(
		prepared,
		`[CapacityUpgradePurchase.spec] Fixture preparation failed: {tostring(problem)}`
	)
	data.currency.gold = 960_000
	for _, materialId in MATERIALS do
		data.materials[materialId] = { total = 750 }
	end
	data.mythlings.worker = {
		typeId = "mythling_0002",
		variantId = "regular",
		claimedAt = 10,
		level = 40,
		xp = 100,
		pendingXp = 0.5,
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
			workerIdsBySlot = { ["1"] = "worker" },
		},
	}
	return data
end

local function upgrade(
	revision: number,
	token: string,
	category: InventoryCapacity.Category?,
	purchased: number?
): Types.UpgradeInventoryCapacityRequest
	local count = purchased or 0
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		category = category or "materials",
		expectedUpgradeCount = count,
		expectedGoldCost = if count == 0 then 20_000 else 300_000,
		expectedMaterialQuantity = if count == 0 then 50 else 200,
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
	local dataSource: CapacityUpgradePurchase.DataSource = {
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
		api = CapacityUpgradePurchase.new(dataSource),
	}
end

describe("CapacityUpgradePurchase", function()
	it("buys two independent +12-slot upgrades for each of the three categories", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local revision = 0
		for _, category in CATEGORIES do
			local initial = if category == "mythlings" then 24 else 12
			for purchased = 0, 1 do
				local others: { [string]: number } = {}
				for _, other in CATEGORIES do
					if other ~= category then
						others[other] = InventoryCapacity.GetUsage(data, other).limit
					end
				end
				local request = upgrade(revision, "all-categories", category, purchased)
				expect(f.api.Upgrade(f.first, request)).toEqual({
					ok = true,
					revision = revision + 1,
					values = {
						category = category,
						previousUpgradeCount = purchased,
						upgradeCount = purchased + 1,
						limit = initial + 12 * (purchased + 1),
						maxLimit = initial + 24,
						goldSpent = request.expectedGoldCost,
						materialsSpentPerType = request.expectedMaterialQuantity,
					},
				})
				revision += 1
				expect(InventoryCapacity.GetUsage(data, category).limit).toBe(
					initial + 12 * (purchased + 1)
				)
				for other, previous in others do
					expect(
						InventoryCapacity.GetUsage(data, other :: InventoryCapacity.Category).limit
					).toBe(previous)
				end
			end
		end
		expect(data.inventoryUpgrades).toEqual({ materials = 2, mythlings = 2, equipment = 2 })
		expect(data.currency.gold).toBe(0)
		expect(data.materials).toEqual({})
		expect(f.state.callbackCalls).toBe(6)
		for _, operation in f.state.operations do
			expect(operation).toBe("Inventory.UpgradeCapacity")
		end
	end)

	it(
		"treats missing purchased counts as zero while preserving unrelated saved upgrade fields",
		function()
			for _, missingTable in { true, false } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.inventoryUpgrades = if missingTable
					then nil
					else { future_category = 9, equipment = 1 }
				expect(f.api.Upgrade(f.first, upgrade(0, "missing-count", "mythlings")).ok).toBe(
					true
				)
				local counts = assert(
					data.inventoryUpgrades,
					"[CapacityUpgradePurchase.spec] Expected purchases"
				)
				expect(counts.mythlings).toBe(1)
				expect(counts.materials).toBeNil()
				if not missingTable then
					expect(counts.future_category).toBe(9)
					expect(counts.equipment).toBe(1)
				end
			end
		end
	)

	it(
		"does not use the Material capacity being purchased to fit its own recipe and reservations",
		function()
			for purchased, reserved in { [0] = 7_000, [1] = 19_000 } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.inventoryUpgrades = { materials = purchased }
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { water_material = reserved } },
					},
				}
				local before = gameplay(data)
				expect(
					f.api.Upgrade(f.first, upgrade(0, "cannot-borrow", "materials", purchased)).code
				).toBe("MaterialCapacityTooSmall")
				expect(gameplay(data)).toEqual(before)
				local jobs =
					assert(data.craftingJobs, "[CapacityUpgradePurchase.spec] Expected reservation")
				local reservations = assert(
					jobs.active.reservations,
					"[CapacityUpgradePurchase.spec] Expected refund"
				)
				reservations.materials.water_material -= 1_000
				local retained = copy(jobs)
				expect(
					f.api.Upgrade(f.first, upgrade(1, "fits-old-capacity", "materials", purchased)).ok
				).toBe(true)
				expect(data.craftingJobs).toEqual(retained)
				expect(InventoryCapacity.GetUsage(data, "materials").limit).toBe(
					if purchased == 0 then 24 else 36
				)
			end
		end
	)

	it(
		"checks other-category recipes against owned Material capacity instead of the selected category",
		function()
			for _, category in { "mythlings", "equipment" } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { water_material = 7_000 } },
					},
				}
				local before = gameplay(data)
				expect(
					f.api.Upgrade(
						f.first,
						upgrade(0, "material-cap", category :: InventoryCapacity.Category)
					).code
				).toBe("MaterialCapacityTooSmall")
				expect(gameplay(data)).toEqual(before)
				data.inventoryUpgrades = { materials = 1 }
				expect(
					f.api.Upgrade(
						f.first,
						upgrade(1, "room-owned", category :: InventoryCapacity.Category)
					).ok
				).toBe(true)
			end
		end
	)

	it(
		"requires all six real owned ingredients without substitutions or Shrine/refund payment",
		function()
			for index, materialId in MATERIALS do
				local f = fixture()
				local data = f.profiles[f.first]
				for _, id in MATERIALS do
					data.materials[id].total = 50
				end
				data.materials[materialId].total = 49
				data.materials[MATERIALS[index % #MATERIALS + 1]].total += 1
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { [materialId] = 100 } },
					},
				}
				local before = gameplay(data)
				expect(f.api.Upgrade(f.first, upgrade(0, "missing-ingredient")).code).toBe(
					"InsufficientMaterials"
				)
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it(
		"retains assigned Mythlings, equipped gear, protected starters, and output/refund reservations",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			for index = 2, 24 do
				data.mythlings[`worker_{index}`] =
					{ typeId = "retained_form", variantId = "old", claimedAt = 1, standId = 1 }
			end
			data.craftingJobs = {
				active = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 200 } },
				},
			}
			local owned, equipment, loadout, jobs, shrines =
				data.mythlings,
				data.equipment,
				data.combatLoadout,
				data.craftingJobs,
				data.base.shrines
			local before = gameplay(data)
			expect(InventoryCapacity.GetUsage(data, "mythlings")).toEqual({ used = 24, limit = 24 })
			expect(InventoryCapacity.GetUsage(data, "equipment")).toEqual({ used = 3, limit = 12 })
			expect(f.api.Upgrade(f.first, upgrade(0, "workers", "mythlings")).ok).toBe(true)
			expect(f.api.Upgrade(f.first, upgrade(1, "gear", "equipment")).ok).toBe(true)
			expect(InventoryCapacity.GetUsage(data, "mythlings")).toEqual({ used = 24, limit = 36 })
			expect(InventoryCapacity.GetUsage(data, "equipment")).toEqual({ used = 3, limit = 24 })
			expect(data.mythlings).toEqual(before.mythlings)
			expect(data.equipment).toEqual(before.equipment)
			expect(data.combatLoadout).toEqual(before.combatLoadout)
			expect(data.craftingJobs).toEqual(before.craftingJobs)
			expect(data.base.shrines).toEqual(before.base.shrines)
			expect(data.mythlings).toBe(owned)
			expect(data.equipment).toBe(equipment)
			expect(data.combatLoadout).toBe(loadout)
			expect(data.craftingJobs).toBe(jobs)
			expect(data.base.shrines).toBe(shrines)
		end
	)

	it(
		"allows retained over-capacity categories to buy room without deleting old holdings",
		function()
			for _, category in CATEGORIES do
				local f = fixture()
				local data = f.profiles[f.first]
				if category == "materials" then
					data.materials.retained_legacy = { total = 40_000 }
				elseif category == "mythlings" then
					for index = 1, 50 do
						data.mythlings[`retained_{index}`] =
							{ typeId = "old_form", variantId = "regular", claimedAt = 1 }
					end
				else
					for index = 1, 40 do
						data.equipment[`retained_{index}`] = { definitionId = "old_equipment" }
					end
				end
				local before = gameplay(data)
				expect(f.api.Upgrade(f.first, upgrade(0, "over-cap", category)).ok).toBe(true)
				expect(f.api.Upgrade(f.first, upgrade(1, "still-over-cap", category, 1)).ok).toBe(
					true
				)
				expect(data.mythlings).toEqual(before.mythlings)
				expect(data.equipment).toEqual(before.equipment)
				if category == "materials" then
					for _, materialId in MATERIALS do
						before.materials[materialId].total -= 250
					end
					expect(data.materials).toEqual(before.materials)
				end
			end
		end
	)

	it("rejects stale counts, skipped purchases, quotes, and completed category paths", function()
		for _, failure in { "count", "gold", "quantity", "maximum" } do
			local f = fixture()
			local data = f.profiles[f.first]
			local request = upgrade(0, "stale")
			local code = "PriceChanged"
			if failure == "count" then
				request.expectedUpgradeCount = 1
				code = "UpgradeCountChanged"
			elseif failure == "gold" then
				request.expectedGoldCost -= 1
			elseif failure == "quantity" then
				request.expectedMaterialQuantity -= 1
			else
				data.inventoryUpgrades = { materials = 2 }
				request = upgrade(0, "maximum", "materials", 2)
				code = "MaxCapacity"
			end
			local before = gameplay(data)
			expect(f.api.Upgrade(f.first, request).code).toBe(code)
			expect(gameplay(data)).toEqual(before)
		end
	end)

	it(
		"rejects malformed request fields and cannot purchase unknown or differently cased categories",
		function()
			local invalid: { any } = { false, setmetatable(upgrade(0, "meta"), {}) }
			for _, field in
				{
					"requestId",
					"expectedRevision",
					"category",
					"expectedUpgradeCount",
					"expectedGoldCost",
					"expectedMaterialQuantity",
				}
			do
				local request: any = upgrade(0, "missing")
				request[field] = nil
				table.insert(invalid, request)
			end
			for _, field in
				{ "limit", "player", "materialId", "materials", "gold", "signature", "operation" }
			do
				local request: any = upgrade(0, "extra")
				request[field] = 1
				table.insert(invalid, request)
			end
			for _, category in { "Materials", "consumables", "all", "", 1 } do
				local request: any = upgrade(0, "category")
				request.category = category
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
				for _, value in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53 } do
					local request: any = upgrade(0, "number")
					request[field] = value
					table.insert(invalid, request)
				end
			end
			for _, request in invalid do
				local f = fixture()
				local before = copy(f.profiles[f.first])
				expect(f.api.Upgrade(f.first, request).code).toBe("InvalidRequest")
				expect(f.profiles[f.first]).toEqual(before)
				expect(f.state.transactionCalls).toBe(0)
			end
		end
	)

	it(
		"fails closed for any malformed known purchased count, selected collection, or payment state",
		function()
			for _, failure in
				{
					"version",
					"counts",
					"other-count",
					"negative",
					"fractional",
					"past-cap",
					"owned",
					"record",
					"key",
					"gold",
					"poor",
					"material",
					"reservation",
				}
			do
				local f = fixture()
				local data = f.profiles[f.first]
				local raw = data :: any
				local code: string? = nil
				if failure == "version" then
					data.version = 3
					code = "UnsupportedVersion"
				elseif failure == "counts" then
					raw.inventoryUpgrades = false
					code = "InvalidInventoryUpgrade"
				elseif failure == "other-count" then
					data.inventoryUpgrades = { equipment = 3 }
					code = "InvalidInventoryUpgrade"
				elseif
					failure == "negative"
					or failure == "fractional"
					or failure == "past-cap"
				then
					data.inventoryUpgrades = {
						mythlings = if failure == "negative"
							then -1
							elseif failure == "fractional" then 0.5
							else 3,
					}
					code = "InvalidInventoryUpgrade"
				elseif failure == "owned" then
					raw.mythlings = false
					code = "InvalidInventoryState"
				elseif failure == "record" then
					raw.mythlings.worker = false
					code = "InvalidInventoryState"
				elseif failure == "key" then
					data.mythlings[""] = data.mythlings.worker
					code = "InvalidInventoryState"
				elseif failure == "gold" then
					data.currency.gold = -1
					code = "InvalidCurrency"
				elseif failure == "poor" then
					data.currency.gold = 19_999
					code = "InsufficientGold"
				elseif failure == "material" then
					data.materials.fire_material.total = -1
				else
					data.craftingJobs = {
						active = {
							status = "Active",
							reservations = { equipment = -1, materials = {} },
						},
					}
				end
				local before = gameplay(data)
				local result = f.api.Upgrade(f.first, upgrade(0, "invalid-state", "mythlings"))
				expect(result.ok).toBe(false)
				if code then
					expect(result.code).toBe(code)
				end
				expect(gameplay(data)).toEqual(before)
			end
		end
	)

	it("replays a completed purchase and binds category and all exact quote fields", function()
		local f = fixture()
		local request = upgrade(0, "binding")
		local result = f.api.Upgrade(f.first, request)
		expect(result.ok).toBe(true)
		local after = copy(f.profiles[f.first])
		expect(f.api.Upgrade(f.first, request)).toEqual({
			ok = true,
			revision = 1,
			values = result.values,
			replayed = true,
		})
		local changes: { [string]: any } = {
			category = "mythlings",
			expectedUpgradeCount = 1,
			expectedGoldCost = 20_001,
			expectedMaterialQuantity = 51,
		}
		for field, value in changes do
			local changed: any = upgrade(0, "binding")
			changed[field] = value
			expect(f.api.Upgrade(f.first, changed).code).toBe("RequestConflict")
		end
		expect(f.profiles[f.first]).toEqual(after)
		expect(f.state.callbackCalls).toBe(1)
		for _, field in { "expectedUpgradeCount", "expectedGoldCost", "expectedMaterialQuantity" } do
			local large = fixture()
			local selected: any = upgrade(0, "large")
			selected[field] = 2 ^ 52
			expect(large.api.Upgrade(large.first, selected).ok).toBe(false)
			selected[field] += 1
			expect(large.api.Upgrade(large.first, selected).code).toBe("RequestConflict")
			expect(large.state.callbackCalls).toBe(1)
		end
	end)

	it("retains failed receipts after later funding allows a new purchase", function()
		local f = fixture()
		local data = f.profiles[f.first]
		data.currency.gold = 19_999
		local request = upgrade(0, "poor")
		expect(f.api.Upgrade(f.first, request).code).toBe("InsufficientGold")
		data.currency.gold = 20_000
		expect(f.api.Upgrade(f.first, upgrade(1, "funded")).ok).toBe(true)
		local after = copy(data)
		expect(f.api.Upgrade(f.first, request)).toEqual({
			ok = false,
			code = "InsufficientGold",
			revision = 1,
			replayed = true,
		})
		expect(data).toEqual(after)
	end)

	it(
		"retains independent purchased maxima and receipts through reconnect-style serialization",
		function()
			local f = fixture()
			local first = upgrade(0, "before-save", "equipment")
			local result = f.api.Upgrade(f.first, first)
			expect(result.ok).toBe(true)
			local restored = fixture(copy(f.profiles[f.first]))
			expect(restored.api.Upgrade(restored.first, first)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.state.callbackCalls).toBe(0)
			expect(restored.api.Upgrade(restored.first, upgrade(1, "final", "equipment", 1)).ok).toBe(
				true
			)
			local data = restored.profiles[restored.first]
			local before = gameplay(data)
			expect(restored.api.Upgrade(restored.first, upgrade(2, "maximum", "equipment", 2)).code).toBe(
				"MaxCapacity"
			)
			expect(gameplay(data)).toEqual(before)
			expect(data.inventoryUpgrades).toEqual({ materials = 0, mythlings = 0, equipment = 2 })
			expect(InventoryCapacity.GetUsage(data, "equipment").limit).toBe(36)
		end
	)

	it("rejects unavailable profiles and stale revisions without running the purchase", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		f.state.available = false
		expect(f.api.Upgrade(f.first, upgrade(0, "unavailable")).code).toBe("DataUnavailable")
		expect(f.state.transactionCalls).toBe(0)
		f.state.available = true
		expect(f.api.Upgrade(f.first, upgrade(1, "stale")).code).toBe("StaleRevision")
		expect(f.state.callbackCalls).toBe(0)
		expect(f.profiles[f.first]).toEqual(before)
	end)

	it("rolls back Gold, six Material debits, new capacity, and receipt on session loss", function()
		local f = fixture()
		local before = copy(f.profiles[f.first])
		f.state.loseSessionAfterCallback = true
		expect(f.api.Upgrade(f.first, upgrade(0, "lost-session"))).toEqual({
			ok = false,
			code = "DataUnavailable",
			revision = 0,
		})
		expect(f.profiles[f.first]).toEqual(before)
	end)

	it("isolates the purchase to the requesting profile", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		local request = upgrade(0, "shared-token")
		expect(f.api.Upgrade(f.first, request).ok).toBe(true)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		local result = f.api.Upgrade(f.second, request)
		expect(result.ok).toBe(true)
		expect(result.replayed).toBeNil()
		expect(f.profiles[f.first]).toEqual(firstAfter)
	end)

	it(
		"retains live identities, legacy fields, shop data, and accounting without settling work",
		function()
			local f = fixture()
			local data = f.profiles[f.first]
			local raw = data :: any
			raw.shop = { periodId = "retained_period", purchased = { fire_material = 7 } }
			local worker = data.mythlings.worker :: any
			worker.luck = 77
			worker.traitIds = { "lucky", "insomniac" }
			local fire = data.materials.fire_material :: any
			fire.custom = { retained = true }
			local currency = data.currency :: any
			currency.legacyTokens = 17
			local before = gameplay(data)
			local upgrades, base, clock, materials, owned, equipment =
				data.inventoryUpgrades,
				data.base,
				data.productionClock,
				data.materials,
				data.mythlings,
				data.equipment
			expect(f.api.Upgrade(f.first, upgrade(0, "preserve", "mythlings")).ok).toBe(true)
			local expected = copy(before)
			local expectedUpgrades = assert(
				expected.inventoryUpgrades,
				"[CapacityUpgradePurchase.spec] Expected initial upgrades"
			)
			expectedUpgrades.mythlings = 1
			expected.currency.gold -= 20_000
			for _, materialId in MATERIALS do
				expected.materials[materialId].total -= 50
			end
			expect(gameplay(data)).toEqual(expected)
			expect(data.inventoryUpgrades).toBe(upgrades)
			expect(data.base).toBe(base)
			expect(data.productionClock).toBe(clock)
			expect(data.materials).toBe(materials)
			expect(data.materials.fire_material).toBe(fire)
			expect(data.currency).toBe(currency)
			expect(data.mythlings).toBe(owned)
			expect(data.mythlings.worker).toBe(worker)
			expect(data.equipment).toBe(equipment)
		end
	)
end)
