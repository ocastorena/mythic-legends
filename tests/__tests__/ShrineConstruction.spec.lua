--!strict
-- ServerStorage/Tests/__tests__/ShrineConstruction.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Bases = require(ReplicatedStorage.Shared.Configurations.Bases)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineConstruction = require(ServerScriptService.Services.BaseService.ShrineConstruction)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local SHRINE_IDS = {
	"fire_shrine",
	"water_shrine",
	"earth_shrine",
	"air_shrine",
	"light_shrine",
	"dark_shrine",
}

local function copy(value: any): any
	return HttpService:JSONDecode(HttpService:JSONEncode(value))
end

local function gameplaySnapshot(data: Types.PlayerDoc): any
	local result = copy(data)
	result.transactions = nil
	return result
end

local function freshData(gold: number?): Types.PlayerDoc
	local data = (copy(PlayerDataTemplate) :: unknown) :: Types.PlayerDoc
	data.currency.gold = gold or 100
	data.materials = {}
	data.mythlings = {}
	data.base.stands = {}
	data.base.buildSlotUpgrades = 0
	data.base.shrines = {}
	data.base.craftingStation = {
		id = "station_123",
		craftingStationId = Bases.craftingStationId,
	}
	data.productionClock = {
		lastAccruedAt = 1_000,
		nextBatchAt = 1_000 + Production.batchIntervalSeconds,
	}
	return data
end

local function buildRequest(
	revision: number,
	token: string,
	shrineId: string,
	expectedGoldCost: number?
): Types.BuildShrineRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineId = shrineId,
		expectedGoldCost = if expectedGoldCost == nil then 100 else expectedGoldCost,
	}
end

local function shrineCount(data: Types.PlayerDoc): number
	local shrines = assert(data.base.shrines, "[ShrineConstruction.spec] Expected Shrine map")
	local count = 0
	for _ in shrines do
		count += 1
	end
	return count
end

local function fixture(data: Types.PlayerDoc?, generatedIds: { string }?)
	local player = (table.freeze({}) :: unknown) :: Player
	local state = {
		data = data or freshData(),
		generatedIds = generatedIds or {},
		generated = 0,
		active = true,
	}
	local dataSource: ShrineConstruction.DataSource = {
		GetLoadedData = function(_player: Player): Types.PlayerDoc?
			return if state.active then state.data else nil
		end,
		Transact = function(_player: Player, request, mutate)
			return Transactions.Run(state.data, request, function(draft)
				return mutate(draft, 0)
			end, function()
				return state.active
			end)
		end,
	}
	local api = ShrineConstruction.new(dataSource, function(): string
		state.generated += 1
		return state.generatedIds[state.generated] or `generated_{state.generated}`
	end)
	return { player = player, state = state, dataSource = dataSource, api = api }
end

