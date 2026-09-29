--!strict
-- ServerStorage/Tests/__tests__/ShrineProduction.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local ShrineProduction = require(ServerScriptService.Services.ProductionService.ShrineProduction)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local afterEach = JestGlobals.afterEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local fixtureRoots: { Instance } = {}
local stopServices: { () -> () } = {}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function profile(userId: number): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return `station_{userId}`
	end, 0)
	assert(prepared, `[ShrineProduction.spec] Fixture preparation failed: {tostring(problem)}`)
	data.profile.userId = userId
	data.profile.createdAt = 100
	data.profile.lastLoginAt = 200
	data.mythlings.worker = {
		typeId = "mythling_0001",
		variantId = "retained_variant",
		claimedAt = 25,
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

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function fixture(clockOverride: (() -> number)?)
	-- The private transaction bridge treats Player as an ownership token; the service tests below
	-- exercise the real-instance lifecycle gate separately.
	local first = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local second = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
	local profiles: { [Player]: Types.PlayerDoc } =
		{ [first] = profile(1001), [second] = profile(1002) }
	local state = {
		now = 0,
		clockCalls = 0,
		updateCalls = 0,
		callbackCalls = 0,
		inCallback = false,
		available = true,
		active = true,
		loseSessionAfterCallback = false,
		operations = {} :: { string },
		players = {} :: { Player },
	}
	local function update(
		player: Player,
		operation: string,
		mutate: Transactions.Mutator
	): Types.TransactionResult
		state.updateCalls += 1
		table.insert(state.operations, operation)
		table.insert(state.players, player)
		local data = profiles[player]
		if not state.available or not data then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		local revision = Transactions.GetRevision(data)
		return Transactions.Run(data, {
			id = `{revision}:server-{state.updateCalls}`,
			expectedRevision = revision,
			operation = operation,
			signature = "server-authored",
		}, function(draft)
			state.inCallback = true
			state.callbackCalls += 1
			local outcome = mutate(draft)
			state.inCallback = false
			if state.loseSessionAfterCallback then
				state.active = false
			end
			return outcome
		end, function()
			return state.active
		end)
	end
	local api = ShrineProduction.new({ Update = update }, function(): number
		state.clockCalls += 1
		assert(
			state.inCallback,
			"[ShrineProduction.spec] Clock sampled outside the transaction callback"
		)
		return if clockOverride then clockOverride() else state.now
	end)
	return { first = first, second = second, profiles = profiles, state = state, api = api }
end

local function savedShrine(data: Types.PlayerDoc): Types.ShrineRecord
	return assert(data.base.shrines, "[ShrineProduction.spec] Expected Shrine map").first
end

afterEach(function()
	for _, stop in stopServices do
		pcall(stop)
	end
	table.clear(stopServices)
	for _, root in fixtureRoots do
		root:Destroy()
	end
	table.clear(fixtureRoots)
end)

describe("ShrineProduction.Settle", function()
	it("samples fractional server time once inside one correctly named Update", function()
		local f = fixture()
		f.state.now = 0.25
		local result = f.api.Settle(f.first)
		expect(result).toEqual({ ok = true, revision = 1, values = { settledAt = 0.25 } })
		expect(f.state.updateCalls).toBe(1)
		expect(f.state.callbackCalls).toBe(1)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.operations).toEqual({ "Production.SettleShrines" })
		expect(f.state.players).toEqual({ f.first })
		local data = f.profiles[f.first]
		expect(data.productionClock).toEqual({ lastAccruedAt = 0.25, nextBatchAt = 1 })
		expect(data.mythlings.worker.xp).toBe(0)
		expect(data.mythlings.worker.pendingXp).toBe(0.25)
		expect(savedShrine(data).newWork).toBeCloseTo(12 * 0.25 / 3_600)
	end)

	it("does not sample the clock when Update rejects an unavailable profile", function()
		local f = fixture()
		f.state.available = false
		local before = copy(f.profiles[f.first])
		local result = f.api.Settle(f.first)
		expect(result).toEqual({ ok = false, code = "DataUnavailable", revision = 0 })
		expect(f.state.updateCalls).toBe(1)
		expect(f.state.callbackCalls).toBe(0)
		expect(f.state.clockCalls).toBe(0)
		expect(f.profiles[f.first]).toEqual(before)
	end)

	it("settles only the selected player's loaded profile", function()
		local f = fixture()
		local secondBefore = copy(f.profiles[f.second])
		f.state.now = 1
		expect(f.api.Settle(f.first).ok).toBe(true)
		expect(f.profiles[f.first].mythlings.worker.xp).toBe(1)
		expect(f.profiles[f.second]).toEqual(secondBefore)
		local firstAfter = copy(f.profiles[f.first])
		f.state.now = 2
		expect(f.api.Settle(f.second).ok).toBe(true)
		expect(f.profiles[f.second].mythlings.worker.xp).toBe(2)
		expect(f.profiles[f.first]).toEqual(firstAfter)
		expect(f.state.players).toEqual({ f.first, f.second })
	end)

	it(
		"preserves earned state at a repeated timestamp despite separate Update revisions",
		function()
			local f = fixture()
			f.state.now = 1
			local first = f.api.Settle(f.first)
			local afterFirst = gameplay(f.profiles[f.first])
			local second = f.api.Settle(f.first)
			expect(first.revision).toBe(1)
			expect(second).toEqual({ ok = true, revision = 2, values = { settledAt = 1 } })
			expect(gameplay(f.profiles[f.first])).toEqual(afterFirst)
			expect(f.state.clockCalls).toBe(2)
			expect(f.state.updateCalls).toBe(2)
		end
	)

	it("preserves live accounting references through the shared transaction commit", function()
		local f = fixture()
		local data = f.profiles[f.first]
		local clock, base, shrines, shrine, worker =
			data.productionClock,
			data.base,
			data.base.shrines,
			savedShrine(data),
			data.mythlings.worker
		f.state.now = 1
		expect(f.api.Settle(f.first).ok).toBe(true)
		expect(data.productionClock).toBe(clock)
		expect(data.base).toBe(base)
		expect(data.base.shrines).toBe(shrines)
		expect(savedShrine(data)).toBe(shrine)
		expect(data.mythlings.worker).toBe(worker)
	end)

	for _, timestamp in { -1, math.huge, 0 / 0 } do
		it(
			`rejects invalid sampled time {tostring(timestamp)} without changing gameplay`,
			function()
				local f = fixture()
				f.state.now = timestamp
				local before = gameplay(f.profiles[f.first])
				local result = f.api.Settle(f.first)
				expect(result.ok).toBe(false)
				expect(type(result.code)).toBe("string")
				expect(result.revision).toBe(1)
				expect(result.values).toBeNil()
				expect(gameplay(f.profiles[f.first])).toEqual(before)
				expect(f.state.clockCalls).toBe(1)
			end
		)
	end

	it("rejects a backdated server sample without resetting the saved clock", function()
		local f = fixture()
		f.state.now = 2
		expect(f.api.Settle(f.first).ok).toBe(true)
		local before = gameplay(f.profiles[f.first])
		f.state.now = 1.5
		local result = f.api.Settle(f.first)
		expect(result.ok).toBe(false)
		expect(result.code).toBe("BackdatedChange")
		expect(gameplay(f.profiles[f.first])).toEqual(before)
	end)

	it("propagates adapter rejection without initializing missing earned-state fields", function()
		local f = fixture()
		f.profiles[f.first].mythlings.worker.pendingXp = nil
		local before = gameplay(f.profiles[f.first])
		f.state.now = 1
		local result = f.api.Settle(f.first)
		expect(result.ok).toBe(false)
		expect(result.code).toBe("IncompleteMythlingProgression")
		expect(result.revision).toBe(1)
		expect(gameplay(f.profiles[f.first])).toEqual(before)
	end)

	it("discards successful draft work if the player's session is lost before commit", function()
		local f = fixture()
		f.state.now = 300
		f.state.loseSessionAfterCallback = true
		local before = copy(f.profiles[f.first])
		local result = f.api.Settle(f.first)
		expect(result).toEqual({ ok = false, code = "DataUnavailable", revision = 0 })
		expect(f.state.clockCalls).toBe(1)
		expect(f.profiles[f.first]).toEqual(before)
	end)

	it(
		"lets the transaction reject throwing clocks without a partial settlement or receipt",
		function()
			local f = fixture(function(): number
				error("intentional clock failure")
			end)
			local before = copy(f.profiles[f.first])
			local result = f.api.Settle(f.first)
			expect(result).toEqual({ ok = false, code = "MutationFailed", revision = 0 })
			expect(f.profiles[f.first]).toEqual(before)
			expect(f.state.clockCalls).toBe(1)
		end
	)

	it("lets the transaction cancel yielding clocks without committing late work", function()
		local f = fixture(function(): number
			coroutine.yield()
			return 1
		end)
		local before = copy(f.profiles[f.first])
		local result = f.api.Settle(f.first)
		expect(result).toEqual({ ok = false, code = "MutationYielded", revision = 0 })
		expect(f.profiles[f.first]).toEqual(before)
		expect(f.state.clockCalls).toBe(1)
	end)
end)

