--!strict
-- ServerStorage/Tests/__tests__/ProfileSchema.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local Types = require(ReplicatedStorage.Shared.Types)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Projection = require(ServerScriptService.Services.DataService.Projection)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function snapshot(value: unknown): any
	return HttpService:JSONDecode(HttpService:JSONEncode(value))
end

local function freshData(): Types.PlayerDoc
	return (snapshot(PlayerDataTemplate) :: unknown) :: Types.PlayerDoc
end

local function oldData(): Types.PlayerDoc
	local data = freshData()
	data.version = 4
	data.profile = { userId = 25, createdAt = 100, lastLoginAt = 200 }
	data.base.buildSlotUpgrades = nil
	data.base.shrines = nil
	return data
end

local function initializedData(version: number): Types.PlayerDoc
	local data = freshData()
	data.version = version
	data.profile = { userId = 25, createdAt = 100, lastLoginAt = 200 }
	data.base.craftingStation = {
		id = "retained-station",
		craftingStationId = "basic_crafting_station",
	}
	if version == Configuration.schemaVersion then
		data.productionClock = {
			lastAccruedAt = 1_000,
			nextBatchAt = 1_000 + Production.batchIntervalSeconds,
		}
	end
	return data
end

local function stationId(): string
	return "permanent-station-id"
end

local function neverGenerate(): string
	error("[ProfileSchema.spec] Must reuse the existing Station")
end

