--!strict
-- ServerStorage/Tests/__tests__/BaseServiceView.spec

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local RequestConfiguration = require(ReplicatedStorage.Shared.Configurations.BaseRequests)
local BaseView = require(ServerScriptService.Services.BaseService.BaseView)
local BaseRequests = require(ServerScriptService.Services.BaseService.BaseRequests)
local ShrineView = require(ServerScriptService.Services.BaseService.ShrineView)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
local ShrineUpgradePurchase =
	require(ServerScriptService.Services.BaseService.ShrineUpgradePurchase)
local ShrineRemoval = require(ServerScriptService.Services.BaseService.ShrineRemoval)
local ShrineConstruction = require(ServerScriptService.Services.BaseService.ShrineConstruction)
local BaseExpansionPurchase =
	require(ServerScriptService.Services.BaseService.BaseExpansionPurchase)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local viewModule = ServerScriptService.Services.BaseService.BaseView
local playersModule = ServerScriptService.Infrastructure.PlayerUtil
local remoteModule = ServerScriptService.Infrastructure.RemoteUtil
local requestsModule = ServerScriptService.Services.BaseService.BaseRequests
local constructionModule = ServerScriptService.Services.BaseService.ShrineConstruction
local expansionModule = ServerScriptService.Services.BaseService.BaseExpansionPurchase
local accessModule = ServerScriptService.Services.BaseService.BaseAccess
local shrineViewModule = ServerScriptService.Services.BaseService.ShrineView
local shrineWorkersModule = ServerScriptService.Services.BaseService.ShrineWorkers
local shrineUpgradeModule = ServerScriptService.Services.BaseService.ShrineUpgradePurchase
local shrineRemovalModule = ServerScriptService.Services.BaseService.ShrineRemoval
local shrineAccessModule = ServerScriptService.Services.BaseService.ShrineAccess
local limiterModule = ServerScriptService.Infrastructure.RateLimiter
local cleanup: { () -> () } = {}
type AccessCheck = (Player, Types.PlayerDoc) -> string?
type ShrineAccessCheck = (Player, Types.PlayerDoc, string) -> string?

type Service = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	GetBase: (Player) -> Types.BaseViewResult,
	GetShrine: (Player, Types.GetShrineRequest) -> Types.ShrineViewResult,
	BuildShrine: (Player, Types.BuildShrineRequest) -> Types.TransactionResult,
	ExpandBase: (Player, Types.ExpandBaseRequest) -> Types.TransactionResult,
	AssignShrineWorker: (Player, Types.AssignShrineWorkerRequest) -> Types.TransactionResult,
	RemoveShrineWorker: (Player, Types.RemoveShrineWorkerRequest) -> Types.TransactionResult,
	UpgradeShrine: (Player, Types.UpgradeShrineRequest) -> Types.TransactionResult,
	DismantleShrine: (Player, Types.DismantleShrineRequest) -> Types.TransactionResult,
	CheckShrineAccess: (Player, Types.BaseRecord, string) -> string?,
}

