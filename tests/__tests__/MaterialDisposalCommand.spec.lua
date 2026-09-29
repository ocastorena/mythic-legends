--!strict
-- ServerStorage/Tests/__tests__/MaterialDisposalCommand.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local MaterialDisposalCommand =
	require(ServerScriptService.Services.InventoryService.MaterialDisposalCommand)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local MAX_SAFE_INTEGER = 2 ^ 53 - 1
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
		return "disposal_station"
	end, 0)
	assert(
		prepared,
		`[MaterialDisposalCommand.spec] Fixture preparation failed: {tostring(problem)}`
	)
	for _, materialId in MATERIALS do
		data.materials[materialId] = { total = 100 }
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

-- These deliberately untrusted payloads also exercise missing/forged fields below.
local function selection(
	selling: boolean,
	revision: number,
	token: string,
	quantity: number?,
	owned: number?,
	materialId: string?
): any
	local request: any = {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		materialId = materialId or "fire_material",
		quantity = quantity or 25,
		expectedOwnedQuantity = owned or 100,
	}
	if selling then
		request.expectedUnitGold = 2
	end
	return request
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
	local dataSource: MaterialDisposalCommand.DataSource = {
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
				local result = mutate(draft)
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
		api = MaterialDisposalCommand.new(dataSource),
	}
end

