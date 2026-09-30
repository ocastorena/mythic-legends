--!strict
-- ServerStorage/Tests/__tests__/BaseView.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseView = require(ServerScriptService.Services.BaseService.BaseView)
local ShrineConstruction = require(ServerScriptService.Services.BaseService.ShrineConstruction)
local BaseExpansionPurchase =
	require(ServerScriptService.Services.BaseService.BaseExpansionPurchase)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local SHRINES =
	{ "air_shrine", "dark_shrine", "earth_shrine", "fire_shrine", "light_shrine", "water_shrine" }
local MATERIALS = {
	"air_material",
	"dark_material",
	"earth_material",
	"fire_material",
	"light_material",
	"water_material",
}
local GOLD = { 10_000, 50_000, 150_000, 500_000 }
local QUANTITIES = { 50, 100, 150, 200 }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function shrine(id: string, slot: number)
	return {
		id = id,
		shrineId = "fire_shrine",
		buildSlotId = slot,
		level = 1,
		stored = 123,
		progress = 0.5,
		newWork = 0.25,
		workerIdsBySlot = {},
	}
end

local function fixture(saved: Types.PlayerDoc?, prepareDue: boolean?)
	local data = saved or copy(PlayerDataTemplate)
	if not saved then
		assert(ProfileSchema.Prepare(data, function()
			return "base_station"
		end, 0))
		data.currency.gold = 1_000_000
		for _, materialId in MATERIALS do
			data.materials[materialId] = { total = 1_000 }
		end
	end
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = { loaded = true, reads = 0, transactions = 0, ids = 0, loads = 0, saves = 0 }
	local source = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			expect(caller).toBe(player)
			state.reads += 1
			return if state.loaded then data else nil
		end,
		Transact = function(
			_caller: Player,
			request: Types.TransactionRequest,
			mutation: (Types.PlayerDoc, number) -> Types.TransactionOutcome
		): Types.TransactionResult
			state.transactions += 1
			return Transactions.Run(data, request, function(draft)
				local now = if prepareDue then 2 else 0
				if prepareDue then
					local settled = CraftingJobs.new().SettleDueToDraft(draft, now)
					if not settled.ok then
						return settled
					end
				end
				return mutation(draft, now)
			end, function()
				return true
			end)
		end,
		Load = function()
			state.loads += 1
			error("Base views must not load profiles")
		end,
		SaveNow = function()
			state.saves += 1
			error("Base views must not save profiles")
		end,
	}
	return {
		data = data,
		player = player,
		state = state,
		api = BaseView.new(source),
		build = ShrineConstruction.new(source, function()
			state.ids += 1
			return `new_shrine_{state.ids}`
		end),
		expand = BaseExpansionPurchase.new(source),
	}
end

local function getView(api: { Get: (Player) -> Types.BaseViewResult }, player: Player)
	local result = api.Get(player)
	assert(result.ok, `Expected Base view, got {tostring(result.code)}`)
	return (assert(result.view, "Expected Base projection"))
end

local function buildRequest(offer: Types.ShrineBuildOffer): Types.BuildShrineRequest
	return {
		requestId = "0:build",
		expectedRevision = 0,
		shrineId = offer.shrineId,
		expectedGoldCost = offer.goldCost,
	}
end

local function expandRequest(
	offer: Types.BaseExpansionOffer,
	revision: number
): Types.ExpandBaseRequest
	return {
		requestId = `{revision}:expand`,
		expectedRevision = revision,
		expectedUpgradeCount = offer.expectedUpgradeCount,
		expectedGoldCost = offer.goldCost,
		expectedMaterialQuantity = offer.materialQuantity,
	}
end

