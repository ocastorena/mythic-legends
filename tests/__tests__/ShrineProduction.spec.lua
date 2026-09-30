--!strict
-- ServerStorage/Tests/__tests__/ShrineProduction.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local ShrineProduction = require(ServerScriptService.Services.ProductionService.ShrineProduction)
local ShrineCollector = require(ServerScriptService.Services.ProductionService.ShrineCollector)
local ProductionRequests =
	require(ServerScriptService.Services.ProductionService.ProductionRequests)
local RequestConfiguration = require(ReplicatedStorage.Shared.Configurations.ProductionRequests)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local afterEach = JestGlobals.afterEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local jest = JestGlobals.jest

local collectorModule = ServerScriptService.Services.ProductionService.ShrineCollector
local requestsModule = ServerScriptService.Services.ProductionService.ProductionRequests
local limiterModule = ServerScriptService.Infrastructure.RateLimiter
local remoteUtilModule = ServerScriptService.Infrastructure.RemoteUtil

type ProductionService = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	CollectShrine: (Player, Types.CollectShrineRequest) -> Types.TransactionResult,
}

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
		mutate: ServerTypes.ProfileMutation
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
			local outcome = mutate(draft, state.now)
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

local function serviceFixture()
	local root = Instance.new("Folder")
	table.insert(fixtureRoots, root)
	local state = {
		reads = 0,
		transactions = 0,
		registrations = 0,
		accessCalls = 0,
		admissions = {} :: { number },
		clears = {} :: { number },
	}
	local observed = {
		requests = nil :: ProductionRequests.Requests?,
		checkAccess = nil :: ShrineCollector.AccessCheck?,
		cleared = {} :: { RemoteFunction },
		accessPlayer = nil :: Player?,
		accessBase = nil :: Types.BaseRecord?,
		accessShrine = nil :: string?,
	}
	local remotes = {} :: { RemoteFunction }
	for _, name in { "GetStatus", "Collect", "CollectShrine" } do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = root
		table.insert(remotes, remote)
	end
	jest.mock(collectorModule, function()
		return {
			new = function(
				source: ShrineCollector.DataSource,
				clock: (() -> number)?,
				checkAccess: ShrineCollector.AccessCheck?
			): ShrineCollector.ShrineCollector
				observed.checkAccess = checkAccess
				return ShrineCollector.new(source, clock, checkAccess)
			end,
		}
	end)
	jest.mock(requestsModule, function()
		return {
			new = function(
				dependencies: ProductionRequests.Dependencies
			): ProductionRequests.Requests
				local requests = ProductionRequests.new(dependencies)
				observed.requests = requests
				return requests
			end,
		}
	end)
	jest.mock(limiterModule, function()
		return {
			new = function(burst: number, refill: number)
				if burst == 8 then
					expect(refill).toBe(3)
				else
					expect(burst).toBe(RequestConfiguration.requestBurst)
					expect(refill).toBe(RequestConfiguration.requestRefillPerSecond)
				end
				local real = RateLimiter.new(burst, refill)
				return {
					Allow = function(_self: unknown, player: Player): boolean
						table.insert(state.admissions, burst)
						return real:Allow(player)
					end,
					Forget = function(_self: unknown, player: Player)
						real:Forget(player)
					end,
					Clear = function()
						table.insert(state.clears, burst)
						real:Clear()
					end,
				}
			end,
		}
	end)
	jest.mock(remoteUtilModule, function()
		return {
			ClearServerHandler = function(remote: RemoteFunction)
				table.insert(observed.cleared, remote)
				RemoteUtil.ClearServerHandler(remote)
			end,
		}
	end)
	local service: ProductionService? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> ProductionService
		service = loadService(ServerScriptService.Services.ProductionService)
	end)
	local api = assert(service, "[ShrineProduction.spec] Expected isolated service")
	table.insert(stopServices, api.Stop)
	local context = (
		{
			Services = {
				DataService = {
					GetLoadedData = function(): Types.PlayerDoc?
						state.reads += 1
						return nil
					end,
					Transact = function(): Types.TransactionResult
						state.transactions += 1
						return { ok = false, code = "UnexpectedTransaction", revision = 0 }
					end,
					Update = function(): Types.TransactionResult
						state.transactions += 1
						return { ok = false, code = "UnexpectedUpdate", revision = 0 }
					end,
					RegisterProfileSettlement = function()
						state.registrations += 1
					end,
					Checkpoint = function(): Types.TransactionResult
						return { ok = false, code = "DataUnavailable", revision = 0 }
					end,
				},
				BaseService = {
					HasStand = function(): boolean
						return false
					end,
					CheckShrineAccess = function(
						player: Player,
						base: Types.BaseRecord,
						shrine: string
					): string?
						state.accessCalls += 1
						observed.accessPlayer, observed.accessBase, observed.accessShrine =
							player, base, shrine
						return "OutOfRange"
					end,
				},
			},
			Configurations = { Mythlings = Mythlings },
			Remotes = {
				Production = {
					GetStatus = remotes[1],
					Collect = remotes[2],
					CollectShrine = remotes[3],
				},
			},
		} :: unknown
	) :: ServerTypes.Context
	return {
		api = api,
		context = context,
		state = state,
		observed = observed,
		remotes = remotes,
		root = root,
	}
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
	jest.unmock(collectorModule)
	jest.unmock(requestsModule)
	jest.unmock(limiterModule)
	jest.unmock(remoteUtilModule)
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

