--!strict
-- ServerStorage/Tests/__tests__/ShrineView.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local ShrineView = require(ServerScriptService.Services.BaseService.ShrineView)
local ShrineUpgradePurchase =
	require(ServerScriptService.Services.BaseService.ShrineUpgradePurchase)
local ShrineDismantling = require(ServerScriptService.Services.BaseService.ShrineDismantling)
local ShrineCollection = require(ServerScriptService.Services.ProductionService.ShrineCollection)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local CONTENT = {
	{
		element = "Fire",
		shrineId = "fire_shrine",
		materialId = "fire_material",
		formId = "mythling_0001",
	},
	{
		element = "Water",
		shrineId = "water_shrine",
		materialId = "water_material",
		formId = "mythling_0004",
	},
	{
		element = "Earth",
		shrineId = "earth_shrine",
		materialId = "earth_material",
		formId = "mythling_0007",
	},
	{
		element = "Air",
		shrineId = "air_shrine",
		materialId = "air_material",
		formId = "mythling_0010",
	},
	{
		element = "Light",
		shrineId = "light_shrine",
		materialId = "light_material",
		formId = "mythling_0013",
	},
	{
		element = "Dark",
		shrineId = "dark_shrine",
		materialId = "dark_material",
		formId = "mythling_0016",
	},
}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function worker(formId: string, level: number?): Types.MythlingEntry
	return {
		typeId = formId,
		variantId = "retained_variant",
		claimedAt = 25,
		level = level or 1,
		xp = 0,
		pendingXp = 0,
	}
end

local function shrine(id: string, shrineId: string, slot: number): Types.ShrineRecord
	return {
		id = id,
		shrineId = shrineId,
		buildSlotId = slot,
		level = 1,
		stored = 10,
		progress = 0.5,
		newWork = 0.25,
		workerIdsBySlot = {},
	}
end

local function fixture()
	local data = copy(PlayerDataTemplate)
	local state = { loaded = true, reads = 0, ids = 0, protectedCalls = 0 }
	assert(ProfileSchema.Prepare(data, function()
		state.ids += 1
		return "permanent_station"
	end, 0))
	data.currency.gold = 20_000
	data.materials = { fire_material = { total = 5_000 } }
	local selected = shrine("selected", "fire_shrine", 1)
	data.base.shrines = { selected = selected }
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local function forbidden()
		state.protectedCalls += 1
		error("Shrine reads must not load, transact, save, or settle")
	end
	local source = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			expect(caller).toBe(player)
			state.reads += 1
			return if state.loaded then data else nil
		end,
		Load = forbidden,
		Transact = forbidden,
		SaveNow = forbidden,
		Checkpoint = forbidden,
	}
	return {
		data = data,
		player = player,
		selected = selected,
		state = state,
		api = ShrineView.new(source),
	}
end

local function get(api: ShrineView.ShrineView, player: Player): Types.ShrineView
	local result = api.Get(player, { shrineInstanceId = "selected" })
	assert(result.ok, `Expected Shrine view, got {tostring(result.code)}`)
	return (assert(result.view, "Expected Shrine projection"))
end

local function exactKeys(value: unknown, expected: { string })
	assert(type(value) == "table", "Expected projected table")
	local actual = {}
	for key in value :: { [string]: unknown } do
		table.insert(actual, key)
	end
	table.sort(actual)
	table.sort(expected)
	expect(actual).toEqual(expected)
end

