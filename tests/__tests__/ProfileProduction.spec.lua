--!strict
-- ServerStorage/Tests/__tests__/ProfileProduction.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Template = require(ServerStorage.Databases.PlayerDataTemplate)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local Projection = require(ServerScriptService.Services.DataService.Projection)
local ProfileProduction = require(ServerScriptService.Services.ProductionService.ProfileProduction)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)

local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function profile(): Types.PlayerDoc
	local data = copy(Template)
	assert((ProfileSchema.Prepare(data, function()
		return "station"
	end, 0)), "[ProfileProduction.spec] Fixture preparation failed")
	data.mythlings.worker = {
		typeId = "mythling_0001",
		variantId = "default",
		claimedAt = 0,
		level = 1,
		xp = 0,
		pendingXp = 0,
	}
	data.base.shrines = {
		first = {
			id = "first",
			shrineId = "fire_shrine",
			buildSlotId = 1,
			level = 1,
			stored = 0,
			progress = 0,
			newWork = 0,
			workerIdsBySlot = { ["1"] = "worker" },
		},
	}
	return data
end

local function clock(data: Types.PlayerDoc): Types.ProductionClock
	return (assert(data.productionClock, "[ProfileProduction.spec] Expected clock"))
end

local function run(
	data: Types.PlayerDoc,
	now: number,
	boundary: ServerTypes.ProfileBoundary
): Types.TransactionResult
	local revision = Transactions.GetRevision(data)
	return Transactions.Run(data, {
		id = `{revision}:boundary`,
		expectedRevision = revision,
		operation = "Profile.Test",
		signature = "",
	}, function(draft)
		return ProfileProduction.Settle(draft, now, boundary)
	end, function()
		return true
	end)
end

local function earnings(data: Types.PlayerDoc): unknown
	return {
		mythlings = data.mythlings,
		shrines = data.base.shrines,
		lastAccruedAt = clock(data).lastAccruedAt,
		nextBatchAt = clock(data).nextBatchAt,
	}
end

describe("ProfileProduction session boundaries", function()
	it("initializes only session hints on Ready and retains the fixed earned schedule", function()
		local data = profile()
		expect(run(data, 0.25, "Ready").ok).toBe(true)
		expect(clock(data)).toEqual({
			lastAccruedAt = 0.25,
			nextBatchAt = 1,
			lastOnlineCheckpointAt = 0.25,
		})
		expect(data.mythlings.worker.pendingXp).toBe(0.25)
		expect(data.mythlings.worker.xp).toBe(0)
		expect(run(data, 0.25, "Ready").ok).toBe(true)
		expect(data.mythlings.worker.pendingXp).toBe(0.25)
	end)

	it(
		"matches uninterrupted earnings through checkpoints, clean release, JSON restore and rejoin",
		function()
			local expected, data = profile(), profile()
			expect((ShrineAccounting.SettleToDraft(expected, 2_000))).toBe(true)
			expect(run(data, 0, "Ready").ok).toBe(true)
			for _, time in { 30, 60, 119.75, 180.2 } do
				expect(run(data, time, "Checkpoint").ok).toBe(true)
			end
			expect(run(data, 200.75, "Release").ok).toBe(true)
			expect(clock(data).lastOnlineCheckpointAt).toBe(180.2)
			expect(clock(data).offlineSince).toBe(200.75)
			data = copy(data)
			expect((ProfileSchema.Prepare(data, function()
				error("must preserve Station")
			end, 2_000))).toBe(true)
			expect(run(data, 2_000, "Ready").ok).toBe(true)
			expect(earnings(data)).toEqual(earnings(expected))
			expect(clock(data).lastOnlineCheckpointAt).toBe(2_000)
			expect(clock(data).offlineSince).toBeNil()
		end
	)

	it(
		"uses lastAccruedAt after an unclean exit, never replaying from an older checkpoint",
		function()
			local expected, data = profile(), profile()
			expect(run(data, 30, "Ready").ok).toBe(true)
			expect((ShrineAccounting.SettleToDraft(data, 67.5))).toBe(true)
			expect(clock(data).lastOnlineCheckpointAt).toBe(30)
			data = copy(data)
			expect(run(data, 600, "Ready").ok).toBe(true)
			expect((ShrineAccounting.SettleToDraft(expected, 600))).toBe(true)
			expect(earnings(data)).toEqual(earnings(expected))
		end
	)

	it(
		"does not catch up full storage or unassigned intervals across session transitions",
		function()
			for _, full in { true, false } do
				local data = profile()
				local shrine = (assert(
					data.base.shrines,
					"[ProfileProduction.spec] Expected Shrines"
				)).first
				if full then
					shrine.stored = 300
				else
					shrine.workerIdsBySlot = {}
				end
				expect(run(data, 30, "Ready").ok).toBe(true)
				expect(run(data, 90, "Release").ok).toBe(true)
				expect(run(data, 90_000, "Ready").ok).toBe(true)
				expect(data.mythlings.worker.xp).toBe(0)
				expect(data.mythlings.worker.pendingXp).toBe(0)
				expect(clock(data).lastAccruedAt).toBe(90_000)
				expect(
					(assert(data.base.shrines, "[ProfileProduction.spec] Expected Shrines")).first.stored
				).toBe(if full then 300 else 0)
			end
		end
	)

	it(
		"resolves retained credit without a source Shrine and preserves inactive legacy records",
		function()
			local data = profile()
			data.base.shrines = {}
			data.mythlings.worker.pendingXp = 0.75
			data.mythlings.legacy =
				{ typeId = "prototype", variantId = "old", claimedAt = 9, level = 8, xp = 72 }
			local raw = data.mythlings.legacy :: any
			raw.luck = 7
			raw.traits = { "legacy_trait" }
			local legacy = copy(data.mythlings.legacy)
			data.craftingJobs = {
				held = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
				},
			}
			local jobs = copy(data.craftingJobs)
			expect(run(data, 100, "Ready").ok).toBe(true)
			expect(data.mythlings.worker.xp).toBe(0.75)
			expect(data.mythlings.worker.pendingXp).toBe(0)
			expect(data.mythlings.legacy).toEqual(legacy)
			expect(data.craftingJobs).toEqual(jobs)
		end
	)

	it("does not let a checkpoint or release turn a saved offline profile online", function()
		local data = profile()
		expect(run(data, 1, "Checkpoint").code).toBe("ProfileNotReady")
		expect(run(data, 1, "Release").code).toBe("ProfileNotReady")
		expect(run(data, 1, "Ready").ok).toBe(true)
		expect(run(data, 2, "Release").ok).toBe(true)
		local before = copy(earnings(data))
		expect(run(data, 3, "Release").code).toBe("ProfileNotReady")
		expect(run(data, 3, "Checkpoint").code).toBe("ProfileNotReady")
		expect(earnings(data)).toEqual(before)
		expect(clock(data).offlineSince).toBe(2)
	end)

	it("rolls back hints along with accounting on backdated or invalid time", function()
		local data = profile()
		expect(run(data, 30, "Ready").ok).toBe(true)
		local before = copy(earnings(data))
		for _, time in { 29, -1, math.huge, 0 / 0 } do
			expect(run(data, time, "Checkpoint").ok).toBe(false)
			expect(earnings(data)).toEqual(before)
			expect(clock(data).lastOnlineCheckpointAt).toBe(30)
		end
	end)

	it("does not publish private session hints", function()
		local data = profile()
		expect(run(data, 0, "Ready").ok).toBe(true)
		expect(run(data, 1, "Release").ok).toBe(true)
		expect(Projection.Build(data).productionClock).toBeNil()
	end)
