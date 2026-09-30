--!strict
-- ServerStorage/Tests/__tests__/ShrineUpgradeOffers.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local ShrineUpgrades = require(ServerScriptService.Services.BaseService.ShrineUpgrades)
local ShrineUpgradePurchase =
	require(ServerScriptService.Services.BaseService.ShrineUpgradePurchase)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function fixture()
	local definitions: ShrineUpgrades.Metadata = {
		forms = { fire_form = { element = "Fire", baseYieldPerHour = 12 } },
		shrines = {},
	}
	local state: ShrineUpgrades.State = {
		lastAccruedAt = 100.25,
		nextBatchAt = 101.25,
		shrines = {},
		workers = { worker = { formId = "fire_form", level = 5, xp = 10, pendingXp = 0.5 } },
	}
	local resources: ShrineUpgrades.Resources = {
		gold = 20_000,
		materials = {},
		inventoryUpgrades = { materials = 2 },
		craftingJobs = {},
	}
	for _, element in ELEMENTS do
		local id = `{element}_shrine`
		local configured = Shrines[id]
		definitions.shrines[id] = {
			element = configured.element,
			materialId = configured.materialId,
			maxLevel = configured.maxLevel,
			levels = copy(configured.levels),
		}
		state.shrines[`owned_{element}`] = {
			shrineId = id,
			level = 1,
			stored = 17,
			progress = 0.5,
			newWork = 0.25,
			workerIdsBySlot = if element == "fire" then { ["1"] = "worker" } else {},
		}
		resources.materials[configured.materialId] = { total = 5_000 }
	end
	return { state = state, resources = resources, definitions = definitions }
end

local function quote(offer: Types.ShrineUpgradeOffer, id: string): ShrineUpgrades.Request
	return {
		shrineInstanceId = id,
		expectedLevel = offer.expectedLevel,
		expectedMaterialId = offer.materialId,
		expectedGoldCost = offer.goldCost,
		expectedMaterialQuantity = offer.materialQuantity,
	}
end