describe("ProductionService.SettleShrines gate", function()
	it("rejects calls before startup, after stop, and for non-Player impostors", function()
		local root = Instance.new("Folder")
		root.Name = "ShrineProductionServiceFixture"
		root.Parent = script.Parent
		table.insert(fixtureRoots, root)
		local module = ServerScriptService.Services.ProductionService:Clone()
		module.Parent = root
		-- Dynamic require isolates this singleton service and its private children for the test.
		local loadService = require :: (ModuleScript) -> any
		local service = loadService(module)
		-- Studio's disposable runner cannot create engine Players (WritePlayer capability).
		-- Exercise lifecycle and impostor rejection here; actual membership needs playtesting.
		local player = { UserId = 1001, Parent = game:GetService("Players") }
		local updates = 0
		local getStatus = Instance.new("RemoteFunction")
		getStatus.Parent = root
		local collect = Instance.new("RemoteFunction")
		collect.Parent = root
		local function expectUnavailable(value: unknown)
			local result = service.SettleShrines(value)
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(updates).toBe(0)
		end

		expectUnavailable(player)
		service.Init({
			Services = {
				DataService = {
					Update = function(): Types.TransactionResult
						updates += 1
						return { ok = false, code = "UnexpectedUpdate", revision = 0 }
					end,
					GetLoadedData = function(): Types.PlayerDoc?
						return nil
					end,
				},
				BaseService = {
					HasStand = function(): boolean
						return false
					end,
				},
			},
			Configurations = { Mythlings = Mythlings },
			Remotes = { Production = { GetStatus = getStatus, Collect = collect } },
		})
		table.insert(stopServices, function()
			service.Stop()
		end)
		expectUnavailable(player)
		service.Start()
		expectUnavailable(player)
		expectUnavailable(nil)
		expectUnavailable(root)
		service.Stop()
		expectUnavailable(player)
	end)
end)