describe("MVP ProfileSchema", function()
	it("initializes unique free Stations before exposing each fresh profile", function()
		local first, second = freshData(), freshData()
		local counter = 0
		local function createId(): string
			counter += 1
			return `station-{counter}`
		end
		expect((ProfileSchema.Prepare(first, createId))).toBe(true)
		expect((ProfileSchema.Prepare(second, createId))).toBe(true)
		expect(counter).toBe(2)
		expect(first.base.craftingStation).toEqual({
			id = "station-1",
			craftingStationId = "basic_crafting_station",
		})
		expect(second.base.craftingStation).toEqual({
			id = "station-2",
			craftingStationId = "basic_crafting_station",
		})
		expect(first.base.buildSlotUpgrades).toBe(0)
		expect(first.base.shrines).toEqual({})
		expect(first.currency.gold).toBe(Configuration.startingGold)
		expect(first.materials).toEqual({})
		expect(PlayerDataTemplate.base.craftingStation).toBeNil()
	end)

	it(
		"grants one protected starter pair in place only after fresh preparation succeeds",
		function()
			local data = freshData()
			local equipment, loadout = data.equipment, data.combatLoadout
			expect((ProfileSchema.Prepare(data, stationId, 0))).toBe(true)
			expect(data.equipment).toBe(equipment)
			expect(data.combatLoadout).toBe(loadout)
			expect(data.equipment).toEqual({
				starter_wooden_sword = {
					definitionId = Configuration.starterSwordId,
					isStarterGrant = true,
				},
				starter_wooden_shield = {
					definitionId = Configuration.starterShieldId,
					isStarterGrant = true,
				},
			})
			expect(data.combatLoadout).toEqual({
				primaryWeaponInstanceId = "starter_wooden_sword",
				shieldInstanceId = "starter_wooden_shield",
			})
			local sword, shield = equipment.starter_wooden_sword, equipment.starter_wooden_shield
			local before = snapshot(data)
			expect((ProfileSchema.Prepare(data, neverGenerate, 100))).toBe(true)
			expect(snapshot(data)).toEqual(before)
			expect(equipment.starter_wooden_sword).toBe(sword)
			expect(equipment.starter_wooden_shield).toBe(shield)
			expect(PlayerDataTemplate.equipment).toEqual({})
			expect(PlayerDataTemplate.combatLoadout).toEqual({})
		end
	)

	it(
		"retains a pre-created Station and empty-work clock while finishing untouched defaults",
		function()
			local data = freshData()
			data.base.craftingStation =
				{ id = stationId(), craftingStationId = "basic_crafting_station" }
			data.productionClock = {
				lastAccruedAt = 50,
				nextBatchAt = 50 + Production.batchIntervalSeconds,
				lastOnlineCheckpointAt = 50,
				offlineSince = 50,
			}
			local station, clock = data.base.craftingStation, data.productionClock
			expect((ProfileSchema.Prepare(data, neverGenerate, 100))).toBe(true)
			expect(data.base.craftingStation).toBe(station)
			expect(data.productionClock).toBe(clock)
			expect(data.equipment.starter_wooden_sword.isStarterGrant).toBe(true)
			expect(data.equipment.starter_wooden_shield.isStarterGrant).toBe(true)
		end
	)

	it(
		"does not refill old starter data or empty slots before profile metadata is initialized",
		function()
			for _, removeSword in { false, true } do
				local data = freshData()
				data.equipment.starter_wooden_shield = {
					definitionId = Configuration.starterShieldId,
					isStarterGrant = true,
				}
				if not removeSword then
					data.equipment.starter_wooden_sword = {
						definitionId = Configuration.starterSwordId,
						isStarterGrant = true,
					}
				end
				local expectedEquipment = snapshot(data.equipment)
				expect((ProfileSchema.Prepare(data, stationId, 0))).toBe(true)
				expect(data.equipment).toEqual(expectedEquipment)
				expect(data.combatLoadout).toEqual({})
				local before = snapshot(data)
				expect((ProfileSchema.Prepare(data, neverGenerate, 50))).toBe(true)
				expect(snapshot(data)).toEqual(before)
			end
		end
	)

	it(
		"never reconstructs missing Equipment or a chosen empty slot for an established profile",
		function()
			for _, keepShield in { false, true } do
				local data = initializedData(Configuration.schemaVersion)
				if keepShield then
					data.equipment.starter_wooden_shield = {
						definitionId = Configuration.starterShieldId,
						isStarterGrant = true,
					}
					data.combatLoadout.shieldInstanceId = "starter_wooden_shield"
				end
				local equipment, loadout = data.equipment, data.combatLoadout
				local before = snapshot(data)
				expect((ProfileSchema.Prepare(data, neverGenerate, 1_100))).toBe(true)
				expect(snapshot(data)).toEqual(before)
				expect(data.equipment).toBe(equipment)
				expect(data.combatLoadout).toBe(loadout)
				local reloaded = (snapshot(data) :: unknown) :: Types.PlayerDoc
				expect((ProfileSchema.Prepare(reloaded, neverGenerate, 1_200))).toBe(true)
				expect(snapshot(reloaded)).toEqual(before)
			end
		end
	)

	it(
		"preserves ambiguous zero-sentinel state instead of interpreting it as a starter grant",
		function()
			local retainedStates: { (any) -> () } = {
				function(data)
					data.profile.userId = 25
				end,
				function(data)
					data.profile.createdAt = 1
				end,
				function(data)
					data.profile.lastLoginAt = 1
				end,
				function(data)
					data.currency.gold = Configuration.startingGold + 1
				end,
				function(data)
					data.currency.gold = Configuration.startingGold - 1
				end,
				function(data)
					data.materials.fire = { total = 1 }
				end,
				function(data)
					data.mythlings.retained = { typeId = "legacy", level = 2, xp = 1 }
				end,
				function(data)
					data.craftingJobs.legacy =
						{ status = "Completed", reservations = { equipment = 0, materials = {} } }
				end,
				function(data)
					data.base.stands["1"] = { retainedWork = 1 }
				end,
				function(data)
					data.base.buildSlotUpgrades = 1
				end,
				function(data)
					data.base.shrines.retained = {
						id = "retained",
						shrineId = "fire_shrine",
						buildSlotId = 1,
						level = 1,
						stored = 0,
						progress = 0,
						newWork = 0,
						workerIdsBySlot = {},
					}
				end,
				function(data)
					data.inventoryUpgrades.materials = 1
				end,
				function(data)
					data.inventoryUpgrades.mythlings = 1
				end,
				function(data)
					data.inventoryUpgrades.equipment = 1
				end,
				function(data)
					data.transactions.revision = 1
				end,
				function(data)
					data.transactions.receipts.retained = { futureData = 1 }
				end,
				function(data)
					data.inventoryUpgrades = nil
				end,
				function(data)
					data.transactions = nil
				end,
				function(data)
					data.craftingJobs = nil
				end,
				function(data)
					data.combatLoadout.primaryWeaponInstanceId = "retained-missing-item"
				end,
				function(data)
					data.equipment.legacy = { definitionId = "future-equipment" }
				end,
			}
			for _, mutate in retainedStates do
				local data = initializedData(Configuration.schemaVersion)
				data.profile = { userId = 0, createdAt = 0, lastLoginAt = 0 }
				mutate(data)
				local before = snapshot(data)
				expect((ProfileSchema.Prepare(data, neverGenerate, 1_100))).toBe(true)
				expect(snapshot(data)).toEqual(before)
			end
		end
	)

	it("does not grant defaults over unknown future or inactive retained fields", function()
		local paths = {
			{},
			{ "profile" },
			{ "currency" },
			{ "inventoryUpgrades" },
			{ "transactions" },
			{ "base" },
			{ "base", "craftingStation" },
			{ "productionClock" },
		}
		for _, path in paths do
			local raw = snapshot(initializedData(Configuration.schemaVersion))
			raw.profile = { userId = 0, createdAt = 0, lastLoginAt = 0 }
			local section = raw
			for _, key in path do
				section = section[key]
			end
			section.retainedFutureState = { earned = 1 }
			local data = (raw :: unknown) :: Types.PlayerDoc
			local before = snapshot(data)
			expect((ProfileSchema.Prepare(data, neverGenerate, 1_100))).toBe(true)
			expect(snapshot(data)).toEqual(before)
		end
		local data = freshData()
		data.consumables = {}
		expect((ProfileSchema.Prepare(data, stationId, 0))).toBe(true)
		expect(data.consumables).toEqual({})
		expect(data.equipment).toEqual({})
		expect(data.combatLoadout).toEqual({})
	end)

	it("leaves starter candidates ungranted when later schema validation fails", function()
		local data = freshData()
		data.productionClock = { lastAccruedAt = 1, nextBatchAt = 1 }
		local before = snapshot(data)
		local equipment, loadout = data.equipment, data.combatLoadout
		local ok, code = ProfileSchema.Prepare(data, stationId, 0)
		expect(ok).toBe(false)
		expect(code).toBe("InvalidProductionClock")
		expect(snapshot(data)).toEqual(before)
		expect(data.equipment).toBe(equipment)
		expect(data.combatLoadout).toBe(loadout)
		data.productionClock = nil
		expect((ProfileSchema.Prepare(data, stationId, 0))).toBe(true)
		expect(data.equipment.starter_wooden_sword.isStarterGrant).toBe(true)
	end)

	it(
		"adds current state atomically while retaining all v4 progression and live table identities",
		function()
			local data = oldData()
			data.currency.gold = 9876
			data.materials.fire = { total = 312 }
			data.inventoryUpgrades = { materials = 1, mythlings = 2, equipment = 1 }
			data.mythlings.kept = {
				typeId = "prototype",
				variantId = "default",
				claimedAt = 55,
				level = 8,
				xp = 72,
				standId = 1,
			}
			data.base.stands["1"] = {
				production = {
					lastAccruedAt = 200,
					materials = { fire = { stored = 20, progress = 0.75 } },
				},
			}
			data.craftingJobs = {
				pending = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire = 5 } },
				},
			}
			data.transactions = {
				revision = 7,
				receipts = {
					["6:kept"] = {
						expectedRevision = 6,
						operation = "Kept",
						signature = "retained",
						result = { ok = true, revision = 7, values = { gold = 9876 } },
					},
				},
			}
			local expected = snapshot(data)
			expected.version = Configuration.schemaVersion
			expected.base.buildSlotUpgrades = 0
			expected.base.shrines = {}
			expected.base.craftingStation =
				{ id = stationId(), craftingStationId = "basic_crafting_station" }
			expected.productionClock = {
				lastAccruedAt = 1_000,
				nextBatchAt = 1_000 + Production.batchIntervalSeconds,
			}
			local base, stands, jobs, receipts =
				data.base, data.base.stands, data.craftingJobs, data.transactions
			expect((ProfileSchema.Prepare(data, stationId, 1_000))).toBe(true)
			expect(snapshot(data)).toEqual(expected)
			expect(data.base).toBe(base)
			expect(data.base.stands).toBe(stands)
			expect(data.craftingJobs).toBe(jobs)
			expect(data.transactions).toBe(receipts)
		end
	)

	it("migrates saved Salennu identities while retaining earnings and canonical copies", function()
		for _, version in { 4, 5, 6, Configuration.schemaVersion } do
			local raw = snapshot(initializedData(version))
			raw.mythlings.saved_salennu = {
				typeId = "dragon",
				variantId = "regular",
				claimedAt = 55,
				standId = 1,
				level = 8,
				xp = 72,
				pendingXp = 0,
				luck = 77,
				traitIds = { "lucky", "insomniac" },
				futureEarnedState = { retained = 3 },
			}
			raw.mythlings.canonical_salennu = {
				typeId = "mythling_0001",
				variantId = "regular",
				claimedAt = 40,
				level = 9,
				xp = 42,
				pendingXp = 0.25,
			}
			raw.base.stands["1"] = {
				production = {
					lastAccruedAt = 200,
					materials = { crystal = { stored = 12, progress = 0.75, newWork = 0.25 } },
				},
			}
			local data = (raw :: unknown) :: Types.PlayerDoc
			local expected = snapshot(data)
			expected.version = Configuration.schemaVersion
			expected.mythlings.saved_salennu.typeId = "mythling_0001"
			expected.mythlings.saved_salennu.legacyPrototype = true
			if expected.productionClock == nil then
				expected.productionClock = {
					lastAccruedAt = 1_000,
					nextBatchAt = 1_000 + Production.batchIntervalSeconds,
				}
			end
			local owned, saved, canonical, stands =
				data.mythlings,
				data.mythlings.saved_salennu,
				data.mythlings.canonical_salennu,
				data.base.stands
			expect((ProfileSchema.Prepare(data, neverGenerate, 1_000))).toBe(true)
			expect(snapshot(data)).toEqual(expected)
			expect(data.mythlings).toBe(owned)
			expect(data.mythlings.saved_salennu).toBe(saved)
			expect(data.mythlings.canonical_salennu).toBe(canonical)
			expect(data.base.stands).toBe(stands)
			expect((ProfileSchema.Prepare(data, neverGenerate, 1_100))).toBe(true)
			expect(snapshot(data)).toEqual(expected)
		end
	end)

	it("leaves saved Salennu identity untouched when preparation rejects the profile", function()
		local data = initializedData(Configuration.schemaVersion)
		data.mythlings.saved_salennu = {
			typeId = "dragon",
			variantId = "regular",
			claimedAt = 55,
			standId = 1,
			level = 8,
			xp = 72,
		}
		data.productionClock = { lastAccruedAt = 1_000, nextBatchAt = 1_000 }
		local before, saved = snapshot(data), data.mythlings.saved_salennu
		local ok, problem = ProfileSchema.Prepare(data, neverGenerate, 1_100)
		expect(ok).toBe(false)
		expect(problem).toBe("InvalidProductionClock")
		expect(snapshot(data)).toEqual(before)
		expect(data.mythlings.saved_salennu).toBe(saved)
	end)

	it("upgrades an empty v5 Base without replacing any retained tables", function()
		local data = initializedData(5)
		local base = data.base
		local shrines = assert(data.base.shrines, "[ProfileSchema.spec] Expected Shrine map")
		local station = data.base.craftingStation
		local before = snapshot(data)
		before.version = Configuration.schemaVersion
		before.productionClock = {
			lastAccruedAt = 1_000,
			nextBatchAt = 1_000 + Production.batchIntervalSeconds,
		}

		expect((ProfileSchema.Prepare(data, neverGenerate, 1_000))).toBe(true)
		expect(snapshot(data)).toEqual(before)
		expect(data.base).toBe(base)
		expect(data.base.shrines).toBe(shrines)
		expect(data.base.craftingStation).toBe(station)
	end)

	it(
		"deterministically fills legacy Shrine fields while preserving records and opaque state",
		function()
			for _, version in { 4, 5 } do
				local data = initializedData(version)
				data.base.buildSlotUpgrades = 2
				local raw = snapshot(data)
				raw.base.shrines = {}
				-- Deliberately insert the lexically later missing record first.
				raw.base.shrines.zulu = {
					id = "zulu",
					shrineId = "air_shrine",
					futureLedger = { stored = 9 },
				}
				raw.base.shrines.fixed = {
					id = "fixed",
					shrineId = "water_shrine",
					buildSlotId = 2,
					level = 2,
				}
				raw.base.shrines.alpha = { id = "alpha", shrineId = "fire_shrine" }
				-- Future job fields are opaque to this migration and must not be reconstructed.
				raw.craftingJobs = {
					job = {
						stationInstanceId = "retained-station",
						deadline = 12345,
						finishId = "fire",
						status = "Active",
						reservations = { equipment = 1, materials = { fire = 5 } },
					},
				}
				data = (raw :: unknown) :: Types.PlayerDoc
				local shrines =
					assert(data.base.shrines, "[ProfileSchema.spec] Expected Shrine map")
				local alpha, fixed, zulu = shrines.alpha, shrines.fixed, shrines.zulu
				local jobs = data.craftingJobs

				expect((ProfileSchema.Prepare(data, neverGenerate))).toBe(true)
				expect(data.version).toBe(Configuration.schemaVersion)
				expect(data.base.shrines).toBe(shrines)
				local prepared =
					assert(data.base.shrines, "[ProfileSchema.spec] Expected prepared Shrine map")
				expect(prepared.alpha).toBe(alpha)
				expect(prepared.fixed).toBe(fixed)
				expect(prepared.zulu).toBe(zulu)
				expect(prepared.alpha.buildSlotId).toBe(1)
				expect(prepared.alpha.level).toBe(1)
				expect(prepared.fixed.buildSlotId).toBe(2)
				expect(prepared.fixed.level).toBe(2)
				expect(prepared.zulu.buildSlotId).toBe(3)
				expect(prepared.zulu.level).toBe(1)
				expect((prepared.zulu :: any).futureLedger).toEqual({ stored = 9 })
				expect(data.craftingJobs).toBe(jobs)
			end
		end
	)

	it("can retry an interrupted first initialization without regranting other defaults", function()
		local data = freshData()
		data.currency.gold = 77
		expect((ProfileSchema.Prepare(data, neverGenerate))).toBe(false)
		local reloaded = (snapshot(data) :: unknown) :: Types.PlayerDoc
		expect((ProfileSchema.Prepare(reloaded, stationId))).toBe(true)
		expect(reloaded.currency.gold).toBe(77)
		expect((ProfileSchema.Prepare(reloaded, neverGenerate))).toBe(true)
	end)

	it("rejects malformed profile metadata without throwing or changing Base state", function()
		local raw = snapshot(freshData())
		raw.profile = "invalid"
		local data = (raw :: unknown) :: Types.PlayerDoc
		local before = snapshot(data)
		local ok, code = ProfileSchema.Prepare(data, neverGenerate)
		expect(ok).toBe(false)
		expect(code).toBe("InvalidProfile")
		expect(snapshot(data)).toEqual(before)
	end)

	it("retains Station identity through repeat preparation and serialized reconnects", function()
		local data = freshData()
		expect((ProfileSchema.Prepare(data, stationId))).toBe(true)
		expect((ProfileSchema.Prepare(data, neverGenerate))).toBe(true)
		data.profile.createdAt = 100
		local reloaded = (snapshot(data) :: unknown) :: Types.PlayerDoc
		expect((ProfileSchema.Prepare(reloaded, neverGenerate))).toBe(true)
		expect(snapshot(reloaded)).toEqual(snapshot(data))
	end)

	it("rejects other namespaces' schemas and future versions without modifying them", function()
		for _, version in { 0, 2, 3, Configuration.schemaVersion + 1 } do
			local data = oldData()
			data.version = version
			local before = snapshot(data)
			local ok, code = ProfileSchema.Prepare(data, neverGenerate)
			expect(ok).toBe(false)
			expect(code).toBe("UnsupportedVersion")
			expect(snapshot(data)).toEqual(before)
		end
	end)

	it("rejects missing or invalid required Shrine fields in the current schema", function()
		local corruptions = {
			{ kept = { id = "kept", shrineId = "fire_shrine" } },
			{ kept = { id = "kept", shrineId = "fire_shrine", buildSlotId = 1 } },
			{ kept = { id = "kept", shrineId = "fire_shrine", level = 1 } },
			{ kept = { id = "kept", shrineId = "fire_shrine", buildSlotId = 0, level = 1 } },
			{ kept = { id = "kept", shrineId = "fire_shrine", buildSlotId = 1, level = 4 } },
		}

		for _, shrines in corruptions do
			local data = initializedData(Configuration.schemaVersion)
			local raw = snapshot(data)
			raw.base.shrines = shrines
			data = (raw :: unknown) :: Types.PlayerDoc
			local before = snapshot(data)

			local ok, code = ProfileSchema.Prepare(data, neverGenerate)
			expect(ok).toBe(false)
			expect(code).toBe("InvalidBase")
			expect(snapshot(data)).toEqual(before)
		end
	end)

	it("rejects conflicting or invalid explicit legacy Shrine state atomically", function()
		local corruptions = {
			{
				first = { id = "first", shrineId = "fire_shrine", buildSlotId = 1, level = 1 },
				second = { id = "second", shrineId = "water_shrine", buildSlotId = 1, level = 1 },
			},
			{
				locked = { id = "locked", shrineId = "earth_shrine", buildSlotId = 3, level = 1 },
			},
			{
				invalidLevel = {
					id = "invalidLevel",
					shrineId = "light_shrine",
					buildSlotId = 1,
					level = 4,
				},
			},
		}

		for _, shrines in corruptions do
			local data = initializedData(5)
			local raw = snapshot(data)
			raw.base.shrines = shrines
			data = (raw :: unknown) :: Types.PlayerDoc
			local before = snapshot(data)
			local ok, code = ProfileSchema.Prepare(data, neverGenerate)
			expect(ok).toBe(false)
			expect(code).toBe("InvalidBase")
			expect(snapshot(data)).toEqual(before)
		end
	end)

	it("does not repair a lost Station or silently reset malformed purchased state", function()
		local data = freshData()
		data.profile.userId = 25
		data.profile.createdAt = 100
		local before = snapshot(data)
		local ok, code = ProfileSchema.Prepare(data, stationId)
		expect(ok).toBe(false)
		expect(code).toBe("MissingStation")
		expect(snapshot(data)).toEqual(before)
		data = oldData()
		data.base.buildSlotUpgrades = -1
		before = snapshot(data)
		expect((ProfileSchema.Prepare(data, stationId))).toBe(false)
		expect(snapshot(data)).toEqual(before)
	end)

	it("leaves the original version and ledger untouched if identity generation fails", function()
		local data = oldData()
		local before = snapshot(data)
		expect((ProfileSchema.Prepare(data, neverGenerate))).toBe(false)
		expect(snapshot(data)).toEqual(before)
		expect((ProfileSchema.Prepare(data, function(): string
			return ""
		end))).toBe(false)
		expect(snapshot(data)).toEqual(before)
	end)

	it(
		"projects only allowlisted detached Shrine state and preserves the legacy stand view",
		function()
			local data = initializedData(5)
			data.base.stands["1"] = {}
			local raw = snapshot(data)
			raw.base.shrines = {
				kept = {
					id = "kept",
					shrineId = "dark_shrine",
					privateLedger = { stored = 99 },
				},
			}
			data = (raw :: unknown) :: Types.PlayerDoc
			expect((ProfileSchema.Prepare(data, neverGenerate))).toBe(true)
			local projection = Projection.Build(data)
			expect(projection.base.status).toEqual({
				usedShrineSlots = 1,
				unlockedShrineSlots = 2,
				maxShrineSlots = 6,
				craftingStation = {
					id = "retained-station",
					craftingStationId = "basic_crafting_station",
				},
			})
			expect(projection.base.stands).toEqual(data.base.stands)
			expect(projection.base.shrines).toEqual({
				kept = { id = "kept", shrineId = "dark_shrine", buildSlotId = 1, level = 1 },
			})
			expect(projection.base.shrines.kept.privateLedger).toBeNil()
			expect(projection.base.shrines.kept.stored).toBeNil()
			expect(projection.base.shrines.kept.progress).toBeNil()
			expect(projection.base.shrines.kept.newWork).toBeNil()
			expect(projection.base.shrines.kept.workerIdsBySlot).toBeNil()
			expect(projection.productionClock).toBeNil()
			projection.base.shrines.kept.level = 3
			expect(
				assert(data.base.shrines, "[ProfileSchema.spec] Expected saved Shrine map").kept.level
			).toBe(1)
			projection.base.status.craftingStation.id = "client-change"
			expect((assert(data.base.craftingStation, "[ProfileSchema.spec] Expected Station")).id).toBe(
				"retained-station"
			)
			local saved = snapshot(data.base)
			expect(saved.unlockedShrineSlots).toBeNil()
			expect(saved.maxShrineSlots).toBeNil()
		end
	)
end)