describe("ProductionService Shrine command gates", function()
	it(
		"rejects impostors before admission and clears both independent budgets and every handler",
		function()
			local f = serviceFixture()
			local retained: ProductionRequests.Requests? = nil
			local function unavailable()
				for _, raw in
					{ { UserId = 1001, Parent = game:GetService("Players") }, f.root, false }
				do
					local player = (raw :: unknown) :: Player
					expect(
						f.api.CollectShrine(player, ({} :: unknown) :: Types.CollectShrineRequest)
					).toEqual({
						ok = false,
						code = "DataUnavailable",
						revision = 0,
					})
					local handler = retained
					if handler then
						expect(handler.CollectShrine(player, {})).toEqual({
							ok = false,
							code = "DataUnavailable",
							revision = 0,
						})
					end
				end
				expect(f.state.admissions).toEqual({})
				expect(f.state.reads + f.state.transactions + f.state.accessCalls).toBe(0)
			end
			unavailable()
			f.api.Init(f.context)
			retained = assert(f.observed.requests, "[ShrineProduction.spec] Expected handlers")
			unavailable()
			f.api.Start()
			f.api.Start()
			unavailable()
			f.api.Stop()
			f.api.Stop()
			unavailable()
			expect(f.observed.cleared).toEqual(f.remotes)
			expect(f.state.clears).toEqual({ 8, RequestConfiguration.requestBurst })
			expect(f.state.registrations).toBe(1)
		end
	)

	it(
		"injects production authorization with the exact caller, saved Base, and Shrine identity",
		function()
			local f = serviceFixture()
			f.api.Init(f.context)
			local checkAccess =
				assert(f.observed.checkAccess, "[ShrineProduction.spec] Expected access injection")
			local player = (table.freeze({}) :: unknown) :: Player
			local data = profile(1001)
			expect(checkAccess(player, data, "first")).toBe("OutOfRange")
			expect(f.observed.accessPlayer).toBe(player)
			expect(f.observed.accessBase).toBe(data.base)
			expect(f.observed.accessShrine).toBe("first")
			expect(f.state.accessCalls).toBe(1)
			expect(f.state.reads + f.state.transactions).toBe(0)
		end
	)

	it(
		"fails initialization before registering production when Shrine authorization is absent",
		function()
			local f = serviceFixture()
			local context = (f.context :: unknown) :: { Services: { [string]: unknown } }
			context.Services.BaseService = {
				HasStand = function(): boolean
					return false
				end,
			}
			expect(function()
				f.api.Init(f.context)
			end).toThrow()
			expect(f.state.registrations).toBe(0)
			expect(f.observed.checkAccess).toBeNil()
			expect(f.observed.requests).toBeNil()
		end
	)

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
		local reads, transactions = 0, 0
		local registered: ServerTypes.ProfileSettlement? = nil
		local request: Types.CollectShrineRequest = {
			requestId = "0:collect",
			expectedRevision = 0,
			shrineInstanceId = "first",
			expectedMaterialId = "fire_material",
		}
		local getStatus = Instance.new("RemoteFunction")
		getStatus.Parent = root
		local collect = Instance.new("RemoteFunction")
		collect.Parent = root
		local collectShrine = Instance.new("RemoteFunction")
		collectShrine.Parent = root
		local function expectUnavailable(value: unknown)
			local result = service.SettleShrines(value)
			expect(result.ok).toBe(false)
			expect(type(result.code)).toBe("string")
			expect(service.CollectShrine(value, request)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(updates).toBe(0)
			expect(reads).toBe(0)
			expect(transactions).toBe(0)
		end

		expectUnavailable(player)
		service.Init({
			Services = {
				DataService = {
					RegisterProfileSettlement = function(
						owner: string,
						settle: ServerTypes.ProfileSettlement
					)
						expect(owner).toBe("Production")
						registered = settle
					end,
					Checkpoint = function(): Types.TransactionResult
						return { ok = false, code = "DataUnavailable", revision = 0 }
					end,
					Update = function(): Types.TransactionResult
						updates += 1
						return { ok = false, code = "UnexpectedUpdate", revision = 0 }
					end,
					GetLoadedData = function(): Types.PlayerDoc?
						reads += 1
						return nil
					end,
					Transact = function(): Types.TransactionResult
						transactions += 1
						return { ok = false, code = "UnexpectedTransaction", revision = 0 }
					end,
				},
				BaseService = {
					HasStand = function(): boolean
						return false
					end,
					CheckShrineAccess = function(): string?
						error("Impostor must not reach Shrine access")
					end,
				},
			},
			Configurations = { Mythlings = Mythlings },
			Remotes = {
				Production = {
					GetStatus = getStatus,
					Collect = collect,
					CollectShrine = collectShrine,
				},
			},
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
		-- Reverse service shutdown stops Production before DataService releases profiles. Its
		-- registered pure hook must remain independent of disposed runtime command instances.
		local settle = assert(registered, "Expected Production profile hook")
		local data = profile(1001)
		expect(settle(data, 30, "Ready").ok).toBe(true)
		expect(settle(data, 45, "Release").ok).toBe(true)
		expect(
			(assert(data.productionClock, "[ShrineProduction.spec] Expected clock")).offlineSince
		).toBe(45)
	end)
end)