describe("BaseView", function()
	it(
		"returns six sorted exact build quotes and a detached six-Material expansion without writes",
		function()
			local f = fixture()
			local raw = f.data :: any
			raw.secret, raw.base.secret, raw.base.craftingStation.secret =
				"profile", "base", "station"
			local before = copy(f.data)
			local result = f.api.Get(f.player)
			local view = assert(result.view, "Expected view")
			local expansion = assert(view.expansion, "Expected initial expansion")
			expect(result).toEqual({ ok = true, revision = 0, view = view })
			expect(view).toEqual({
				status = {
					usedShrineSlots = 0,
					unlockedShrineSlots = 2,
					maxShrineSlots = 6,
					craftingStation = {
						id = "base_station",
						craftingStationId = "basic_crafting_station",
					},
				},
				buildSlotUpgradeCount = 0,
				shrines = {},
				buildOffers = view.buildOffers,
				expansion = expansion,
			})
			expect(#view.buildOffers).toBe(6)
			for index, offer in view.buildOffers do
				expect(offer).toEqual({ shrineId = SHRINES[index], goldCost = 100, canBuild = true })
				local other = fixture(copy(f.data))
				local built = other.build.Build(other.player, buildRequest(offer))
				expect(built.ok).toBe(true)
				expect(assert(built.values).buildSlotId).toBe(1)
				expect(other.state.ids).toBe(1)
			end
			expect(expansion).toEqual({
				expectedUpgradeCount = 0,
				goldCost = 10_000,
				materialQuantity = 50,
				nextUnlockedSlots = 3,
				materials = expansion.materials,
				canPurchase = true,
			})
			expect(#expansion.materials).toBe(6)
			for index, ingredient in expansion.materials do
				expect(ingredient).toEqual({
					materialId = MATERIALS[index],
					quantity = 50,
					ownedQuantity = 1_000,
				})
			end
			expect(f.data).toEqual(before)
			expect(f.state).toEqual({
				loaded = true,
				reads = 1,
				transactions = 0,
				ids = 0,
				loads = 0,
				saves = 0,
			})
		end
	)

	it(
		"quotes all four sequential purchases and removes the next offer at the permanent six-slot cap",
		function()
			local f = fixture()
			local spent = 0
			for count = 0, 3 do
				local before = copy(f.data)
				local result = f.api.Get(f.player)
				local view = assert(result.view, "Expected sequential view")
				local offer = assert(view.expansion, "Expected next expansion")
				expect(result.revision).toBe(count)
				expect(view.buildSlotUpgradeCount).toBe(count)
				expect(view.status.unlockedShrineSlots).toBe(count + 2)
				expect(view.status.usedShrineSlots).toBe(0)
				expect(offer.expectedUpgradeCount).toBe(count)
				expect(offer.goldCost).toBe(GOLD[count + 1])
				expect(offer.materialQuantity).toBe(QUANTITIES[count + 1])
				expect(offer.nextUnlockedSlots).toBe(count + 3)
				expect(offer.canPurchase).toBe(true)
				for _, ingredient in offer.materials do
					expect(ingredient.ownedQuantity).toBe(1_000 - spent)
				end
				expect(f.data).toEqual(before)
				expect(f.expand.Expand(f.player, expandRequest(offer, result.revision)).ok).toBe(
					true
				)
				spent += QUANTITIES[count + 1]
			end
			local before = copy(f.data)
			local full = getView(f.api, f.player)
			expect(full.buildSlotUpgradeCount).toBe(4)
			expect(full.status.unlockedShrineSlots).toBe(6)
			expect(full.expansion).toBeNil()
			expect(full.expansionCode).toBe("MaxBaseSlots")
			for _, offer in full.buildOffers do
				expect(offer.canBuild).toBe(true)
			end
			expect(f.state.transactions).toBe(4)
			expect(f.state.ids).toBe(0)
			expect(f.data).toEqual(before)
		end
	)

	it(
		"sorts duplicate-element Shrines by build slot and excludes the permanent station from capacity",
		function()
			local f = fixture()
			f.data.base.shrines = { alpha = shrine("alpha", 2), zeta = shrine("zeta", 1) }
			local owned = assert(f.data.base.shrines, "Expected duplicate-element layout")
			local raw = owned.alpha :: any
			raw.secret, raw.workerIdsBySlot["1"] = "private-shrine", "retained_worker"
			local before = copy(f.data)
			local view = getView(f.api, f.player)
			expect(view.shrines).toEqual({
				{ id = "zeta", shrineId = "fire_shrine", buildSlotId = 1, level = 1 },
				{ id = "alpha", shrineId = "fire_shrine", buildSlotId = 2, level = 1 },
			})
			expect(view.status.usedShrineSlots).toBe(2)
			for index, offer in view.buildOffers do
				expect(offer).toEqual({
					shrineId = SHRINES[index],
					goldCost = 100,
					canBuild = false,
					buildCode = "BaseFull",
				})
				local other = fixture(copy(f.data))
				expect(other.build.Build(other.player, buildRequest(offer)).code).toBe("BaseFull")
				expect(other.state.ids).toBe(0)
			end
			local expansion = assert(view.expansion, "Full occupancy must still permit expansion")
			expect(expansion.canPurchase).toBe(true)
			expect(expansion.materialQuantity).toBe(50)
			expect(f.data).toEqual(before)
			f.data.base.buildSlotUpgrades = 1
			local expanded = getView(f.api, f.player)
			for _, offer in expanded.buildOffers do
				expect(offer.canBuild).toBe(true)
			end
			local build = f.build.Build(f.player, buildRequest(expanded.buildOffers[1]))
			expect(build.ok).toBe(true)
			expect(assert(build.values).buildSlotId).toBe(3)
		end
	)

	it(
		"matches mutation eligibility for Gold, collected Materials and pre-upgrade refund capacity",
		function()
			local cases: { { code: string, change: (Types.PlayerDoc) -> () } } = {
				{
					code = "InsufficientGold",
					change = function(data)
						data.currency.gold = 99
					end,
				},
				{
					code = "InsufficientMaterials",
					change = function(data)
						data.materials.earth_material = nil
						data.base.shrines = { fire = shrine("fire", 1) }
						local owned = assert(data.base.shrines, "Expected stored output")
						owned.fire.stored = 300
						data.craftingJobs = {
							legacy = {
								status = "Active",
								reservations = {
									equipment = 1,
									materials = { earth_material = 50 },
								},
							},
						}
					end,
				},
				{
					code = "MaterialCapacityTooSmall",
					change = function(data)
						data.craftingJobs = {
							legacy = {
								status = "Active",
								reservations = {
									equipment = 1,
									materials = { fire_material = 12_000 },
								},
							},
						}
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				case.change(f.data)
				local before = copy(f.data)
				local view = getView(f.api, f.player)
				local expansion = assert(view.expansion, "Expected rejected quote")
				expect(expansion.canPurchase).toBe(false)
				expect(expansion.purchaseCode).toBe(case.code)
				local other = fixture(copy(f.data))
				expect(other.expand.Expand(other.player, expandRequest(expansion, 0)).code).toBe(
					case.code
				)
				for _, offer in view.buildOffers do
					local builder = fixture(copy(f.data))
					local result = builder.build.Build(builder.player, buildRequest(offer))
					expect(result.ok).toBe(offer.canBuild)
					expect(result.code).toBe(offer.buildCode)
				end
				if case.code == "InsufficientMaterials" then
					for _, ingredient in expansion.materials do
						if ingredient.materialId == "earth_material" then
							expect(ingredient.ownedQuantity).toBe(0)
						end
					end
				end
				expect(f.data).toEqual(before)
				expect(f.state.transactions + f.state.ids + f.state.loads + f.state.saves).toBe(0)
			end
		end
	)

	it(
		"allows retained over-cap holdings while reporting only owned ingredients and preserving reservations",
		function()
			local f = fixture()
			f.data.materials.retained_legacy_material = { total = 50_000 }
			f.data.craftingJobs = {
				legacy = {
					status = "Active",
					reservations = { equipment = 1, materials = { water_material = 5 } },
				},
			}
			local before = copy(f.data)
			local view = getView(f.api, f.player)
			local expansion = assert(view.expansion, "Expected retained-holdings quote")
			expect(expansion.canPurchase).toBe(true)
			for _, ingredient in expansion.materials do
				expect(ingredient.ownedQuantity).toBe(1_000)
			end
			expect(f.data).toEqual(before)
			local other = fixture(copy(f.data))
			expect(other.expand.Expand(other.player, expandRequest(expansion, 0)).ok).toBe(true)
			expect(other.data.materials.retained_legacy_material).toEqual({ total = 50_000 })
			expect(other.data.craftingJobs).toEqual(before.craftingJobs)
			expect(f.state.transactions + f.state.ids).toBe(0)
		end
	)

	it(
		"returns detached nested station, Shrine and ingredient rows without exposing private state",
		function()
			local f = fixture()
			f.data.base.shrines = { selected = shrine("selected", 1) }
			local before = copy(f.data)
			local view = getView(f.api, f.player)
			local original = copy(view)
			local expansion = assert(view.expansion, "Expected expansion")
			pcall(function()
				view.status.craftingStation.id = "tampered"
			end)
			pcall(function()
				view.shrines[1].level = 3
			end)
			pcall(function()
				view.buildOffers[1].goldCost = 0
			end)
			pcall(function()
				expansion.materials[1].ownedQuantity = 0
			end)
			pcall(function()
				expansion.materials[1] = expansion.materials[2]
			end)
			expect(f.data).toEqual(before)
			expect(getView(f.api, f.player)).toEqual(original)
			expect(f.state.transactions + f.state.ids + f.state.loads + f.state.saves).toBe(0)
		end
	)

	it(
		"keeps due refund reservations in the committed view until authoritative preparation releases them",
		function()
			local f = fixture()
			f.data.craftingJobs = {
				due = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 12_000 } },
					receipt = {
						version = 1,
						recipeId = "retired_recipe",
						stationId = "base_station",
						craftingStationId = "basic_crafting_station",
						startedAt = 0,
						completesAt = 1,
						result = {
							definitionId = "elemental_sword",
							finishId = "fire",
							quantity = 1,
							instanceIds = { "due_output" },
						},
						paid = { gold = 50, materials = { fire_material = 12_000 } },
					},
				},
			}
			local before = copy(f.data)
			local view = getView(f.api, f.player)
			local expansion = assert(view.expansion, "Expected conservative quote")
			expect(expansion.canPurchase).toBe(false)
			expect(expansion.purchaseCode).toBe("MaterialCapacityTooSmall")
			expect(f.data).toEqual(before)
			expect(f.data.equipment.due_output).toBeNil()
			expect(f.state.transactions + f.state.ids).toBe(0)
			-- A mutation may legitimately differ after the shared due-job preparation commits.
			local transaction = fixture(copy(f.data), true)
			expect(transaction.expand.Expand(transaction.player, expandRequest(expansion, 0)).ok).toBe(
				true
			)
			expect(transaction.data.equipment.due_output).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
			local jobs = assert(transaction.data.craftingJobs, "Expected settled receipt")
			expect(jobs.due.status).toBe("Completed")
			expect(jobs.due.reservations).toEqual({ equipment = 0, materials = {} })
			expect(f.data).toEqual(before)
		end
	)

	it(
		"fails the whole view for unavailable profiles or malformed revision, schema, Base and resources",
		function()
			local cases: { { code: string, revision: number, change: (any) -> () } } = {
				{
					code = "InvalidTransaction",
					revision = -1,
					change = function(data)
						data.transactions = { revision = 0.5, receipts = {} }
					end,
				},
				{
					code = "UnsupportedVersion",
					revision = 0,
					change = function(data)
						data.version = 6
					end,
				},
				{
					code = "InvalidBaseState",
					revision = 0,
					change = function(data)
						data.base = false
					end,
				},
				{
					code = "InvalidBaseState",
					revision = 0,
					change = function(data)
						data.base.craftingStation = nil
					end,
				},
				{
					code = "InvalidBaseState",
					revision = 0,
					change = function(data)
						data.base.buildSlotUpgrades = 5
					end,
				},
				{
					code = "InvalidBaseState",
					revision = 0,
					change = function(data)
						data.base.shrines =
							{ first = shrine("first", 1), second = shrine("second", 1) }
					end,
				},
				{
					code = "InvalidCurrency",
					revision = 0,
					change = function(data)
						data.currency.gold = "100"
					end,
				},
				{
					code = "InvalidInventoryState",
					revision = 0,
					change = function(data)
						data.materials.fire_material.total = -1
					end,
				},
				{
					code = "InvalidReservations",
					revision = 0,
					change = function(data)
						data.craftingJobs = {
							legacy = {
								status = "Active",
								reservations = { equipment = -1, materials = {} },
							},
						}
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				case.change(f.data)
				local before = copy(f.data)
				expect(f.api.Get(f.player)).toEqual({
					ok = false,
					code = case.code,
					revision = case.revision,
				})
				expect(f.data).toEqual(before)
				expect(f.state.transactions + f.state.ids + f.state.loads + f.state.saves).toBe(0)
			end
			local f = fixture()
			f.state.loaded = false
			expect(f.api.Get(f.player)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			f.state.loaded = true
			f.data.transactions = nil
			expect(f.api.Get(f.player).revision).toBe(0)
			f.data.base.buildSlotUpgrades = 4
			local raw = f.data :: any
			raw.currency.gold = "bad"
			expect(f.api.Get(f.player)).toEqual({
				ok = false,
				code = "InvalidCurrency",
				revision = 0,
			})
		end
	)
end)