describe("ShrineView", function()
	it(
		"projects all six definitions and three levels with configured level-scaled worker Yield",
		function()
			for _, content in CONTENT do
				for level, workerLevel in { 1, 50, 100 } do
					local f = fixture()
					f.selected.shrineId, f.selected.level = content.shrineId, level
					f.data.materials = { [content.materialId] = { total = 5_000 } }
					f.data.mythlings.assigned = worker(content.formId, workerLevel)
					f.selected.workerIdsBySlot = { ["1"] = "assigned" }
					local before = copy(f.data)
					local view = get(f.api, f.player)
					local yieldPerHour = 12 * (1 + (workerLevel - 1) * 0.01)
					expect(view).toEqual({
						shrineInstanceId = "selected",
						shrineId = content.shrineId,
						buildSlotId = 1,
						level = level,
						maxLevel = 3,
						element = content.element,
						materialId = content.materialId,
						stored = 10,
						storageCapacity = ({ 300, 1_200, 3_600 })[level],
						yieldPerHour = view.yieldPerHour,
						isProducing = true,
						productionProgress = view.productionProgress,
						estimatedSecondsToNextMaterial = view.estimatedSecondsToNextMaterial,
						slots = view.slots,
						availableWorkers = {},
						collectable = 10,
						canCollect = true,
						canDismantle = false,
						dismantleCode = "ShrineOccupied",
						upgrade = view.upgrade,
						upgradeCode = if level == 3 then "MaxLevel" else nil,
					})
					expect(view.productionProgress).toBeCloseTo(0.75, 8)
					expect(type(view.estimatedSecondsToNextMaterial)).toBe("number")
					expect(view.yieldPerHour).toBeCloseTo(yieldPerHour, 8)
					expect(#view.slots).toBe(level)
					for slotId, slot in view.slots do
						expect(slot.slotId).toBe(slotId)
						if slotId == 1 then
							local assigned = assert(slot.worker, "Expected assigned worker")
							exactKeys(
								assigned,
								{ "workerId", "formId", "level", "xp", "yieldPerHour" }
							)
							expect(assigned.workerId).toBe("assigned")
							expect(assigned.formId).toBe(content.formId)
							expect(assigned.level).toBe(workerLevel)
							expect(assigned.xp).toBe(0)
							expect(assigned.yieldPerHour).toBeCloseTo(yieldPerHour, 8)
						else
							expect(slot).toEqual({ slotId = slotId })
						end
					end
					if level == 3 then
						expect(view.upgrade).toBeNil()
					else
						expect(view.upgrade).toEqual({
							expectedLevel = level,
							level = level + 1,
							materialId = content.materialId,
							goldCost = if level == 1 then 1_000 else 15_000,
							materialQuantity = if level == 1 then 400 else 4_000,
							ownedMaterialQuantity = 5_000,
							workerSlots = level + 1,
							storageCapacity = if level == 1 then 1_200 else 3_600,
							canUpgrade = true,
						})
					end
					expect(f.data).toEqual(before)
					expect(f.state.ids).toBe(1)
					expect(f.state.protectedCalls).toBe(0)
				end
			end
		end
	)

	it(
		"sorts only matching unassigned canonical candidates and sums actual assigned rates",
		function()
			local f = fixture()
			f.selected.level = 3
			f.data.mythlings = {
				assigned = worker("mythling_0001"),
				assigned_epic = worker("mythling_0003", 100),
				elsewhere = worker("mythling_0002"),
				z_candidate = worker("mythling_0003", 100),
				a_candidate = worker("mythling_0002", 50),
				other_element = worker("mythling_0004"),
				legacy = { typeId = "retained_unknown", variantId = "regular", claimedAt = 0 },
			}
			f.data.mythlings.a_candidate.xp = 17
			f.selected.workerIdsBySlot = { ["3"] = "assigned_epic", ["1"] = "assigned" }
			local other = shrine("other", "fire_shrine", 2)
			other.workerIdsBySlot = { ["1"] = "elsewhere" }
			f.data.base.shrines = { other = other, selected = f.selected }
			local raw = f.data :: any
			raw.secret, raw.base.secret, raw.base.shrines.selected.secret =
				"profile", "base", "shrine"
			raw.mythlings.a_candidate.secret = "candidate"
			raw.mythlings.assigned.luck, raw.mythlings.assigned.traitId = 999, "retained_trait"
			raw.mythlings.assigned.pendingXp = 0.25
			local before = copy(f.data)
			local view = get(f.api, f.player)
			expect(view.yieldPerHour).toBeCloseTo(12 + 32 * 1.99, 8)
			expect(view.slots[2]).toEqual({ slotId = 2 })
			expect(view.availableWorkers).toEqual({
				{
					workerId = "a_candidate",
					formId = "mythling_0002",
					level = 50,
					xp = 17,
					yieldPerHour = 18 * 1.49,
				},
				{
					workerId = "z_candidate",
					formId = "mythling_0003",
					level = 100,
					xp = 0,
					yieldPerHour = 32 * 1.99,
				},
			})
			exactKeys(view.slots[1], { "slotId", "worker" })
			exactKeys(view.slots[1].worker, { "workerId", "formId", "level", "xp", "yieldPerHour" })
			exactKeys(view, {
				"shrineInstanceId",
				"shrineId",
				"buildSlotId",
				"level",
				"maxLevel",
				"element",
				"materialId",
				"stored",
				"storageCapacity",
				"yieldPerHour",
				"isProducing",
				"productionProgress",
				"estimatedSecondsToNextMaterial",
				"slots",
				"availableWorkers",
				"collectable",
				"canCollect",
				"canDismantle",
				"dismantleCode",
				"upgradeCode",
			})
			f.selected.stored = 3_600
			local full = get(f.api, f.player)
			expect(full.isProducing).toBe(false)
			expect(full.estimatedSecondsToNextMaterial).toBeNil()
			expect(full.yieldPerHour).toBeCloseTo(view.yieldPerHour, 8)
			f.selected.stored = 10
			expect(f.data).toEqual(before)
		end
	)

	it(
		"uses committed output and reserved stack room for partial, full and over-cap collection",
		function()
			for _, sample in
				{
					{ owned = 995, reserved = 0, amount = 5 },
					{ owned = 995, reserved = 3, amount = 2 },
					{ owned = 1_000, reserved = 0, amount = 0 },
					{ owned = 1_100, reserved = 0, amount = 0 },
				}
			do
				local f = fixture()
				f.data.materials = {
					fire_material = { total = sample.owned },
					retained_material = { total = 11_000 },
				}
				f.data.craftingJobs = {
					opaque = {
						status = "Active",
						reservations = {
							equipment = 1,
							materials = { fire_material = sample.reserved },
						},
					},
				}
				local before = copy(f.data)
				local view = get(f.api, f.player)
				expect(view.collectable).toBe(sample.amount)
				expect(view.canCollect).toBe(sample.amount > 0)
				expect(view.collectCode).toBe(if sample.amount > 0 then nil else "InventoryFull")
				local snapshot = assert(ShrineAccounting.ReadSnapshot(f.data))
				local collected, problem = ShrineCollection.Collect(snapshot.state, f.data, 0, {
					shrineInstanceId = "selected",
					expectedMaterialId = "fire_material",
				}, snapshot.metadata)
				if sample.amount > 0 then
					assert(collected, "Expected partial collection")
					expect(collected.collected).toBe(view.collectable)
				else
					expect(problem).toBe(view.collectCode)
				end
				expect(f.data).toEqual(before)
				f.selected.stored = 0
				local empty = get(f.api, f.player)
				expect(empty.collectable).toBe(0)
				expect(empty.collectCode).toBe("NothingToCollect")
			end
		end
	)

	it(
		"matches upgrade affordability at the saved cursor without counting stored output or refunds",
		function()
			for _, sample in
				{
					{ gold = 999, owned = 5_000, code = "InsufficientGold" },
					{ gold = 20_000, owned = 399, code = "InsufficientMaterials" },
					{ gold = 20_000, owned = 400, code = "" },
				}
			do
				local f = fixture()
				f.data.currency.gold = sample.gold
				f.data.materials.fire_material.total = sample.owned
				f.selected.stored = 300
				f.data.craftingJobs = {
					legacy = {
						status = "Active",
						reservations = { equipment = 1, materials = { fire_material = 400 } },
					},
				}
				local before = copy(f.data)
				local view = get(f.api, f.player)
				local offer = assert(view.upgrade, "Expected upgrade quote")
				expect(offer.ownedMaterialQuantity).toBe(sample.owned)
				expect(offer.canUpgrade).toBe(sample.code == "")
				expect(offer.upgradeCode).toBe(if sample.code == "" then nil else sample.code)
				expect(f.data).toEqual(before)
				local mutationData = copy(f.data)
				local commands = ShrineUpgradePurchase.new({
					GetLoadedData = function(): Types.PlayerDoc?
						return mutationData
					end,
					Transact = function(_player, request, mutation)
						return Transactions.Run(mutationData, request, function(draft)
							return mutation(draft, 0)
						end, function()
							return true
						end)
					end,
				}, function()
					return 0
				end)
				local result = commands.Upgrade(f.player, {
					requestId = "0:upgrade",
					expectedRevision = 0,
					shrineInstanceId = "selected",
					expectedLevel = offer.expectedLevel,
					expectedMaterialId = offer.materialId,
					expectedGoldCost = offer.goldCost,
					expectedMaterialQuantity = offer.materialQuantity,
				})
				expect(result.ok).toBe(offer.canUpgrade)
				expect(result.code).toBe(offer.upgradeCode)
			end
		end
	)

	it(
		"does not settle elapsed jobs, pending XP or earned work and uses committed dismantle reasons",
		function()
			local f = fixture()
			f.selected.stored, f.selected.newWork = 0, 2
			f.data.craftingJobs = {
				due = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
					receipt = {
						version = 1,
						recipeId = "elemental_sword_fire",
						stationId = "permanent_station",
						craftingStationId = "basic_crafting_station",
						startedAt = 0,
						completesAt = 1,
						result = {
							definitionId = "elemental_sword",
							finishId = "fire",
							quantity = 1,
							instanceIds = { "promised_output" },
						},
						paid = { gold = 50, materials = { fire_material = 5 } },
					},
				},
			}
			f.data.mythlings.retired_worker = worker("mythling_0001")
			f.data.mythlings.retired_worker.pendingXp = 119.5
			local before = copy(f.data)
			local view = get(f.api, f.player)
			expect(view.stored).toBe(0)
			expect(view.yieldPerHour).toBe(0)
			expect(view.isProducing).toBe(false)
			expect(view.canDismantle).toBe(true)
			expect(view.dismantleCode).toBeNil()
			expect(view.collectCode).toBe("NothingToCollect")
			expect(get(f.api, f.player)).toEqual(view)
			expect(f.data).toEqual(before)
			expect(f.data.equipment.promised_output).toBeNil()
			expect(f.state.protectedCalls).toBe(0)
			local snapshot = assert(ShrineAccounting.ReadSnapshot(f.data))
			local _, code = ShrineDismantling.Dismantle(snapshot.state, f.data.base, 1, {
				shrineInstanceId = "selected",
				expectedLevel = 1,
			}, snapshot.metadata)
			expect(code).toBe("MaterialsStored")
			f.selected.stored = 1
			expect(get(f.api, f.player).dismantleCode).toBe("MaterialsStored")
			f.selected.workerIdsBySlot = { ["1"] = "retired_worker" }
			expect(get(f.api, f.player).dismantleCode).toBe("ShrineOccupied")
		end
	)

	it("detaches nested rows and accepts a deeply frozen valid saved profile", function()
		local f = fixture()
		f.data.mythlings.assigned = worker("mythling_0001")
		f.data.mythlings.available = worker("mythling_0002")
		f.selected.workerIdsBySlot = { ["1"] = "assigned" }
		local before = copy(f.data)
		FreezeUtil.DeepFreeze(f.data)
		local view = get(f.api, f.player)
		local expected = copy(view)
		pcall(function()
			view.stored = 999
		end)
		pcall(function()
			view.slots[1].slotId = 9
		end)
		pcall(function()
			local selected = assert(view.slots[1].worker, "Expected assigned worker")
			selected.xp = 9_999
		end)
		pcall(function()
			view.availableWorkers[1].level = 99
		end)
		pcall(function()
			local offer = assert(view.upgrade, "Expected upgrade quote")
			offer.goldCost = 1
		end)
		expect(get(f.api, f.player)).toEqual(expected)
		expect(f.data).toEqual(before)
		expect(f.state.ids).toBe(1)
		expect(f.state.protectedCalls).toBe(0)
	end)

	it(
		"rejects malformed requests in profile/revision order and omits the complete view on invalid state",
		function()
			local f = fixture()
			f.state.loaded = false
			expect(f.api.Get(f.player, nil)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			f.state.loaded = true
			f.data.transactions = { revision = -1, receipts = {} }
			expect(f.api.Get(f.player, nil)).toEqual({
				ok = false,
				code = "InvalidTransaction",
				revision = -1,
			})
			f.data.transactions = { revision = 7, receipts = {} }
			for _, request in
				{
					false,
					"selected",
					{},
					{ shrineInstanceId = "" },
					{ shrineInstanceId = string.rep("x", 129) },
					{ shrineInstanceId = "selected", targetUserId = 9001 },
					{ shrineInstanceId = "selected", expectedRevision = 7 },
					setmetatable({ shrineInstanceId = "selected" }, {}),
				}
			do
				expect(f.api.Get(f.player, request)).toEqual({
					ok = false,
					code = "InvalidRequest",
					revision = 7,
				})
			end
			expect(f.api.Get(f.player, { shrineInstanceId = "missing" })).toEqual({
				ok = false,
				code = "ShrineNotOwned",
				revision = 7,
			})
			local mutations: { (any) -> () } = {
				function(raw)
					raw.version = -1
				end,
				function(raw)
					raw.base = nil
				end,
				function(raw)
					raw.productionClock = nil
				end,
				function(raw)
					raw.base.shrines.selected.workerIdsBySlot = { ["1"] = "missing" }
				end,
				function(raw)
					raw.base.shrines.selected.stored = -1
				end,
				function(raw)
					raw.materials.fire_material.total = -1
				end,
				function(raw)
					raw.currency.gold = "bad"
				end,
				function(raw)
					raw.inventoryUpgrades = { materials = 3 }
				end,
				function(raw)
					raw.craftingJobs = {
						bad = {
							status = "Active",
							reservations = { equipment = -1, materials = {} },
						},
					}
				end,
				function(raw)
					raw.mythlings.bad = { typeId = "mythling_0001", level = 1, xp = 0 }
				end,
				function(raw)
					raw.mythlings.bad = { typeId = "opaque_legacy", pendingXp = 1 }
				end,
			}
			for _, mutate in mutations do
				local other = fixture()
				other.data.transactions = { revision = 7, receipts = {} }
				other.selected.level = 3 -- Maximum level must not bypass global resource validation.
				mutate(other.data)
				local result = other.api.Get(other.player, { shrineInstanceId = "selected" })
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(result.revision).toBe(7)
				expect(result.view).toBeNil()
				expect(other.state.protectedCalls).toBe(0)
			end
		end
	)
end)