end)

describe("optional schema-7 production session hints", function()
	it(
		"preserves absent, online and offline hints without awarding work during schema preparation",
		function()
			local cases: { { lastOnlineCheckpointAt: number?, offlineSince: number? } } = {
				{},
				{ lastOnlineCheckpointAt = 30 },
				{ lastOnlineCheckpointAt = 30, offlineSince = 60 },
			}
			for _, hints in cases do
				local data = profile()
				data.productionClock = {
					lastAccruedAt = 100,
					nextBatchAt = 101,
					lastOnlineCheckpointAt = hints.lastOnlineCheckpointAt,
					offlineSince = hints.offlineSince,
				}
				local before = copy(data)
				expect((ProfileSchema.Prepare(data, function()
					error("must preserve Station")
				end, 1_000))).toBe(true)
				expect(data).toEqual(before)
			end
		end
	)

	it("rejects partial, unordered or invalid hints without repairing earned work", function()
		local corruptions = {
			{ offlineSince = 60 },
			{ lastOnlineCheckpointAt = -1 },
			{ lastOnlineCheckpointAt = 101 },
			{ lastOnlineCheckpointAt = 50, offlineSince = 40 },
			{ lastOnlineCheckpointAt = 50, offlineSince = 101 },
			{ lastOnlineCheckpointAt = "50" },
			{ lastOnlineCheckpointAt = 50, offlineSince = "60" },
		}
		for _, hints in corruptions do
			local data = profile()
			local invalid: any = { lastAccruedAt = 100, nextBatchAt = 101 }
			for key, value in hints do
				invalid[key] = value
			end
			data.productionClock = invalid
			local before = copy(data)
			local ok, code = ProfileSchema.Prepare(data, function()
				error("must preserve Station")
			end, 1_000)
			expect(ok).toBe(false)
			expect(code).toBe("InvalidProductionClock")
			expect(ProfileProduction.Settle(data, 1_000, "Ready").code).toBe(
				"InvalidProductionClock"
			)
			expect((ShrineAccounting.SettleToDraft(data, 1_000))).toBe(false)
			expect(data).toEqual(before)
		end
	end)
end)