local function fixture()
	local state = {
		reads = 0,
		transactions = 0,
		loads = 0,
		factories = 0,
		viewCalls = 0,
		requestFactories = 0,
		admissions = 0,
		accessChecks = 0,
		shrineAccessChecks = 0,
		shrineViewFactories = 0,
		shrineWorkerFactories = 0,
		shrineUpgradeFactories = 0,
		shrineRemovalFactories = 0,
		canonicalLimiterFactories = 0,
		legacyLimiterFactories = 0,
		canonicalLimiterClears = 0,
		legacyLimiterClears = 0,
		observations = 0,
		observationCleanups = 0,
		loaded = nil :: Types.PlayerDoc?,
		reader = nil :: BaseView.BaseView?,
		shrineReader = nil :: ShrineView.ShrineView?,
		requests = nil :: BaseRequests.Requests?,
		requestDependencies = nil :: BaseRequests.Dependencies?,
		viewGuard = nil :: AccessCheck?,
		buildGuard = nil :: AccessCheck?,
		expandGuard = nil :: AccessCheck?,
		shrineViewGuard = nil :: ShrineAccessCheck?,
		shrineWorkerGuard = nil :: ShrineAccessCheck?,
		shrineUpgradeGuard = nil :: ShrineAccessCheck?,
		shrineRemovalGuard = nil :: ShrineAccessCheck?,
		cleared = {} :: { RemoteFunction },
	}
	local root = Instance.new("Folder")
	local template = Instance.new("Model")
	template.Name = "BaseLevel1"
	template.Parent = root
	local arena = Instance.new("Part")
	arena.Parent = root
	local place, remove = Instance.new("RemoteFunction"), Instance.new("RemoteFunction")
	place.Parent, remove.Parent = root, root
	local get, build, expand =
		Instance.new("RemoteFunction"),
		Instance.new("RemoteFunction"),
		Instance.new("RemoteFunction")
	get.Name, build.Name, expand.Name = "GetBase", "BuildShrine", "ExpandBase"
	get.Parent, build.Parent, expand.Parent = root, root, root
	local shrineGet, shrineAssign, shrineRemove, shrineUpgrade, shrineDismantle =
		Instance.new("RemoteFunction"),
		Instance.new("RemoteFunction"),
		Instance.new("RemoteFunction"),
		Instance.new("RemoteFunction"),
		Instance.new("RemoteFunction")
	shrineGet.Name, shrineAssign.Name, shrineRemove.Name, shrineUpgrade.Name, shrineDismantle.Name =
		"GetShrine", "AssignShrineWorker", "RemoveShrineWorker", "UpgradeShrine", "DismantleShrine"
	for _, remote in { shrineGet, shrineAssign, shrineRemove, shrineUpgrade, shrineDismantle } do
		remote.Parent = root
	end
	table.insert(cleanup, function()
		root:Destroy()
	end)
	local source = {
		GetLoadedData = function(_player: Player): Types.PlayerDoc?
			state.reads += 1
			return state.loaded
		end,
		Load = function(): boolean
			state.loads += 1
			error("Base view admission must not initiate loading")
		end,
		Transact = function(): Types.TransactionResult
			state.transactions += 1
			return { ok = false, code = "UnexpectedTransaction", revision = 0 }
		end,
	}
	jest.mock(viewModule, function()
		return {
			new = function(
				dataSource: BaseView.DataSource,
				checkAccess: AccessCheck?
			): BaseView.BaseView
				expect(dataSource).toBe(source)
				state.factories += 1
				state.viewGuard = checkAccess
				local real = BaseView.new(dataSource, checkAccess)
				local reader = {
					Get = function(player: Player): Types.BaseViewResult
						state.viewCalls += 1
						return real.Get(player)
					end,
				}
				state.reader = reader
				return reader
			end,
		}
	end)
	jest.mock(constructionModule, function()
		return {
			ReadOffer = ShrineConstruction.ReadOffer,
			new = function(
				dataSource: ShrineConstruction.DataSource,
				makeId: (() -> string)?,
				checkAccess: AccessCheck?
			): ShrineConstruction.ShrineConstruction
				expect(dataSource).toBe(source)
				expect(makeId).toBeNil()
				state.buildGuard = checkAccess
				return ShrineConstruction.new(dataSource, makeId, checkAccess)
			end,
		}
	end)
	jest.mock(expansionModule, function()
		return {
			ReadOffer = BaseExpansionPurchase.ReadOffer,
			new = function(
				dataSource: BaseExpansionPurchase.DataSource,
				checkAccess: AccessCheck?
			): BaseExpansionPurchase.BaseExpansionPurchase
				expect(dataSource).toBe(source)
				state.expandGuard = checkAccess
				return BaseExpansionPurchase.new(dataSource, checkAccess)
			end,
		}
	end)
	jest.mock(requestsModule, function()
		return {
			new = function(dependencies: BaseRequests.Dependencies): BaseRequests.Requests
				state.requestFactories += 1
				state.requestDependencies = dependencies
				local handlers = BaseRequests.new(dependencies)
				state.requests = handlers
				return handlers
			end,
		}
	end)
	jest.mock(shrineViewModule, function()
		return {
			new = function(
				dataSource: ShrineView.DataSource,
				checkAccess: ShrineAccessCheck?
			): ShrineView.ShrineView
				expect(dataSource).toBe(source)
				state.shrineViewFactories += 1
				state.shrineViewGuard = checkAccess
				local reader = ShrineView.new(dataSource, checkAccess)
				state.shrineReader = reader
				return reader
			end,
		}
	end)
	jest.mock(shrineWorkersModule, function()
		return {
			new = function(
				dataSource: ShrineWorkers.DataSource,
				clock: (() -> number)?,
				checkAccess: ShrineAccessCheck?
			): ShrineWorkers.ShrineWorkers
				expect(dataSource).toBe(source)
				expect(clock).toBeNil()
				state.shrineWorkerFactories += 1
				state.shrineWorkerGuard = checkAccess
				return ShrineWorkers.new(dataSource, clock, checkAccess)
			end,
		}
	end)
	jest.mock(shrineUpgradeModule, function()
		return {
			ReadOffer = ShrineUpgradePurchase.ReadOffer,
			new = function(
				dataSource: ShrineUpgradePurchase.DataSource,
				clock: (() -> number)?,
				checkAccess: ShrineAccessCheck?
			): ShrineUpgradePurchase.ShrineUpgradePurchase
				expect(dataSource).toBe(source)
				expect(clock).toBeNil()
				state.shrineUpgradeFactories += 1
				state.shrineUpgradeGuard = checkAccess
				return ShrineUpgradePurchase.new(dataSource, clock, checkAccess)
			end,
		}
	end)
	jest.mock(shrineRemovalModule, function()
		return {
			new = function(
				dataSource: ShrineRemoval.DataSource,
				clock: (() -> number)?,
				checkAccess: ShrineAccessCheck?
			): ShrineRemoval.ShrineRemoval
				expect(dataSource).toBe(source)
				expect(clock).toBeNil()
				state.shrineRemovalFactories += 1
				state.shrineRemovalGuard = checkAccess
				return ShrineRemoval.new(dataSource, clock, checkAccess)
			end,
		}
	end)
	jest.mock(shrineAccessModule, function()
		return {
			Check = function(): string?
				state.shrineAccessChecks += 1
				return "OutOfRange"
			end,
		}
	end)
	jest.mock(accessModule, function()
		return {
			Check = function(): string?
				state.accessChecks += 1
				return "OutOfRange"
			end,
		}
	end)
	jest.mock(limiterModule, function()
		return {
			new = function(burst: number, refill: number)
				local isCanonical = burst == RequestConfiguration.requestBurst
				if isCanonical then
					expect(refill).toBe(RequestConfiguration.requestRefillPerSecond)
					state.canonicalLimiterFactories += 1
				else
					expect(burst).toBe(6)
					expect(refill).toBe(2)
					state.legacyLimiterFactories += 1
				end
				local real = RateLimiter.new(burst, refill)
				return {
					Allow = function(_self: unknown, player: Player): boolean
						state.admissions += 1
						return real:Allow(player)
					end,
					Forget = function(_self: unknown, player: Player)
						real:Forget(player)
					end,
					Clear = function()
						if isCanonical then
							state.canonicalLimiterClears += 1
						else
							state.legacyLimiterClears += 1
						end
						real:Clear()
					end,
				}
			end,
		}
	end)
	jest.mock(playersModule, function()
		return {
			OnPlayer = function(_onAdded: (Player, () -> boolean) -> (), owner: Trove.Trove)
				-- Exercise service lifecycle without dispatching live joins or creating Players.
				state.observations += 1
				owner:Add(function()
					state.observationCleanups += 1
				end)
			end,
		}
	end)
	jest.mock(remoteModule, function()
		return {
			ClearServerHandler = function(remote: RemoteFunction)
				table.insert(state.cleared, remote)
				RemoteUtil.ClearServerHandler(remote)
			end,
		}
	end)
	local service: Service? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> Service
		service = loadService(ServerScriptService.Services.BaseService)
	end)
	local api = assert(service, "[BaseServiceView.spec] Expected isolated service")
	table.insert(cleanup, api.Stop)
	-- This partial context supplies every dependency exercised by Init/Start, not live joins.
	local context = (
		{
			Instances = {
				Arena = arena,
				BaseIslands = root,
				Bases = root,
				MythlingAssets = root,
				BaseAssets = root,
			},
			Configurations = { Mythlings = Mythlings },
			Remotes = {
				Base = {
					PlaceMythling = place,
					RemoveMythling = remove,
					GetBase = get,
					BuildShrine = build,
					ExpandBase = expand,
					GetShrine = shrineGet,
					AssignShrineWorker = shrineAssign,
					RemoveShrineWorker = shrineRemove,
					UpgradeShrine = shrineUpgrade,
					DismantleShrine = shrineDismantle,
				},
			},
			Services = { DataService = source, InventoryService = {}, ProductionService = {} },
		} :: unknown
	) :: ServerTypes.Context
	return {
		api = api,
		context = context,
		state = state,
		root = root,
		remotes = {
			place,
			remove,
			get,
			build,
			expand,
			shrineGet,
			shrineAssign,
			shrineRemove,
			shrineUpgrade,
			shrineDismantle,
		},
	}
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(viewModule)
	jest.unmock(playersModule)
	jest.unmock(remoteModule)
	jest.unmock(requestsModule)
	jest.unmock(constructionModule)
	jest.unmock(expansionModule)
	jest.unmock(accessModule)
	jest.unmock(shrineViewModule)
	jest.unmock(shrineWorkersModule)
	jest.unmock(shrineUpgradeModule)
	jest.unmock(shrineRemovalModule)
	jest.unmock(shrineAccessModule)
	jest.unmock(limiterModule)