describe("ShrineConstruction", function()
	it(
		"builds every configured Shrine for 100 Gold at level 1 without Materials or Mythlings",
		function()
			for index, shrineId in SHRINE_IDS do
				local instanceId = `shrine_instance_{index}`
				local f = fixture(freshData(100), { instanceId })
				local definition = assert(
					Shrines[shrineId],
					"[ShrineConstruction.spec] Expected configured Shrine"
				)
				expect(definition.buildGoldCost).toBe(100)
				expect(definition.initialLevel).toBe(1)

				local result = f.api.Build(
					f.player,
					buildRequest(0, `definition-{index}`, shrineId, definition.buildGoldCost)
				)

				expect(result).toEqual({
					ok = true,
					values = {
						shrineInstanceId = instanceId,
						shrineId = shrineId,
						buildSlotId = 1,
						level = 1,
						goldSpent = 100,
					},
					revision = 1,
				})
				expect(f.state.data.currency.gold).toBe(0)
				expect(f.state.data.materials).toEqual({})
				expect(f.state.data.mythlings).toEqual({})

				local shrines = assert(
					f.state.data.base.shrines,
					"[ShrineConstruction.spec] Expected Shrine map"
				)
				local record = shrines[instanceId]
				expect(record).toEqual({
					id = instanceId,
					shrineId = shrineId,
					buildSlotId = 1,
					level = 1,
					stored = 0,
					progress = 0,
					newWork = 0,
					workerIdsBySlot = {},
				})
				expect(getmetatable(record)).toBeNil()
				local encoded, json = pcall(function()
					return HttpService:JSONEncode(record)
				end)
				expect(encoded).toBe(true)
				expect(HttpService:JSONDecode(json :: string)).toEqual(record)
				local documentEncoded, documentJson = pcall(function()
					return HttpService:JSONEncode(f.state.data)
				end)
				expect(documentEncoded).toBe(true)
				expect(HttpService:JSONDecode(documentJson :: string)).toEqual(f.state.data)
			end
		end
	)

	it("requires exactly the four public request fields before starting a transaction", function()
		local requiredFields = { "requestId", "expectedRevision", "shrineId", "expectedGoldCost" }
		for index, field in requiredFields do
			local f = fixture()
			local raw: { [string]: any } = buildRequest(0, `missing-{index}`, "fire_shrine") :: any
			raw[field] = nil
			local before = copy(f.state.data)

			local result = f.api.Build(f.player, raw :: any)

			expect(result).toEqual({ ok = false, code = "InvalidRequest", revision = 0 })
			expect(f.state.data).toEqual(before)
			expect(f.state.generated).toBe(0)
		end

		local f = fixture()
		local raw: { [string]: any } = buildRequest(0, "extra", "fire_shrine") :: any
		raw.extra = true
		local before = copy(f.state.data)
		expect(f.api.Build(f.player, raw :: any)).toEqual({
			ok = false,
			code = "InvalidRequest",
			revision = 0,
		})
		expect(f.state.data).toEqual(before)
	end)

	it("allows duplicate elements and enforces the canonical two starting slots", function()
		local data = freshData(300)
		data.base.stands["legacy"] = {}
		local f = fixture(data, { "fire_one", "fire_two", "must_not_generate" })

		local first = f.api.Build(f.player, buildRequest(0, "first-fire", "fire_shrine"))
		local second = f.api.Build(f.player, buildRequest(1, "second-fire", "fire_shrine"))
		local full = f.api.Build(f.player, buildRequest(2, "third-fire", "fire_shrine"))

		expect(first.ok).toBe(true)
		expect(second.ok).toBe(true)
		expect(assert(first.values, "[ShrineConstruction.spec] Expected first values").buildSlotId).toBe(
			1
		)
		expect(
			assert(second.values, "[ShrineConstruction.spec] Expected second values").buildSlotId
		).toBe(2)
		expect(full).toEqual({ ok = false, code = "BaseFull", revision = 3 })
		expect(f.state.data.currency.gold).toBe(100)
		expect(shrineCount(f.state.data)).toBe(2)
		local shrines = assert(
			f.state.data.base.shrines,
			"[ShrineConstruction.spec] Expected duplicate Shrine map"
		)
		expect(shrines.fire_one.shrineId).toBe("fire_shrine")
		expect(shrines.fire_two.shrineId).toBe("fire_shrine")
		expect(shrines.fire_one.workerIdsBySlot).never.toBe(shrines.fire_two.workerIdsBySlot)
		expect(shrines.fire_one.workerIdsBySlot).toEqual({})
		expect(shrines.fire_two.workerIdsBySlot).toEqual({})
		expect(f.state.generated).toBe(2)
	end)

	it("supports all six purchased slots before reporting the expanded Base full", function()
		local data = freshData(700)
		data.base.buildSlotUpgrades = 4
		local generatedIds = {
			"expanded_one",
			"expanded_two",
			"expanded_three",
			"expanded_four",
			"expanded_five",
			"expanded_six",
			"must_not_generate",
		}
		local f = fixture(data, generatedIds)

		for index, shrineId in SHRINE_IDS do
			local result =
				f.api.Build(f.player, buildRequest(index - 1, `expanded-{index}`, shrineId))
			expect(result.ok).toBe(true)
			expect(
				assert(result.values, "[ShrineConstruction.spec] Expected expanded build values").buildSlotId
			).toBe(index)
		end
		local full = f.api.Build(f.player, buildRequest(6, "expanded-full", "fire_shrine"))

		expect(full).toEqual({ ok = false, code = "BaseFull", revision = 7 })
		expect(shrineCount(data)).toBe(6)
		expect(data.currency.gold).toBe(100)
		expect(f.state.generated).toBe(6)
	end)

	it("automatically fills the lowest free Shrine-slot hole", function()
		local data = freshData(200)
		data.base.shrines = {
			existing = {
				id = "existing",
				shrineId = "earth_shrine",
				buildSlotId = 2,
				level = 1,
			},
		}
		local f = fixture(data, { "fills_hole" })

		local result = f.api.Build(f.player, buildRequest(0, "fill-hole", "water_shrine"))

		expect(result.ok).toBe(true)
		expect(
			assert(result.values, "[ShrineConstruction.spec] Expected result values").buildSlotId
		).toBe(1)
		local shrines =
			assert(data.base.shrines, "[ShrineConstruction.spec] Expected hole-filled Shrine map")
		expect(shrines.fills_hole.buildSlotId).toBe(1)
		expect(shrines.existing.buildSlotId).toBe(2)
	end)

	it("replays the same build with the same instance ID and without charging twice", function()
		local f = fixture(freshData(200), { "stable_shrine", "must_not_generate" })
		local request = buildRequest(0, "replay", "air_shrine")

		local first = f.api.Build(f.player, request)
		local replayGeneratorCalls = 0
		local replayApi = ShrineConstruction.new(f.dataSource, function(): string
			replayGeneratorCalls += 1
			error("a replay must never generate a second instance ID")
		end)
		local replay = replayApi.Build(f.player, request)

		expect(first.ok).toBe(true)
		expect(replay.ok).toBe(true)
		expect(replay.replayed).toBe(true)
		expect(replay.revision).toBe(first.revision)
		local replayValues =
			assert(replay.values, "[ShrineConstruction.spec] Expected replay values")
		local firstValues =
			assert(first.values, "[ShrineConstruction.spec] Expected original values")
		expect(replayValues.shrineInstanceId).toBe(firstValues.shrineInstanceId)
		expect(replayValues.shrineInstanceId).toBe("stable_shrine")
		expect(f.state.data.currency.gold).toBe(100)
		expect(shrineCount(f.state.data)).toBe(1)
		expect(f.state.generated).toBe(1)
		expect(replayGeneratorCalls).toBe(0)
	end)

	it("rejects reused request IDs when the Shrine or quoted cost changes", function()
		local f = fixture(freshData(300), { "original_shrine", "must_not_generate" })
		local original = buildRequest(0, "conflict", "fire_shrine")
		expect(f.api.Build(f.player, original).ok).toBe(true)

		local changedShrine = f.api.Build(f.player, buildRequest(0, "conflict", "water_shrine"))
		local changedCost = f.api.Build(f.player, buildRequest(0, "conflict", "fire_shrine", 99))

		expect(changedShrine).toEqual({ ok = false, code = "RequestConflict", revision = 1 })
		expect(changedCost).toEqual({ ok = false, code = "RequestConflict", revision = 1 })
		expect(f.state.data.currency.gold).toBe(200)
		expect(shrineCount(f.state.data)).toBe(1)
		expect(f.state.generated).toBe(1)
	end)

	it("commits only one of two same-revision requests for the last free slot", function()
		local data = freshData(300)
		data.base.shrines = {
			existing = {
				id = "existing",
				shrineId = "earth_shrine",
				buildSlotId = 1,
				level = 1,
			},
		}
		local f = fixture(data, { "winner", "must_not_generate" })

		local winner = f.api.Build(f.player, buildRequest(0, "winner", "light_shrine"))
		local stale = f.api.Build(f.player, buildRequest(0, "loser", "dark_shrine"))

		expect(winner.ok).toBe(true)
		expect(
			assert(winner.values, "[ShrineConstruction.spec] Expected winning build values").buildSlotId
		).toBe(2)
		expect(stale).toEqual({ ok = false, code = "StaleRevision", revision = 1 })
		expect(data.currency.gold).toBe(200)
		expect(shrineCount(data)).toBe(2)
		expect(f.state.generated).toBe(1)
	end)

	it(
		"replays a saved old-price receipt before current price validation or ID generation",
		function()
			local data = freshData(200)
			local historicalRequest = buildRequest(0, "historical-price", "fire_shrine", 99)
			expect(Shrines.fire_shrine.buildGoldCost).toBe(100)
			expect(historicalRequest.expectedGoldCost).never.toBe(Shrines.fire_shrine.buildGoldCost)
			local signature =
				`shrineId={#historicalRequest.shrineId}:{historicalRequest.shrineId};expectedGoldCost={historicalRequest.expectedGoldCost}`
			local seeded = Transactions.Run(data, {
				id = historicalRequest.requestId,
				expectedRevision = historicalRequest.expectedRevision,
				operation = "Base.BuildShrine",
				signature = signature,
			}, function(draft)
				local shrines =
					assert(draft.base.shrines, "[ShrineConstruction.spec] Expected Shrines")
				draft.currency.gold -= historicalRequest.expectedGoldCost
				shrines.historical_shrine = {
					id = "historical_shrine",
					shrineId = historicalRequest.shrineId,
					buildSlotId = 1,
					level = 1,
				}
				return {
					ok = true,
					values = {
						shrineInstanceId = "historical_shrine",
						shrineId = historicalRequest.shrineId,
						buildSlotId = 1,
						level = 1,
						goldSpent = historicalRequest.expectedGoldCost,
					},
				}
			end, function()
				return true
			end)
			expect(seeded.ok).toBe(true)
			expect(data.currency.gold).toBe(101)
			data = (copy(data) :: unknown) :: Types.PlayerDoc
			expect(HttpService:JSONDecode(HttpService:JSONEncode(data))).toEqual(data)

			local generatorCalls = 0
			local dataSource: ShrineConstruction.DataSource = {
				GetLoadedData = function(_player: Player): Types.PlayerDoc?
					return data
				end,
				Transact = function(_player: Player, request, mutate)
					return Transactions.Run(data, request, function(draft)
						return mutate(draft, 0)
					end, function()
						return true
					end)
				end,
			}
			local api = ShrineConstruction.new(dataSource, function(): string
				generatorCalls += 1
				error("historical replay must bypass ID generation")
			end)
			local player = (table.freeze({}) :: unknown) :: Player

			local replay = api.Build(player, historicalRequest)

			expect(replay).toEqual({
				ok = true,
				values = {
					shrineInstanceId = "historical_shrine",
					shrineId = "fire_shrine",
					buildSlotId = 1,
					level = 1,
					goldSpent = 99,
				},
				revision = 1,
				replayed = true,
			})
			expect(generatorCalls).toBe(0)
			expect(data.currency.gold).toBe(101)
			expect(shrineCount(data)).toBe(1)
		end
	)

	it("does not generate IDs for invalid definitions, currency, or insufficient Gold", function()
		local unknown = fixture(freshData(200), { "must_not_generate" })
		local unknownBefore = gameplaySnapshot(unknown.state.data)
		expect(unknown.api.Build(unknown.player, buildRequest(0, "unknown", "unknown_shrine"))).toEqual({
			ok = false,
			code = "InvalidShrine",
			revision = 1,
		})
		expect(gameplaySnapshot(unknown.state.data)).toEqual(unknownBefore)
		expect(unknown.state.generated).toBe(0)

		local invalidCurrencyData = freshData(200)
		invalidCurrencyData.currency.gold = -1
		local invalidCurrency = fixture(invalidCurrencyData, { "must_not_generate" })
		local currencyBefore = gameplaySnapshot(invalidCurrency.state.data)
		expect(
			invalidCurrency.api.Build(
				invalidCurrency.player,
				buildRequest(0, "invalid-currency", "fire_shrine")
			)
		).toEqual({ ok = false, code = "InvalidCurrency", revision = 1 })
		expect(gameplaySnapshot(invalidCurrency.state.data)).toEqual(currencyBefore)
		expect(invalidCurrency.state.generated).toBe(0)

		local poor = fixture(freshData(99), { "must_not_generate" })
		local poorBefore = gameplaySnapshot(poor.state.data)
		expect(poor.api.Build(poor.player, buildRequest(0, "poor", "fire_shrine"))).toEqual({
			ok = false,
			code = "InsufficientGold",
			revision = 1,
		})
		expect(gameplaySnapshot(poor.state.data)).toEqual(poorBefore)
		expect(poor.state.generated).toBe(0)
	end)

	it("rolls back when instance-ID generation errors or yields", function()
		local failing = fixture(freshData(200))
		local failingBefore = copy(failing.state.data)
		local failingCalls = 0
		local failingApi = ShrineConstruction.new(failing.dataSource, function(): string
			failingCalls += 1
			error("intentional generator failure")
		end)

		expect(failingApi.Build(failing.player, buildRequest(0, "generator-error", "fire_shrine"))).toEqual({
			ok = false,
			code = "MutationFailed",
			revision = 0,
		})
		expect(failing.state.data).toEqual(failingBefore)
		expect(failingCalls).toBe(1)

		local yielding = fixture(freshData(200))
		local yieldingBefore = copy(yielding.state.data)
		local yieldingCalls = 0
		local yieldingApi = ShrineConstruction.new(yielding.dataSource, function(): string
			yieldingCalls += 1
			coroutine.yield()
			return "late_id"
		end)

		expect(
			yieldingApi.Build(yielding.player, buildRequest(0, "generator-yield", "fire_shrine"))
		).toEqual({ ok = false, code = "MutationYielded", revision = 0 })
		expect(yielding.state.data).toEqual(yieldingBefore)
		expect(yieldingCalls).toBe(1)
	end)

	it("rejects stale revisions and changed prices without allocating or charging", function()
		local stale = fixture(freshData(200), { "must_not_generate" })
		local staleBefore = gameplaySnapshot(stale.state.data)
		expect(stale.api.Build(stale.player, buildRequest(1, "stale", "light_shrine"))).toEqual({
			ok = false,
			code = "StaleRevision",
			revision = 0,
		})
		expect(gameplaySnapshot(stale.state.data)).toEqual(staleBefore)
		expect(stale.state.generated).toBe(0)

		local changed = fixture(freshData(200), { "must_not_generate" })
		local changedBefore = gameplaySnapshot(changed.state.data)
		expect(
			changed.api.Build(changed.player, buildRequest(0, "changed-price", "light_shrine", 99))
		).toEqual({ ok = false, code = "PriceChanged", revision = 1 })
		expect(gameplaySnapshot(changed.state.data)).toEqual(changedBefore)
		expect(changed.state.generated).toBe(0)
	end)

	it("rolls back a build against invalid Base state", function()
		local data = freshData(200)
		data.base.buildSlotUpgrades = -1
		local before = gameplaySnapshot(data)
		local f = fixture(data, { "must_not_generate" })

		local result = f.api.Build(f.player, buildRequest(0, "invalid-base", "dark_shrine"))

		expect(result).toEqual({ ok = false, code = "InvalidBaseState", revision = 1 })
		expect(gameplaySnapshot(data)).toEqual(before)
		expect(data.currency.gold).toBe(200)
		expect(shrineCount(data)).toBe(0)
		expect(f.state.generated).toBe(0)
	end)

	it("rejects generated IDs that collide with the Station or an existing Shrine", function()
		local stationCollision = freshData(200)
		local station = assert(
			stationCollision.base.craftingStation,
			"[ShrineConstruction.spec] Expected Station"
		)
		local stationFixture = fixture(stationCollision, { station.id })
		local stationBefore = gameplaySnapshot(stationCollision)

		expect(
			stationFixture.api.Build(
				stationFixture.player,
				buildRequest(0, "station-collision", "fire_shrine")
			)
		).toEqual({ ok = false, code = "InstanceIdConflict", revision = 1 })
		expect(gameplaySnapshot(stationCollision)).toEqual(stationBefore)

		local shrineCollision = freshData(200)
		shrineCollision.base.shrines = {
			occupied = {
				id = "occupied",
				shrineId = "water_shrine",
				buildSlotId = 1,
				level = 1,
			},
		}
		local shrineFixture = fixture(shrineCollision, { "occupied" })
		local shrineBefore = gameplaySnapshot(shrineCollision)

		expect(
			shrineFixture.api.Build(
				shrineFixture.player,
				buildRequest(0, "shrine-collision", "water_shrine")
			)
		).toEqual({ ok = false, code = "InstanceIdConflict", revision = 1 })
		expect(gameplaySnapshot(shrineCollision)).toEqual(shrineBefore)
	end)

	it("preserves prototype stands, the permanent Station, and unrelated saved state", function()
		local data = freshData(200)
		data.base.stands["1"] = {
			production = {
				lastAccruedAt = 123,
				materials = { fire = { stored = 4, progress = 0.25 } },
			},
		}
		data.materials.fire = { total = 7 }
		data.mythlings.legacy = {
			typeId = "legacy_type",
			variantId = "regular",
			claimedAt = 50,
			level = 4,
			xp = 25,
		}

		local stands = data.base.stands
		local stand = stands["1"]
		local station =
			assert(data.base.craftingStation, "[ShrineConstruction.spec] Expected Station")
		local materials = data.materials
		local material = data.materials.fire
		local mythlings = data.mythlings
		local mythling = data.mythlings.legacy
		local profile = data.profile
		local clock = data.productionClock
		local equipment = data.equipment
		local loadout = data.combatLoadout
		local preserved = copy({
			stands = data.base.stands,
			station = data.base.craftingStation,
			profile = data.profile,
			materials = data.materials,
			mythlings = data.mythlings,
			equipment = data.equipment,
			inventoryUpgrades = data.inventoryUpgrades,
			craftingJobs = data.craftingJobs,
			combatLoadout = data.combatLoadout,
			productionClock = data.productionClock,
		})
		local f = fixture(data, { "preserving_build" })

		expect(f.api.Build(f.player, buildRequest(0, "preserve", "earth_shrine")).ok).toBe(true)

		expect(data.base.stands).toBe(stands)
		expect(data.base.stands["1"]).toBe(stand)
		expect(data.base.craftingStation).toBe(station)
		expect(data.materials).toBe(materials)
		expect(data.materials.fire).toBe(material)
		expect(data.mythlings).toBe(mythlings)
		expect(data.mythlings.legacy).toBe(mythling)
		expect(data.profile).toBe(profile)
		expect(data.productionClock).toBe(clock)
		expect(data.equipment).toBe(equipment)
		expect(data.combatLoadout).toBe(loadout)
		expect(copy({
			stands = data.base.stands,
			station = data.base.craftingStation,
			profile = data.profile,
			materials = data.materials,
			mythlings = data.mythlings,
			equipment = data.equipment,
			inventoryUpgrades = data.inventoryUpgrades,
			craftingJobs = data.craftingJobs,
			combatLoadout = data.combatLoadout,
			productionClock = data.productionClock,
		})).toEqual(preserved)
		expect(data.currency.gold).toBe(100)
		expect(
			assert(data.base.shrines, "[ShrineConstruction.spec] Expected preserved Shrine map").preserving_build
		).toEqual({
			id = "preserving_build",
			shrineId = "earth_shrine",
			buildSlotId = 1,
			level = 1,
			stored = 0,
			progress = 0,
			newWork = 0,
			workerIdsBySlot = {},
		})
	end)
end)