describe("MaterialDisposalCommand", function()
	it("sells partial and final quantities of all six normal Materials at two Gold each", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local revision = 0
		local gold = data.currency.gold
		for _, materialId in MATERIALS do
			local original = data.materials[materialId]
			for _, amount in { 25, 75 } do
				local owned = if amount == 25 then 100 else 75
				gold += amount * 2
				expect(
					f.api.Sell(
						f.first,
						selection(true, revision, "six-sales", amount, owned, materialId)
					)
				).toEqual({
					ok = true,
					revision = revision + 1,
					values = {
						materialId = materialId,
						quantity = amount,
						remainingQuantity = owned - amount,
						goldGranted = amount * 2,
						unitGold = 2,
						goldBalance = gold,
					},
				})
				revision += 1
				if amount == 25 then
					expect(data.materials[materialId]).toBe(original)
					expect(original.total).toBe(75)
				else
					expect(data.materials[materialId]).toBeNil()
				end
				expect(data.currency.gold).toBe(gold)
			end
		end
		expect(data.materials).toEqual({})
		for _, operation in f.state.operations do
			expect(operation).toBe("Inventory.SellMaterial")
		end
	end)

	it("discards partial and final quantities of all six normal Materials without Gold", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local revision = 0
		local gold = data.currency.gold
		for _, materialId in MATERIALS do
			for _, amount in { 25, 75 } do
				local owned = if amount == 25 then 100 else 75
				expect(
					f.api.Discard(
						f.first,
						selection(false, revision, "six-discards", amount, owned, materialId)
					)
				).toEqual({
					ok = true,
					revision = revision + 1,
					values = {
						materialId = materialId,
						quantity = amount,
						remainingQuantity = owned - amount,
						goldGranted = 0,
					},
				})
				revision += 1
				expect(data.currency.gold).toBe(gold)
			end
			expect(data.materials[materialId]).toBeNil()
		end
		expect(data.materials).toEqual({})
		for _, operation in f.state.operations do
			expect(operation).toBe("Inventory.DiscardMaterial")
		end
	end)

	it(
		"rejects unknown and inactive legacy definitions without reinterpreting retained ownership",
		function()
			for _, selling in { true, false } do
				for _, materialId in
					{ "unknown", "Fire_material", "essence", "crystal", "shadow_dust" }
				do
					local f = fixture()
					local data = f.profiles[f.first]
					data.materials[materialId] = { total = 100 }
					local before = gameplay(data)
					local execute = if selling then f.api.Sell else f.api.Discard
					expect(
						execute(f.first, selection(selling, 0, "disabled", 25, 100, materialId)).code
					).toBe("InvalidMaterial")
					expect(gameplay(data)).toEqual(before)
				end
			end
		end
	)

	it(
		"requires the exact current owned quantity and never silently adjusts the selected amount",
		function()
			for _, selling in { true, false } do
				for _, case in
					{
						{ quantity = 25, expected = 99, actual = 100, code = "QuantityChanged" },
						{ quantity = 25, expected = 101, actual = 100, code = "QuantityChanged" },
						{
							quantity = 101,
							expected = 100,
							actual = 100,
							code = "InsufficientMaterials",
						},
						{ quantity = 1, expected = 0, actual = 0, code = "NotOwned" },
						{ quantity = 1, expected = 100, actual = 0, code = "QuantityChanged" },
					}
				do
					for _, removeEmpty in { true, false } do
						local f = fixture()
						local data = f.profiles[f.first]
						data.materials.fire_material = if case.actual == 0 and removeEmpty
							then nil
							else { total = case.actual }
						local before = gameplay(data)
						local execute = if selling then f.api.Sell else f.api.Discard
						expect(
							execute(
								f.first,
								selection(selling, 0, "owned", case.quantity, case.expected)
							).code
						).toBe(case.code)
						expect(gameplay(data)).toEqual(before)
					end
				end
			end
		end
	)

	it("rejects a stale unit quote instead of paying the client-supplied price", function()
		for _, unitGold in { 1, 3, MAX_SAFE_INTEGER } do
			local f = fixture()
			local before = gameplay(f.profiles[f.first])
			local request = selection(true, 0, "quote")
			request.expectedUnitGold = unitGold
			expect(f.api.Sell(f.first, request).code).toBe("PriceChanged")
			expect(gameplay(f.profiles[f.first])).toEqual(before)
		end
	end)

	it(
		"can drain full or retained over-capacity Inventory while retaining refund reservations",
		function()
			for _, selling in { true, false } do
				for _, legacyQuantity in { 6_000, 20_000 } do
					local f = fixture()
					local data = f.profiles[f.first]
					data.materials.retained_legacy = { total = legacyQuantity }
					data.craftingJobs = {
						active = {
							status = "Active",
							reservations = { equipment = 1, materials = { fire_material = 100 } },
						},
					}
					local jobs = copy(data.craftingJobs)
					local usage = InventoryCapacity.GetUsage(data, "materials")
					expect(usage.used >= usage.limit).toBe(true)
					local execute = if selling then f.api.Sell else f.api.Discard
					expect(execute(f.first, selection(selling, 0, "drain", 100)).ok).toBe(true)
					expect(data.materials.fire_material).toBeNil()
					expect(data.materials.retained_legacy.total).toBe(legacyQuantity)
					expect(data.craftingJobs).toEqual(jobs)
					-- Removing owned Fire leaves its reserved refund occupying the same slot.
					expect(InventoryCapacity.GetUsage(data, "materials").used).toBe(usage.used)
				end
			end
		end
	)

	it("cannot sell or discard Shrine output and reserved refunds as owned Materials", function()
		for _, selling in { true, false } do
			for _, owned in { 0, 1 } do
				local f = fixture()
				local data = f.profiles[f.first]
				data.materials.fire_material = { total = owned }
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { fire_material = 100 } },
					},
				}
				local before = gameplay(data)
				local execute = if selling then f.api.Sell else f.api.Discard
				expect(execute(f.first, selection(selling, 0, "not-collected", 2, owned)).code).toBe(
					if owned == 0 then "NotOwned" else "InsufficientMaterials"
				)
				expect(gameplay(data)).toEqual(before)
			end
		end
	end)

	it(
		"retains unrelated state and live table identities without collecting or settling production",
		function()
			for _, selling in { true, false } do
				local f = fixture()
				local data = f.profiles[f.first]
				local raw = data :: any
				raw.shop = { periodId = "retained", purchased = { fire_material = 7 } }
				raw.currency.legacyTokens = 17
				raw.materials.fire_material.legacy = { kept = true }
				raw.mythlings.worker.luck = 77
				raw.mythlings.worker.traitIds = { "lucky", "insomniac" }
				data.materials.essence = { total = 33 }
				data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 1 }
				data.craftingJobs = {
					active = {
						status = "Active",
						reservations = { equipment = 1, materials = { fire_material = 75 } },
					},
					completed = {
						status = "Completed",
						reservations = { equipment = 1, materials = { water_material = 15 } },
					},
				}
				local before = gameplay(data)
				local materials, fire, currency, base, clock, workers, jobs, upgrades, equipment =
					data.materials,
					data.materials.fire_material,
					data.currency,
					data.base,
					data.productionClock,
					data.mythlings,
					data.craftingJobs,
					data.inventoryUpgrades,
					data.equipment
				local execute = if selling then f.api.Sell else f.api.Discard
				expect(execute(f.first, selection(selling, 0, "preserved")).ok).toBe(true)
				before.materials.fire_material.total -= 25
				if selling then
					before.currency.gold += 50
				end
				expect(gameplay(data)).toEqual(before)
				expect(data.materials).toBe(materials)
				expect(data.materials.fire_material).toBe(fire)
				expect(data.currency).toBe(currency)
				expect(data.base).toBe(base)
				expect(data.productionClock).toBe(clock)
				expect(data.mythlings).toBe(workers)
				expect(data.craftingJobs).toBe(jobs)
				expect(data.inventoryUpgrades).toBe(upgrades)
				expect(data.equipment).toBe(equipment)
			end
		end
	)

	it("keeps discard independent of an invalid but serializable Gold balance", function()
		for _, gold in { -1, 0.5, "retained-invalid" } do
			local f = fixture()
			local data = f.profiles[f.first]
			local raw = data :: any
			raw.currency.gold = gold
			local before = gameplay(data)
			expect(f.api.Sell(f.first, selection(true, 0, "invalid-gold")).code).toBe(
				"InvalidCurrency"
			)
			expect(gameplay(data)).toEqual(before)
			expect(f.api.Discard(f.first, selection(false, 1, "independent-discard")).ok).toBe(true)
			before.materials.fire_material.total -= 25
			expect(gameplay(data)).toEqual(before)
			expect(raw.currency.gold).toBe(gold)
		end
	end)

	it("rejects unsafe multiplication and Gold addition without rounding up a payout", function()
		for _, case in
			{
				{ quantity = 1, gold = MAX_SAFE_INTEGER - 2, ok = true },
				{ quantity = 1, gold = MAX_SAFE_INTEGER - 1, ok = false },
				{ quantity = 2 ^ 52 - 1, gold = 1, ok = true },
				{ quantity = 2 ^ 52 - 1, gold = 2, ok = false },
				{ quantity = 2 ^ 52, gold = 0, ok = false },
			}
		do
			local f = fixture()
			local data = f.profiles[f.first]
			data.materials.fire_material.total = case.quantity
			data.currency.gold = case.gold
			local before = gameplay(data)
			local result = f.api.Sell(
				f.first,
				selection(true, 0, "safe-arithmetic", case.quantity, case.quantity)
			)
			expect(result.ok).toBe(case.ok)
			if case.ok then
				expect(data.currency.gold).toBe(MAX_SAFE_INTEGER)
				expect(data.materials.fire_material).toBeNil()
			else
				expect(result.code).toBe("ArithmeticOverflow")
				expect(gameplay(data)).toEqual(before)
			end
		end
	end)

	it("rejects malformed and forged request fields before admitting any transaction", function()
		for _, selling in { true, false } do
			local invalid: { any } = { false, setmetatable(selection(selling, 0, "meta"), {}) }
			local fields = {
				"requestId",
				"expectedRevision",
				"materialId",
				"quantity",
				"expectedOwnedQuantity",
			}
			if selling then
				table.insert(fields, "expectedUnitGold")
			end
			for _, field in fields do
				local request = selection(selling, 0, "missing")
				request[field] = nil
				table.insert(invalid, request)
			end
			for _, field in
				{
					"player",
					"gold",
					"goldGranted",
					"remainingQuantity",
					"materials",
					"operation",
					"signature",
					"unitGold",
				}
			do
				local request = selection(selling, 0, "forgery")
				request[field] = 100
				table.insert(invalid, request)
			end
			if not selling then
				local request = selection(false, 0, "sale-field")
				request.expectedUnitGold = 2
				table.insert(invalid, request)
			end
			for _, field in { "requestId", "materialId" } do
				for _, value in { "", string.rep("x", 129), 1, {} } do
					local request = selection(selling, 0, "id")
					request[field] = value
					table.insert(invalid, request)
				end
			end
			local numericFields = { "expectedRevision", "quantity", "expectedOwnedQuantity" }
			if selling then
				table.insert(numericFields, "expectedUnitGold")
			end
			for _, field in numericFields do
				for _, value in { -1, 0.5, math.huge, 0 / 0, 2 ^ 53, "25" } do
					local request = selection(selling, 0, "number")
					request[field] = value
					table.insert(invalid, request)
				end
			end
			for _, field in if selling then { "quantity", "expectedUnitGold" } else { "quantity" } do
				local request = selection(selling, 0, "zero")
				request[field] = 0
				table.insert(invalid, request)
			end
			for _, request in invalid do
				local f = fixture()
				local before = copy(f.profiles[f.first])
				local execute = if selling then f.api.Sell else f.api.Discard
				expect(execute(f.first, request).code).toBe("InvalidRequest")
				expect(f.state.transactionCalls).toBe(0)
				expect(f.profiles[f.first]).toEqual(before)
			end
		end
	end)

	it("fails closed on unsupported schemas and malformed Material or reservation state", function()
		for _, selling in { true, false } do
			for _, failure in
				{ "version", "materials", "entry", "total", "key", "upgrades", "reservations" }
			do
				local f = fixture()
				local data = f.profiles[f.first]
				local raw = data :: any
				local code = "InvalidInventoryState"
				if failure == "version" then
					data.version = 3
					code = "UnsupportedVersion"
				elseif failure == "materials" then
					raw.materials = false
				elseif failure == "entry" then
					raw.materials.water_material = false
				elseif failure == "total" then
					data.materials.water_material.total = -1
				elseif failure == "key" then
					data.materials[""] = { total = 1 }
				elseif failure == "upgrades" then
					data.inventoryUpgrades = { materials = 3 }
					code = "InvalidInventoryUpgrade"
				else
					data.craftingJobs = {
						active = {
							status = "Active",
							reservations = { equipment = 1, materials = { water_material = -1 } },
						},
					}
					code = "InvalidReservations"
				end
				local before = gameplay(data)
				local execute = if selling then f.api.Sell else f.api.Discard
				expect(execute(f.first, selection(selling, 0, "invalid-state")).code).toBe(code)
				expect(gameplay(data)).toEqual(before)
			end
		end
	end)

	it(
		"replays once and binds the operation, Material, quantity, owned snapshot, and sale quote",
		function()
			for _, selling in { true, false } do
				local f = fixture()
				local execute = if selling then f.api.Sell else f.api.Discard
				local request = selection(selling, 0, "binding")
				local result = execute(f.first, request)
				expect(result.ok).toBe(true)
				local after = copy(f.profiles[f.first])
				expect(execute(f.first, request)).toEqual({
					ok = true,
					revision = 1,
					values = result.values,
					replayed = true,
				})
				local changes = {
					materialId = "water_material",
					quantity = 26,
					expectedOwnedQuantity = 101,
				} :: { [string]: any }
				if selling then
					changes.expectedUnitGold = 3
				end
				for field, value in changes do
					local changed = selection(selling, 0, "binding")
					changed[field] = value
					expect(execute(f.first, changed).code).toBe("RequestConflict")
				end
				local opposite = if selling then f.api.Discard else f.api.Sell
				expect(opposite(f.first, selection(not selling, 0, "binding")).code).toBe(
					"RequestConflict"
				)
				expect(f.profiles[f.first]).toEqual(after)
				expect(f.state.callbackCalls).toBe(1)
			end
		end
	)

	it("binds adjacent large safe integers without lossy request signatures", function()
		for _, selling in { true, false } do
			local fields = { "quantity", "expectedOwnedQuantity" }
			if selling then
				table.insert(fields, "expectedUnitGold")
			end
			for _, field in fields do
				local f = fixture()
				local execute = if selling then f.api.Sell else f.api.Discard
				local request = selection(selling, 0, "large")
				request[field] = 2 ^ 52
				expect(execute(f.first, request).ok).toBe(false)
				request[field] += 1
				expect(execute(f.first, request).code).toBe("RequestConflict")
				expect(f.state.callbackCalls).toBe(1)
			end
		end
	end)

	it(
		"retains successful and rejected disposal receipts through reconnect-style serialization",
		function()
			for _, selling in { true, false } do
				local f = fixture()
				local execute = if selling then f.api.Sell else f.api.Discard
				local request = selection(selling, 0, "before-save")
				local result = execute(f.first, request)
				expect(result.ok).toBe(true)
				local failed = selection(selling, 1, "stale-ownership")
				expect(execute(f.first, failed).code).toBe("QuantityChanged")
				local restored = fixture(copy(f.profiles[f.first]))
				local restoredExecute = if selling then restored.api.Sell else restored.api.Discard
				expect(
					restoredExecute(restored.first, selection(selling, 2, "remaining", 75, 75)).ok
				).toBe(true)
				local after = copy(restored.profiles[restored.first])
				expect(restoredExecute(restored.first, request)).toEqual({
					ok = true,
					revision = 1,
					values = result.values,
					replayed = true,
				})
				expect(restoredExecute(restored.first, failed)).toEqual({
					ok = false,
					code = "QuantityChanged",
					revision = 2,
					replayed = true,
				})
				expect(restored.state.callbackCalls).toBe(1)
				expect(restored.profiles[restored.first]).toEqual(after)
			end
		end
	)

	it("never repeats a completed disposal after its bounded receipt has been evicted", function()
		for _, selling in { true, false } do
			local f = fixture()
			local execute = if selling then f.api.Sell else f.api.Discard
			local first = selection(selling, 0, "old", 1, 100)
			expect(execute(f.first, first).ok).toBe(true)
			for revision = 1, PlayerData.maxRequestReceipts do
				expect(
					execute(f.first, selection(selling, revision, "eviction", 1, 100 - revision)).ok
				).toBe(true)
			end
			local data = f.profiles[f.first]
			local receipts = assert(
				data.transactions,
				"[MaterialDisposalCommand.spec] Expected receipts"
			).receipts
			expect(receipts[first.requestId]).toBeNil()
			local before = copy(data)
			local calls = f.state.callbackCalls
			expect(execute(f.first, first).code).toBe("StaleRevision")
			expect(f.state.callbackCalls).toBe(calls)
			expect(data).toEqual(before)
		end
	end)

	it("rejects unloaded profiles and stale revisions before mutation", function()
		for _, selling in { true, false } do
			local f = fixture()
			local execute = if selling then f.api.Sell else f.api.Discard
			local before = copy(f.profiles[f.first])
			f.state.available = false
			expect(execute(f.first, selection(selling, 0, "unloaded")).code).toBe("DataUnavailable")
			expect(f.state.transactionCalls).toBe(0)
			f.state.available = true
			expect(execute(f.first, selection(selling, 1, "stale-revision")).code).toBe(
				"StaleRevision"
			)
			expect(f.state.callbackCalls).toBe(0)
			expect(f.profiles[f.first]).toEqual(before)
		end
	end)

	it(
		"rolls back removal, Gold, and receipts if the profile session is lost before commit",
		function()
			for _, selling in { true, false } do
				local f = fixture()
				local execute = if selling then f.api.Sell else f.api.Discard
				local before = copy(f.profiles[f.first])
				f.state.loseSessionAfterCallback = true
				expect(execute(f.first, selection(selling, 0, "session-loss"))).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
				expect(f.profiles[f.first]).toEqual(before)
			end
		end
	)

	it("isolates disposal and request receipts to the requesting profile", function()
		for _, selling in { true, false } do
			local f = fixture()
			local execute = if selling then f.api.Sell else f.api.Discard
			local otherBefore = copy(f.profiles[f.second])
			local request = selection(selling, 0, "shared-id")
			expect(execute(f.first, request).ok).toBe(true)
			expect(f.profiles[f.second]).toEqual(otherBefore)
			local firstAfter = copy(f.profiles[f.first])
			local result = execute(f.second, request)
			expect(result.ok).toBe(true)
			expect(result.replayed).toBeNil()
			expect(f.profiles[f.first]).toEqual(firstAfter)
		end
	end)
end)