end)

describe("BaseService view and purchase admission", function()
	it(
		"rejects forged identities before reader, load, or transaction work throughout its lifetime",
		function()
			local f = fixture()
			local get, build, expand = f.api.GetBase, f.api.BuildShrine, f.api.ExpandBase
			local request: Types.BuildShrineRequest = {
				requestId = "0:build",
				expectedRevision = 0,
				shrineId = "fire_shrine",
				expectedGoldCost = 100,
			}
			local function rejected(raw: unknown)
				local player = raw :: Player
				local unavailable = { ok = false, code = "DataUnavailable", revision = 0 }
				expect(get(player)).toEqual(unavailable)
				expect(f.api.GetShrine(player, { shrineInstanceId = "selected" })).toEqual(
					unavailable
				)
				expect(build(player, request)).toEqual(unavailable)
				expect(expand(player, ({} :: unknown) :: Types.ExpandBaseRequest)).toEqual(
					unavailable
				)
				expect(
					f.api.AssignShrineWorker(
						player,
						({} :: unknown) :: Types.AssignShrineWorkerRequest
					)
				).toEqual(unavailable)
				expect(
					f.api.RemoveShrineWorker(
						player,
						({} :: unknown) :: Types.RemoveShrineWorkerRequest
					)
				).toEqual(unavailable)
				expect(f.api.UpgradeShrine(player, ({} :: unknown) :: Types.UpgradeShrineRequest)).toEqual(
					unavailable
				)
				expect(
					f.api.DismantleShrine(player, ({} :: unknown) :: Types.DismantleShrineRequest)
				).toEqual(unavailable)
				expect(
					f.api.CheckShrineAccess(player, ({} :: unknown) :: Types.BaseRecord, "selected")
				).toBe("DataUnavailable")
				local handlers = f.state.requests
				if handlers then
					expect(handlers.GetBase(player)).toEqual(unavailable)
					expect(handlers.BuildShrine(player, request)).toEqual(unavailable)
					expect(handlers.ExpandBase(player, {})).toEqual(unavailable)
					expect(handlers.GetShrine(player, {})).toEqual(unavailable)
					expect(handlers.AssignShrineWorker(player, {})).toEqual(unavailable)
					expect(handlers.RemoveShrineWorker(player, {})).toEqual(unavailable)
					expect(handlers.UpgradeShrine(player, {})).toEqual(unavailable)
					expect(handlers.DismantleShrine(player, {})).toEqual(unavailable)
				end
			end
			local function noProtectedWork()
				rejected(nil)
				rejected(false)
				rejected(f.root)
				rejected({ UserId = 1001, Parent = Players })
				expect(f.state.viewCalls + f.state.reads + f.state.loads + f.state.transactions).toBe(
					0
				)
				expect(f.state.admissions + f.state.accessChecks + f.state.shrineAccessChecks).toBe(
					0
				)
			end
			noProtectedWork()
			f.api.Init(f.context)
			noProtectedWork()
			f.api.Start()
			noProtectedWork()
			f.api.Stop()
			noProtectedWork()
		end
	)

	it(
		"constructs the loaded-only reader once and releases its lifecycle without restarting",
		function()
			local f = fixture()
			f.api.Init(f.context)
			expect(f.state.factories).toBe(1)
			expect(f.state.requestFactories).toBe(1)
			expect(f.state.canonicalLimiterFactories).toBe(1)
			expect(f.state.legacyLimiterFactories).toBe(1)
			expect(f.state.reader).never.toBeNil()
			expect(f.state.shrineReader).never.toBeNil()
			expect(f.state.shrineViewFactories).toBe(1)
			expect(f.state.shrineWorkerFactories).toBe(1)
			expect(f.state.shrineUpgradeFactories).toBe(1)
			expect(f.state.shrineRemovalFactories).toBe(1)
			f.api.Start()
			f.api.Start()
			expect(f.state.observations).toBe(1)
			f.api.Stop()
			f.api.Stop()
			expect(f.state.observationCleanups).toBe(1)
			expect(f.state.cleared).toEqual(f.remotes)
			expect(f.state.canonicalLimiterClears).toBe(1)
			expect(f.state.legacyLimiterClears).toBe(1)
			expect(f.state.viewCalls + f.state.reads + f.state.loads + f.state.transactions).toBe(0)
			expect(function()
				f.api.Start()
			end).toThrow()
		end
	)

	it(
		"injects the exact loaded-data source into the real reader without granting facade access",
		function()
			local f = fixture()
			f.api.Init(f.context)
			local reader = assert(f.state.reader, "[BaseServiceView.spec] Expected injected reader")
			-- Direct private-reader calls test dependency injection only; the real public Player gate
			-- remains intact and cannot be positively exercised by a fabricated engine Player.
			local identity = (table.freeze({}) :: unknown) :: Player
			expect(reader.Get(identity)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			local data: Types.PlayerDoc =
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate))
			assert(ProfileSchema.Prepare(data, function()
				return "base_view_station"
			end, 0))
			f.state.loaded = data
			local result = reader.Get(identity)
			expect(result).toEqual({ ok = false, code = "DataUnavailable", revision = 0 })
			expect(f.state.reads).toBe(2)
			expect(f.state.loads + f.state.transactions).toBe(0)
			f.api.Start()
			expect(f.api.GetBase(identity)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.state.reads).toBe(2)
		end
	)

	it(
		"injects one production access guard into reads and both purchases without weakening identity checks",
		function()
			local f = fixture()
			f.api.Init(f.context)
			local viewGuard =
				assert(f.state.viewGuard, "[BaseServiceView.spec] Expected view guard")
			local buildGuard =
				assert(f.state.buildGuard, "[BaseServiceView.spec] Expected build guard")
			local expandGuard =
				assert(f.state.expandGuard, "[BaseServiceView.spec] Expected expansion guard")
			expect(buildGuard).toBe(viewGuard)
			expect(expandGuard).toBe(viewGuard)
			local data: Types.PlayerDoc =
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate))
			assert(ProfileSchema.Prepare(data, function()
				return "base_guard_station"
			end, 0))
			local function denied()
				for _, raw in { { UserId = 1001, Parent = Players }, f.root, false } do
					local player = (raw :: unknown) :: Player
					for _, guard in { viewGuard, buildGuard, expandGuard } do
						expect(guard(player, data)).toBe("DataUnavailable")
					end
				end
				expect(f.state.accessChecks).toBe(0)
				expect(f.state.reads + f.state.loads + f.state.transactions + f.state.admissions).toBe(
					0
				)
			end
			denied()
			f.api.Start()
			denied()
			f.api.Stop()
			denied()
		end
	)

	it("forwards each admitted Shrine payload unchanged to its distinct public owner", function()
		local f = fixture()
		f.api.Init(f.context)
		local dependencies = assert(
			f.state.requestDependencies,
			"[BaseServiceView.spec] Expected request dependencies"
		)
		local calls: { { route: string, player: Player, input: unknown } } = {}
		local response: Types.TransactionResult = { ok = false, code = "Forwarded", revision = 23 }
		local viewResponse: Types.ShrineViewResult = { ok = false, code = "Viewed", revision = 23 }
		local function record(route: string, player: Player, input: unknown)
			table.insert(calls, { route = route, player = player, input = input })
		end
		-- Only these public-owner spies are replaced: this tests callback wiring, not admission or
		-- positive engine-Player access. The independent lifecycle tests retain the genuine gates.
		f.api.GetShrine = function(player, input): Types.ShrineViewResult
			record("GetShrine", player, input)
			return viewResponse
		end
		f.api.AssignShrineWorker = function(player, input): Types.TransactionResult
			record("AssignShrineWorker", player, input)
			return response
		end
		f.api.RemoveShrineWorker = function(player, input): Types.TransactionResult
			record("RemoveShrineWorker", player, input)
			return response
		end
		f.api.UpgradeShrine = function(player, input): Types.TransactionResult
			record("UpgradeShrine", player, input)
			return response
		end
		f.api.DismantleShrine = function(player, input): Types.TransactionResult
			record("DismantleShrine", player, input)
			return response
		end
		local identity = (table.freeze({}) :: unknown) :: Player
		local payload = table.freeze({ shrineInstanceId = "selected", unparsed = true })
		expect(dependencies.getShrine(identity, payload)).toBe(viewResponse)
		expect(dependencies.assignShrineWorker(identity, payload)).toBe(response)
		expect(dependencies.removeShrineWorker(identity, payload)).toBe(response)
		expect(dependencies.upgradeShrine(identity, payload)).toBe(response)
		expect(dependencies.dismantleShrine(identity, payload)).toBe(response)
		local expectedRoutes = {
			"GetShrine",
			"AssignShrineWorker",
			"RemoveShrineWorker",
			"UpgradeShrine",
			"DismantleShrine",
		}
		expect(#calls).toBe(#expectedRoutes)
		for index, call in calls do
			expect(call.route).toBe(expectedRoutes[index])
			expect(call.player).toBe(identity)
			expect(call.input).toBe(payload)
		end
		expect(f.state.reads + f.state.loads + f.state.transactions + f.state.admissions).toBe(0)
	end)

	it(
		"injects one mandatory Shrine guard into the real reader and all three command owners",
		function()
			local f = fixture()
			f.api.Init(f.context)
			local guard =
				assert(f.state.shrineViewGuard, "[BaseServiceView.spec] Expected Shrine view guard")
			expect(f.state.shrineWorkerGuard).toBe(guard)
			expect(f.state.shrineUpgradeGuard).toBe(guard)
			expect(f.state.shrineRemovalGuard).toBe(guard)
			local data: Types.PlayerDoc =
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate))
			assert(ProfileSchema.Prepare(data, function()
				return "shrine_guard_station"
			end, 0))
			local function denied()
				local function check(raw: unknown)
					local player = raw :: Player
					expect(guard(player, data, "selected")).toBe("DataUnavailable")
					expect(f.api.CheckShrineAccess(player, data.base, "selected")).toBe(
						"DataUnavailable"
					)
				end
				check(nil)
				check(false)
				check(f.root)
				check({ UserId = 1001, Parent = Players })
				expect(f.state.shrineAccessChecks).toBe(0)
				expect(f.state.reads + f.state.loads + f.state.transactions + f.state.admissions).toBe(
					0
				)
			end
			denied()
			f.api.Start()
			denied()
			f.api.Stop()
			denied()
		end
	)

	it(
		"uses the loaded-only Shrine reader but denies forged identity before accounting projection",
		function()
			local f = fixture()
			f.api.Init(f.context)
			local reader =
				assert(f.state.shrineReader, "[BaseServiceView.spec] Expected Shrine reader")
			local identity = (table.freeze({}) :: unknown) :: Player
			local request = { shrineInstanceId = "selected" }
			local unavailable = { ok = false, code = "DataUnavailable", revision = 0 }
			expect(reader.Get(identity, request)).toEqual(unavailable)
			local data: Types.PlayerDoc =
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate))
			assert(ProfileSchema.Prepare(data, function()
				return "shrine_reader_station"
			end, 0))
			-- Deliberately malformed accounting would fail if projection ran ahead of the guard.
			data.productionClock = nil
			f.state.loaded = data
			for _, phase in { "initialized", "started", "stopped" } do
				if phase == "started" then
					f.api.Start()
				end
				if phase == "stopped" then
					f.api.Stop()
				end
				expect(reader.Get(identity, request)).toEqual(unavailable)
			end
			expect(f.state.reads).toBe(4)
			expect(f.state.shrineAccessChecks).toBe(0)
			expect(f.state.loads + f.state.transactions + f.state.admissions).toBe(0)
		end
	)
end)
