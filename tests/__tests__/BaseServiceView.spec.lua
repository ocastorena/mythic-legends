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
local BaseView = require(ServerScriptService.Services.BaseService.BaseView)
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
local cleanup: { () -> () } = {}

type Service = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	GetBase: (Player) -> Types.BaseViewResult,
	BuildShrine: (Player, Types.BuildShrineRequest) -> Types.TransactionResult,
}

local function fixture()
	local state = {
		reads = 0,
		transactions = 0,
		loads = 0,
		factories = 0,
		viewCalls = 0,
		observations = 0,
		observationCleanups = 0,
		loaded = nil :: Types.PlayerDoc?,
		reader = nil :: BaseView.BaseView?,
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
			new = function(dataSource: BaseView.DataSource): BaseView.BaseView
				expect(dataSource).toBe(source)
				state.factories += 1
				local real = BaseView.new(dataSource)
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
			Remotes = { Base = { PlaceMythling = place, RemoveMythling = remove } },
			Services = { DataService = source, InventoryService = {}, ProductionService = {} },
		} :: unknown
	) :: ServerTypes.Context
	return { api = api, context = context, state = state, root = root, remotes = { place, remove } }
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(viewModule)
	jest.unmock(playersModule)
	jest.unmock(remoteModule)
end)

describe("BaseService view and construction admission", function()
	it(
		"rejects forged identities before reader, load, or transaction work throughout its lifetime",
		function()
			local f = fixture()
			local get, build = f.api.GetBase, f.api.BuildShrine
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
				expect(build(player, request)).toEqual(unavailable)
			end
			local function noProtectedWork()
				rejected(nil)
				rejected(false)
				rejected(f.root)
				rejected({ UserId = 1001, Parent = Players })
				expect(f.state.viewCalls + f.state.reads + f.state.loads + f.state.transactions).toBe(
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
			expect(f.state.reader).never.toBeNil()
			f.api.Start()
			f.api.Start()
			expect(f.state.observations).toBe(1)
			f.api.Stop()
			f.api.Stop()
			expect(f.state.observationCleanups).toBe(1)
			expect(f.state.cleared).toEqual(f.remotes)
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
			expect(result.ok).toBe(true)
			local view = assert(result.view, "[BaseServiceView.spec] Expected loaded Base view")
			expect(view.status.craftingStation.id).toBe("base_view_station")
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
end)
