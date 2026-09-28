--!strict
-- ServerStorage/Tests/__tests__/ProfileSchema.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
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
		"adds v5 state atomically while retaining all v4 progression and live table identities",
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
			local base, stands, jobs, receipts =
				data.base, data.base.stands, data.craftingJobs, data.transactions
			expect((ProfileSchema.Prepare(data, stationId))).toBe(true)
			expect(snapshot(data)).toEqual(expected)
			expect(data.base).toBe(base)
			expect(data.base.stands).toBe(stands)
			expect(data.craftingJobs).toBe(jobs)
			expect(data.transactions).toBe(receipts)
		end
	)

	it(
		"reuses existing Station identity, purchases, Shrines and opaque job links during upgrade",
		function()
			local data = oldData()
			data.base.buildSlotUpgrades = 3
			data.base.shrines = { kept = { id = "kept", shrineId = "fire_shrine" } }
			data.base.craftingStation =
				{ id = "retained-station", craftingStationId = "basic_crafting_station" }
			-- Future job fields are opaque to this schema addition and must not be reconstructed.
			local raw = snapshot(data)
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
			local expected = snapshot(data)
			expected.version = Configuration.schemaVersion
			expect((ProfileSchema.Prepare(data, neverGenerate))).toBe(true)
			expect(snapshot(data)).toEqual(expected)
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
		for _, version in { 0, 2, 3, 6 } do
			local data = oldData()
			data.version = version
			local before = snapshot(data)
			local ok, code = ProfileSchema.Prepare(data, neverGenerate)
			expect(ok).toBe(false)
			expect(code).toBe("UnsupportedVersion")
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
		"projects only client-safe derived Base status and preserves the legacy stand view",
		function()
			local data = oldData()
			data.base.stands["1"] = {}
			expect((ProfileSchema.Prepare(data, stationId))).toBe(true)
			local projection = Projection.Build(data)
			expect(projection.base.status).toEqual({
				usedShrineSlots = 0,
				unlockedShrineSlots = 2,
				maxShrineSlots = 6,
				craftingStation = { id = stationId(), craftingStationId = "basic_crafting_station" },
			})
			expect(projection.base.stands).toEqual(data.base.stands)
			expect(projection.base.shrines).toBeNil()
			projection.base.status.craftingStation.id = "client-change"
			expect((assert(data.base.craftingStation, "[ProfileSchema.spec] Expected Station")).id).toBe(
				stationId()
			)
			local saved = snapshot(data.base)
			expect(saved.unlockedShrineSlots).toBeNil()
			expect(saved.maxShrineSlots).toBeNil()
		end
	)
end)