describe("Shrine upgrade offers", function()
	it(
		"quotes both sequential upgrades for all six elements and agrees with the paid reducer",
		function()
			for _, element in ELEMENTS do
				for currentLevel = 1, 2 do
					local f = fixture()
					local id = `owned_{element}`
					f.state.shrines[id].level = currentLevel
					local beforeState, beforeResources = copy(f.state), copy(f.resources)
					local offer, problem =
						ShrineUpgrades.ReadOffer(f.state, f.resources, id, f.definitions)
					expect(problem).toBeNil()
					local row = assert(offer, "[ShrineUpgradeOffers.spec] Expected offer")
					expect(row).toEqual({
						expectedLevel = currentLevel,
						level = currentLevel + 1,
						materialId = `{element}_material`,
						goldCost = if currentLevel == 1 then 1_000 else 15_000,
						materialQuantity = if currentLevel == 1 then 400 else 4_000,
						ownedMaterialQuantity = 5_000,
						workerSlots = currentLevel + 1,
						storageCapacity = if currentLevel == 1 then 1_200 else 3_600,
						canUpgrade = true,
					})
					local result, upgradeError = ShrineUpgrades.Upgrade(
						f.state,
						f.resources,
						f.state.lastAccruedAt,
						quote(row, id),
						f.definitions
					)
					expect(upgradeError).toBeNil()
					local upgraded =
						assert(result, "[ShrineUpgradeOffers.spec] Expected matching upgrade")
					expect(upgraded.level).toBe(row.level)
					expect(upgraded.goldSpent).toBe(row.goldCost)
					expect(upgraded.materialsSpent).toBe(row.materialQuantity)
					expect(upgraded.production.lastAccruedAt).toBe(f.state.lastAccruedAt)
					expect(upgraded.production.shrines[id].stored).toBe(17)
					expect(f.state).toEqual(beforeState)
					expect(f.resources).toEqual(beforeResources)
				end
			end
		end
	)

	it(
		"reads frozen state and returns detached scalar quotes without moving earned work",
		function()
			local f = fixture()
			local before = copy(f)
			FreezeUtil.DeepFreeze(f.state)
			FreezeUtil.DeepFreeze(f.resources)
			FreezeUtil.DeepFreeze(f.definitions)
			local offer =
				assert(ShrineUpgrades.ReadOffer(f.state, f.resources, "owned_fire", f.definitions))
			offer.goldCost = 1
			offer.storageCapacity = 1
			local again =
				assert(ShrineUpgrades.ReadOffer(f.state, f.resources, "owned_fire", f.definitions))
			expect(again.goldCost).toBe(1_000)
			expect(again.storageCapacity).toBe(1_200)
			expect(f).toEqual(before)
		end
	)

	it("reports terminal levels without inventing a fourth-level quote", function()
		for _, element in ELEMENTS do
			local f = fixture()
			f.state.shrines[`owned_{element}`].level = 3
			local offer, problem =
				ShrineUpgrades.ReadOffer(f.state, f.resources, `owned_{element}`, f.definitions)
			expect(offer).toBeNil()
			expect(problem).toBe("MaxLevel")
		end
	end)

	it(
		"keeps shortages in an offer and never treats stored output or refund reservations as payment",
		function()
			for _, scenario in { "gold", "materials", "absent" } do
				local f = fixture()
				if scenario == "gold" then
					f.resources.gold = 999
				elseif scenario == "materials" then
					f.resources.materials.fire_material.total = 399
				else
					f.resources.materials.fire_material = nil
				end
				f.state.shrines.owned_fire.stored = 300
				f.resources.craftingJobs = {
					legacy = {
						status = "Active",
						reservations = { equipment = 1, materials = { fire_material = 400 } },
					},
				}
				local before = copy(f)
				local offer, problem =
					ShrineUpgrades.ReadOffer(f.state, f.resources, "owned_fire", f.definitions)
				expect(problem).toBeNil()
				local row = assert(offer, "[ShrineUpgradeOffers.spec] Expected shortage quote")
				expect(row.canUpgrade).toBe(false)
				expect(row.upgradeCode).toBe(
					if scenario == "gold" then "InsufficientGold" else "InsufficientMaterials"
				)
				expect(row.ownedMaterialQuantity).toBe(
					if scenario == "absent" then 0 elseif scenario == "materials" then 399 else 5_000
				)
				local result, code = ShrineUpgrades.Upgrade(
					f.state,
					f.resources,
					f.state.lastAccruedAt,
					quote(row, "owned_fire"),
					f.definitions
				)
				expect(result).toBeNil()
				expect(code).toBe(row.upgradeCode)
				expect(f).toEqual(before)
			end
		end
	)

	it(
		"fails closed on malformed accounting, full-path configuration, resources, and selections",
		function()
			local cases: {
				{
					code: string,
					change: (
						ShrineUpgrades.State,
						ShrineUpgrades.Resources,
						ShrineUpgrades.Metadata
					) -> (),
				}
			} =
				{
					{
						code = "InvalidState",
						change = function(state)
							state.nextBatchAt = state.lastAccruedAt
						end,
					},
					{
						code = "InvalidShrine",
						change = function(state)
							state.shrines.owned_fire.progress = 1
						end,
					},
					{
						code = "InvalidUpgradeConfiguration",
						change = function(_state, _resources, metadata)
							metadata.shrines.fire_shrine.levels[3] = nil
						end,
					},
					{
						code = "InvalidUpgradeConfiguration",
						change = function(_state, _resources, metadata)
							metadata.shrines.fire_shrine.levels[2].upgradeCost =
								{ gold = -1, materialQuantity = 400 }
						end,
					},
					{
						code = "InvalidUpgradeConfiguration",
						change = function(_state, _resources, metadata)
							metadata.shrines.fire_shrine.levels[2].capacity = 300
						end,
					},
					{
						code = "InvalidCurrency",
						change = function(_state, resources)
							resources.gold = 0 / 0
						end,
					},
					{
						code = "InvalidInventoryState",
						change = function(_state, resources)
							resources.materials.fire_material.total = -1
						end,
					},
					{
						code = "InvalidInventoryUpgrade",
						change = function(_state, resources)
							resources.inventoryUpgrades = { materials = 0.5 }
						end,
					},
					{
						code = "InvalidReservations",
						change = function(_state, resources)
							resources.craftingJobs = {
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
				case.change(f.state, f.resources, f.definitions)
				local offer, problem =
					ShrineUpgrades.ReadOffer(f.state, f.resources, "owned_fire", f.definitions)
				expect(offer).toBeNil()
				expect(problem).toBe(case.code)
			end
			local f = fixture()
			local missing, missingCode =
				ShrineUpgrades.ReadOffer(f.state, f.resources, "missing", f.definitions)
			expect(missing).toBeNil()
			expect(missingCode).toBe("ShrineNotOwned")
			local invalid, invalidCode =
				ShrineUpgrades.ReadOffer(f.state, f.resources, "", f.definitions)
			expect(invalid).toBeNil()
			expect(invalidCode).toBe("InvalidRequest")
			local configured, configurationError = ShrineUpgrades.ReadOffer(
				f.state,
				f.resources,
				"owned_fire",
				f.definitions,
				{ batchIntervalSeconds = 0, baseXpPerSecond = 1 }
			)
			expect(configured).toBeNil()
			expect(configurationError).toBe("InvalidConfiguration")
		end
	)

	it(
		"uses canonical accounting metadata in the purchase adapter without writing the profile",
		function()
			local data: Types.PlayerDoc = copy(PlayerDataTemplate)
			assert(ProfileSchema.Prepare(data, function()
				return "offer_station"
			end, 0))
			data.currency.gold = 1_000
			data.materials.fire_material = { total = 400 }
			data.base.shrines = {
				owned = {
					id = "owned",
					shrineId = "fire_shrine",
					buildSlotId = 1,
					level = 1,
					stored = 3,
					progress = 0.5,
					newWork = 0.25,
					workerIdsBySlot = {},
				},
			}
			local before = copy(data)
			local snapshot, snapshotError = ShrineAccounting.ReadSnapshot(data)
			expect(snapshotError).toBeNil()
			local read = assert(snapshot, "[ShrineUpgradeOffers.spec] Expected canonical snapshot")
			local offer, problem =
				ShrineUpgradePurchase.ReadOffer(data, read.state, read.metadata, "owned")
			expect(problem).toBeNil()
			local row = assert(offer, "[ShrineUpgradeOffers.spec] Expected canonical quote")
			expect(row.canUpgrade).toBe(true)
			expect(row.goldCost).toBe(1_000)
			expect(row.materialQuantity).toBe(400)
			expect(row.materialId).toBe("fire_material")
			expect(row.workerSlots).toBe(2)
			expect(row.storageCapacity).toBe(1_200)
			expect(data).toEqual(before)
		end
	)
end)
