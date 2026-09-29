--!strict
-- ServerStorage/Tests/__tests__/EquipmentSaleCommand.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local EquipmentSaleCommand =
	require(ServerScriptService.Services.InventoryService.EquipmentSaleCommand)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local MAX_SAFE_INTEGER = 2 ^ 53 - 1
local FINISHES = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function activeJob(): Types.CraftingJob
	return {
		status = "Active",
		reservations = { equipment = 1, materials = { fire_material = 5 } },
		receipt = {
			version = 1,
			recipeId = "elemental_sword_fire",
			stationId = "sale_station",
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

local function profile(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return "sale_station"
	end, 0)
	assert(prepared, `[EquipmentSaleCommand.spec] Fixture preparation failed: {tostring(problem)}`)
	data.equipment.selected = { definitionId = "elemental_sword", finishId = "fire" }
	data.equipment.other = { definitionId = "elemental_shield", finishId = "water" }
	data.materials.fire_material = { total = 15 }
	data.mythlings.worker = {
		typeId = "mythling_0001",
		variantId = "regular",
		claimedAt = 0,
		level = 6,
		xp = 12,
		pendingXp = 0.5,
	}
	data.base.shrines = {
		first = {
			id = "first",
			shrineId = "fire_shrine",
			buildSlotId = 1,
			level = 1,
			stored = 20,
			progress = 0.25,
			newWork = 0.01,
			workerIdsBySlot = { ["1"] = "worker" },
		},
	}
	return data
end

-- Deliberately malformed payloads below stay at this untrusted command boundary.
local function selection(revision: number, token: string): any
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		instanceId = "selected",
		expectedDefinitionId = "elemental_sword",
		expectedFinishId = "fire",
		expectedGold = 25,
	}
end

local function fixture(saved: Types.PlayerDoc?)
	-- Private commands need identity only; the public service validates connected engine Players.
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local data = saved or profile()
	local state = {
		now = 10,
		active = true,
		available = true,
		loseSessionAfterCallback = false,
		transactionCalls = 0,
		callbackCalls = 0,
		operations = {} :: { string },
	}
	local source: EquipmentSaleCommand.DataSource = {
		GetLoadedData = function(requestingPlayer: Player): Types.PlayerDoc?
			return if requestingPlayer == player
					and state.active
					and state.available
				then data
				else nil
		end,
		Transact = function(requestingPlayer, request, mutate)
			state.transactionCalls += 1
			table.insert(state.operations, request.operation)
			if requestingPlayer ~= player or not state.available then
				return { ok = false, code = "DataUnavailable", revision = 0 }
			end
			return Transactions.Run(data, request, function(draft)
				state.callbackCalls += 1
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
	return { player = player, data = data, state = state, api = EquipmentSaleCommand.new(source) }
end

describe("EquipmentSaleCommand", function()
	it(
		"sells all twelve named variants for 25 Gold without per-copy stat or acquisition bonuses",
		function()
			for _, definitionId in { "elemental_sword", "elemental_shield" } do
				for _, finishId in FINISHES do
					for _, route in { "crafted", "featured" } do
						local f = fixture()
						-- Retained unknown saved fields must not override catalogue economics.
						local entry: any = {
							definitionId = definitionId,
							finishId = finishId,
							isStarterGrant = false,
							rarity = "Mythical",
							level = 100,
							xp = 999,
							sellGold = 9999,
							acquisitionRoute = route,
						}
						f.data.equipment.selected = entry
						local before = gameplay(f.data)
						local request = selection(0, "variant")
						request.expectedDefinitionId = definitionId
						request.expectedFinishId = finishId
						expect(f.api.Sell(f.player, request)).toEqual({
							ok = true,
							revision = 1,
							values = {
								instanceId = "selected",
								definitionId = definitionId,
								finishId = finishId,
								goldGranted = 25,
								goldBalance = before.currency.gold + 25,
							},
						})
						before.equipment.selected = nil
						before.currency.gold += 25
						expect(gameplay(f.data)).toEqual(before)
						expect(f.state.operations).toEqual({ "Inventory.SellEquipment" })
					end
				end
			end
		end
	)

	it(
		"protects the original starter pair and starter-marked sellable items before stale quotes",
		function()
			for _, instanceId in { "starter_wooden_sword", "starter_wooden_shield", "selected" } do
				local f = fixture()
				f.data.equipment[instanceId].isStarterGrant = true
				local request = selection(0, "starter")
				request.instanceId = instanceId
				request.expectedGold = 999
				local before = gameplay(f.data)
				expect(f.api.Sell(f.player, request).code).toBe("StarterProtected")
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it("requires explicit unequipping from either slot without clearing the loadout", function()
		for _, slot in { "primaryWeaponInstanceId", "shieldInstanceId" } do
			local f = fixture()
			local loadout: any = f.data.combatLoadout
			loadout[slot] = "selected"
			local before = gameplay(f.data)
			expect(f.api.Sell(f.player, selection(0, "equipped")).code).toBe("Equipped")
			expect(gameplay(f.data)).toEqual(before)
			loadout[slot] = nil
			expect(f.api.Sell(f.player, selection(1, "unequipped")).ok).toBe(true)
		end
	end)

	it("leaves unsellable wooden and unknown legacy metadata untouched", function()
		for _, pair in
			{
				{ "wooden_sword" },
				{ "wooden_shield" },
				{ "legacy_weapon", "retained_finish" },
				{ "elemental_sword", "unreleased_finish" },
			}
		do
			local f = fixture()
			f.data.equipment.selected = { definitionId = pair[1], finishId = pair[2] }
			f.data.combatLoadout = {}
			local request = selection(0, "unsellable")
			request.expectedDefinitionId = pair[1]
			request.expectedFinishId = pair[2]
			local before = gameplay(f.data)
			expect(f.api.Sell(f.player, request).code).toBe("NotSellable")
			expect(gameplay(f.data)).toEqual(before)
		end
	end)

	it(
		"rejects unowned selections and reserved future output instead of claiming or releasing it",
		function()
			for _, instanceId in { "missing", "promised_output" } do
				local f = fixture()
				f.data.craftingJobs = { pending = activeJob() }
				local before = gameplay(f.data)
				local request = selection(0, "not-owned")
				request.instanceId = instanceId
				expect(f.api.Sell(f.player, request).code).toBe("NotOwned")
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"rejects stale definition, finish, absent finish, and price without substituting an item",
		function()
			for _, field in
				{ "expectedDefinitionId", "expectedFinishId", "expectedGold", "omitFinish" }
			do
				local f = fixture()
				local request = selection(0, "stale")
				if field == "omitFinish" then
					request.expectedFinishId = nil
				else
					request[field] = if field == "expectedGold" then 26 else "changed"
				end
				local before = gameplay(f.data)
				local code = if field == "expectedGold" then "PriceChanged" else "EquipmentChanged"
				expect(f.api.Sell(f.player, request).code).toBe(code)
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"requires the requesting player's loaded active profile before entering a transaction",
		function()
			for _, unavailable in { "unloaded", "ended", "other-player" } do
				local f = fixture()
				local player = f.player
				if unavailable == "unloaded" then
					f.state.available = false
				elseif unavailable == "ended" then
					f.state.active = false
				else
					player = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
				end
				local before = copy(f.data)
				expect(f.api.Sell(player, selection(0, "unavailable")).code).toBe("DataUnavailable")
				expect(f.state.transactionCalls).toBe(0)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"rejects forged fields, missing fields, malformed IDs and unsafe or fractional numbers",
		function()
			local payloads: { any } = { false, "sale", setmetatable(selection(0, "meta"), {}) }
			local forged = selection(0, "forged")
			forged.playerId = 1002
			table.insert(payloads, forged)
			for _, field in
				{
					"requestId",
					"expectedRevision",
					"instanceId",
					"expectedDefinitionId",
					"expectedGold",
				}
			do
				local request = selection(0, "missing")
				request[field] = nil
				table.insert(payloads, request)
			end
			for _, field in
				{ "requestId", "instanceId", "expectedDefinitionId", "expectedFinishId" }
			do
				for _, value in { "", string.rep("x", 129), false, 25, {} } do
					local request = selection(0, "id")
					request[field] = value
					table.insert(payloads, request)
				end
			end
			for _, field in { "expectedRevision", "expectedGold" } do
				for _, value in { -1, 0.5, 2 ^ 53, math.huge, 0 / 0, "25", false } do
					local request = selection(0, "number")
					request[field] = value
					table.insert(payloads, request)
				end
			end
			local zeroPrice = selection(0, "zero")
			zeroPrice.expectedGold = 0
			table.insert(payloads, zeroPrice)
			for _, request in payloads do
				local f = fixture()
				local before = copy(f.data)
				expect(f.api.Sell(f.player, request).code).toBe("InvalidRequest")
				expect(f.state.transactionCalls).toBe(0)
				expect(f.data).toEqual(before)
			end
		end
	)

	it("accepts the bounded instance/request IDs and an empty unequipped loadout", function()
		local f = fixture()
		local instanceId = string.rep("x", 128)
		f.data.equipment[instanceId] = f.data.equipment.selected
		f.data.equipment.selected = nil
		f.data.combatLoadout = {}
		local request = selection(0, string.rep("r", 126))
		request.instanceId = instanceId
		expect(f.api.Sell(f.player, request).ok).toBe(true)
		expect(f.data.equipment[instanceId]).toBeNil()
		expect(f.data.combatLoadout).toEqual({})
	end)

	it(
		"fails closed for invalid schema, selected records, starter flags, and saved loadouts",
		function()
			-- Serializable malformed saves reach domain validation rather than clone rejection.
			local cases: { { code: string, mutate: (any) -> () } } = {
				{
					code = "UnsupportedVersion",
					mutate = function(data)
						data.version = PlayerData.schemaVersion + 1
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data)
						data.equipment = false
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data)
						data.equipment.selected = false
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data)
						data.equipment.selected.definitionId = ""
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data)
						data.equipment.selected.finishId = false
					end,
				},
				{
					code = "InvalidInventoryState",
					mutate = function(data)
						data.equipment.selected.isStarterGrant = "false"
					end,
				},
				{
					code = "InvalidLoadoutState",
					mutate = function(data)
						data.combatLoadout = nil
					end,
				},
				{
					code = "InvalidLoadoutState",
					mutate = function(data)
						data.combatLoadout = false
					end,
				},
			}
			for _, slot in { "primaryWeaponInstanceId", "shieldInstanceId" } do
				for _, value in { "", string.rep("x", 129), 1, {} } do
					table.insert(cases, {
						code = "InvalidLoadoutState",
						mutate = function(data: any)
							data.combatLoadout[slot] = value
						end,
					})
				end
			end
			for _, case in cases do
				local f = fixture()
				case.mutate(f.data)
				local before = gameplay(f.data)
				expect(f.api.Sell(f.player, selection(0, "state")).code).toBe(case.code)
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"sells down retained over-capacity holdings without touching reservations or unrelated state",
		function()
			local f = fixture()
			for index = 1, 40 do
				f.data.equipment[`retained_{index}`] = { definitionId = "retained_legacy" }
			end
			f.data.craftingJobs = { pending = activeJob() }
			local loadout: any = f.data.combatLoadout
			loadout.retainedFutureField = { value = "keep" }
			local before = gameplay(f.data)
			expect(f.api.Sell(f.player, selection(0, "sell-down")).ok).toBe(true)
			before.equipment.selected = nil
			before.currency.gold += 25
			expect(gameplay(f.data)).toEqual(before)
		end
	)

	it("keeps exact Gold headroom for active crafting refunds before removing Equipment", function()
		for _, fits in { false, true } do
			local f = fixture()
			f.data.craftingJobs = { pending = activeJob() }
			f.data.currency.gold = MAX_SAFE_INTEGER - (if fits then 75 else 74)
			local before = gameplay(f.data)
			local result = f.api.Sell(f.player, selection(0, "headroom"))
			if fits then
				expect(result.ok).toBe(true)
				expect(f.data.currency.gold).toBe(MAX_SAFE_INTEGER - 50)
				before.currency.gold += 25
				before.equipment.selected = nil
			else
				expect(result.code).toBe("ArithmeticOverflow")
			end
			expect(gameplay(f.data)).toEqual(before)
		end
	end)

	it("rejects malformed currency and refund claims without removing an item", function()
		local cases: { { code: string, mutate: (any) -> () } } = {
			{
				code = "InvalidCurrency",
				mutate = function(data)
					data.currency.gold = -1
				end,
			},
			{
				code = "InvalidCurrency",
				mutate = function(data)
					data.currency.gold = 0.5
				end,
			},
			{
				code = "InvalidCurrency",
				mutate = function(data)
					data.currency.gold = "100"
				end,
			},
			{
				code = "ArithmeticOverflow",
				mutate = function(data)
					data.currency.gold = MAX_SAFE_INTEGER
				end,
			},
			{
				code = "InvalidCraftingState",
				mutate = function(data)
					data.craftingJobs.pending.receipt.paid.gold = -1
				end,
			},
			{
				code = "InvalidCraftingState",
				mutate = function(data)
					data.craftingJobs.pending.receipt.version = 2
				end,
			},
		}
		for _, case in cases do
			local f = fixture()
			f.data.craftingJobs = { pending = activeJob() }
			case.mutate(f.data)
			local before = gameplay(f.data)
			expect(f.api.Sell(f.player, selection(0, "bad-credit")).code).toBe(case.code)
			expect(gameplay(f.data)).toEqual(before)
		end
	end)

	it(
		"rolls back the item, Gold, and receipt if the profile session ends after draft mutation",
		function()
			local f = fixture()
			f.state.loseSessionAfterCallback = true
			local before = copy(f.data)
			expect(f.api.Sell(f.player, selection(0, "session-loss")).code).toBe("DataUnavailable")
			expect(f.state.callbackCalls).toBe(1)
			expect(f.data).toEqual(before)
		end
	)

	it(
		"replays the original result and rejects changed selection signatures without another callback",
		function()
			local f = fixture()
			local request = selection(0, "once")
			local sold = f.api.Sell(f.player, request)
			expect(sold.ok).toBe(true)
			local second = selection(1, "second")
			second.instanceId = "other"
			second.expectedDefinitionId = "elemental_shield"
			second.expectedFinishId = "water"
			expect(f.api.Sell(f.player, second).ok).toBe(true)
			local after = copy(f.data)
			expect(f.api.Sell(f.player, request)).toEqual({
				ok = true,
				revision = 1,
				values = sold.values,
				replayed = true,
			})
			local overrides: { [string]: string | number } = {
				instanceId = "other",
				expectedDefinitionId = "elemental_shield",
				expectedFinishId = "water",
				expectedGold = 26,
			}
			for field, value in overrides do
				local changed = selection(0, "once")
				changed[field] = value
				expect(f.api.Sell(f.player, changed).code).toBe("RequestConflict")
			end
			local noFinish = selection(0, "once")
			noFinish.expectedFinishId = nil
			expect(f.api.Sell(f.player, noFinish).code).toBe("RequestConflict")
			expect(f.state.callbackCalls).toBe(2)
			expect(f.data).toEqual(after)
		end
	)

	it("binds adjacent large safe-integer quotes and retains rejected receipts", function()
		local f = fixture()
		local request = selection(0, "large")
		request.expectedGold = 2 ^ 52
		local rejected = f.api.Sell(f.player, request)
		expect(rejected.code).toBe("PriceChanged")
		local after = copy(f.data)
		expect(f.api.Sell(f.player, request)).toEqual({
			ok = false,
			code = "PriceChanged",
			revision = 1,
			replayed = true,
		})
		request.expectedGold += 1
		expect(f.api.Sell(f.player, request).code).toBe("RequestConflict")
		expect(f.state.callbackCalls).toBe(1)
		expect(f.data).toEqual(after)
	end)

	it(
		"retains replay decisions through serialization and protects changed items from stale requests",
		function()
			local f = fixture()
			local request = selection(0, "persisted")
			local sold = f.api.Sell(f.player, request)
			expect(sold.ok).toBe(true)
			local restored = fixture(copy(f.data))
			restored.data.equipment.selected =
				{ definitionId = "elemental_sword", finishId = "dark" }
			local before = gameplay(restored.data)
			expect(restored.api.Sell(restored.player, request)).toEqual({
				ok = true,
				revision = 1,
				values = sold.values,
				replayed = true,
			})
			expect(restored.api.Sell(restored.player, selection(0, "stale-revision")).code).toBe(
				"StaleRevision"
			)
			expect(restored.api.Sell(restored.player, selection(1, "stale-form")).code).toBe(
				"EquipmentChanged"
			)
			expect(gameplay(restored.data)).toEqual(before)
			expect(restored.state.callbackCalls).toBe(1)
		end
	)
end)
