--!strict
-- ServerStorage/Tests/__tests__/InventoryRemotes.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local InventoryRequests = require(ServerScriptService.Services.InventoryService.InventoryRequests)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)
local Configuration = require(ReplicatedStorage.Shared.Configurations.InventoryRequests)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local cleanup: { () -> () } = {}
local requestsModule = ServerScriptService.Services.InventoryService.InventoryRequests
local limiterModule = ServerScriptService.Infrastructure.RateLimiter
local mythlingsModule = ServerScriptService.Services.InventoryService.Mythlings
local ACTIONS = {
	"EvolveMythling",
	"SellMythling",
	"SellEquipment",
	"SellMaterial",
	"DiscardMaterial",
	"UpgradeCapacity",
}
type RemoteDouble = { OnServerInvoke: unknown }
type Service = { Init: (ServerTypes.Context) -> (), Start: () -> (), Stop: () -> () }

local function fixture()
	local state = {
		reads = 0,
		removes = 0,
		unassigns = 0,
		admissions = 0,
		clears = 0,
		factories = 0,
		calls = {} :: { string },
		caller = nil :: Player?,
		payload = nil :: unknown,
	}
	local captured = {
		dependencies = nil :: InventoryRequests.Dependencies?,
		handlers = nil :: InventoryRequests.Requests?,
	}
	local remotes: { [string]: RemoteDouble } = {}
	local commands: { [string]: InventoryRequests.Command } = {}
	for _, name in ACTIONS do
		remotes[name] = { OnServerInvoke = nil }
		commands[name] = function(player: Player, payload: unknown): Types.TransactionResult
			table.insert(state.calls, name)
			state.caller, state.payload = player, payload
			return { ok = true, revision = 7, values = { action = name } }
		end
	end
	remotes.DeleteMythling = { OnServerInvoke = nil }
	jest.mock(requestsModule, function()
		return {
			new = function(
				dependencies: InventoryRequests.Dependencies
			): InventoryRequests.Requests
				state.factories += 1
				captured.dependencies = dependencies
				local handlers = InventoryRequests.new(dependencies)
				captured.handlers = handlers
				return handlers
			end,
		}
	end)
	jest.mock(limiterModule, function()
		return {
			new = function(burst: number, refill: number)
				expect(burst).toBe(Configuration.requestBurst)
				expect(refill).toBe(Configuration.requestRefillPerSecond)
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
						state.clears += 1
						real:Clear()
					end,
				}
			end,
		}
	end)
	-- Any accidental revival of the old delete path is observable without accessing real saves.
	jest.mock(mythlingsModule, function()
		return {
			Get = function()
				state.reads += 1
				return { standId = 1, pendingXp = 9 }
			end,
			Remove = function()
				state.removes += 1
				return true
			end,
		}
	end)
	local service: Service? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> Service
		service = loadService(ServerScriptService.Services.InventoryService.InventoryRemotes)
	end)
	local api = assert(service, "[InventoryRemotes.spec] Expected isolated owner")
	table.insert(cleanup, api.Stop)
	local context = (
		{
			Services = {
				InventoryService = commands,
				DataService = {
					GetLoadedData = function()
						state.reads += 1
						return nil
					end,
				},
				BaseService = {
					RemoveMythlingFromStand = function()
						state.unassigns += 1
						return true
					end,
				},
			},
			-- Callback slots are doubles so binding/removal is observable without reading write-only
			-- engine callbacks; production class validation remains RemoteUtil.Resolve's responsibility.
			Remotes = { Inventory = remotes },
		} :: unknown
	) :: ServerTypes.Context
	return { api = api, state = state, captured = captured, remotes = remotes, context = context }
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(requestsModule)
	jest.unmock(limiterModule)
	jest.unmock(mythlingsModule)
end)

describe("InventoryRemotes", function()
	it(
		"binds six distinct command adapters and the legacy tombstone exactly once, then clears all handlers",
		function()
			local f = fixture()
			for _, remote in f.remotes do
				expect(remote.OnServerInvoke).toBeNil()
			end
			f.api.Init(f.context)
			local dependencies =
				assert(f.captured.dependencies, "[InventoryRemotes.spec] Expected adapters")
			local handlers =
				assert(f.captured.handlers, "[InventoryRemotes.spec] Expected handlers")
			for _, remote in f.remotes do
				expect(remote.OnServerInvoke).toBeNil()
			end
			f.api.Start()
			f.api.Start()
			expect(f.state.factories).toBe(1)
			local opaque = (table.freeze({}) :: unknown) :: Player
			local adapters = dependencies.commands :: { [string]: InventoryRequests.Command }
			local callbackMap = handlers :: { [string]: unknown }
			for _, name in ACTIONS do
				expect(f.remotes[name].OnServerInvoke).toBe(callbackMap[name])
				local payload = { unexpected = name }
				-- Exercise only the captured facade wiring; authorization is tested through handlers below.
				expect(adapters[name](opaque, payload)).toEqual({
					ok = true,
					revision = 7,
					values = { action = name },
				})
				expect(f.state.caller).toBe(opaque)
				expect(f.state.payload).toBe(payload)
			end
			expect(f.state.calls).toEqual(ACTIONS)
			expect(f.remotes.DeleteMythling.OnServerInvoke).toBe(handlers.DeleteMythling)
			f.api.Stop()
			f.api.Stop()
			for _, remote in f.remotes do
				expect(remote.OnServerInvoke).toBeNil()
			end
			expect(f.state.clears).toBe(1)
			expect(f.state.reads + f.state.removes + f.state.unassigns).toBe(0)
			expect(function()
				f.api.Start()
			end).toThrow()
		end
	)

	it(
		"rejects invalid callers and retained callbacks before admission or legacy side effects at every lifecycle stage",
		function()
			local f = fixture()
			local nonPlayer = Instance.new("Folder")
			table.insert(cleanup, function()
				nonPlayer:Destroy()
			end)
			f.api.Init(f.context)
			local retained =
				assert(f.captured.handlers, "[InventoryRemotes.spec] Expected retained callbacks")
			local callbacks = retained :: { [string]: (Player, unknown) -> unknown }
			local function unavailable()
				for _, raw in { { UserId = 1001, Parent = Players }, nonPlayer, false } do
					local player = (raw :: unknown) :: Player
					for _, action in ACTIONS do
						expect(callbacks[action](player, {})).toEqual({
							ok = false,
							code = "DataUnavailable",
							revision = 0,
						})
					end
					expect(retained.DeleteMythling(player, "assigned_pending_worker")).toEqual({
						ok = false,
						code = "DataUnavailable",
					})
				end
				expect(f.state.calls).toEqual({})
				expect(f.state.admissions + f.state.reads + f.state.removes + f.state.unassigns).toBe(
					0
				)
			end
			unavailable()
			f.api.Start()
			unavailable()
			f.api.Stop()
			unavailable()
			expect(f.state.clears).toBe(1)
		end
	)
end)
