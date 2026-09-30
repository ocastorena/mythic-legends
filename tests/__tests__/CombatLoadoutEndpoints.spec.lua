--!strict
-- ServerStorage/Tests/__tests__/CombatLoadoutEndpoints.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Equipment = require(ReplicatedStorage.Shared.Configurations.Equipment)
local Configuration = require(ReplicatedStorage.Shared.Configurations.LoadoutRequests)
local LoadoutRequests = require(ServerScriptService.Services.CombatService.LoadoutRequests)
local RateLimiter = require(ServerScriptService.Infrastructure.RateLimiter)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local requestsModule = ServerScriptService.Services.CombatService.LoadoutRequests
local limiterModule = ServerScriptService.Infrastructure.RateLimiter
local cleanup: { () -> () } = {}
local NAMES = { "GetLoadout", "Equip", "EquipEquipment", "UnequipEquipment" }
type RemoteDouble = { OnServerInvoke: unknown }
type LimiterDouble = {
	Allow: (unknown, Player, number?) -> boolean,
	Forget: (unknown, Player) -> (),
	Clear: (unknown) -> (),
}
type Service = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	EquipEquipment: (Player, Types.EquipEquipmentRequest) -> Types.TransactionResult,
	UnequipEquipment: (Player, Types.UnequipEquipmentRequest) -> Types.TransactionResult,
}

local function fixture()
	local state = { reads = 0, loads = 0, transactions = 0, admissions = 0, clears = 0 }
	local captured = {
		dependencies = nil :: LoadoutRequests.Dependencies?,
		handlers = nil :: LoadoutRequests.Requests?,
		factories = 0,
		clears = 0,
	}
	jest.mock(requestsModule, function()
		return {
			new = function(dependencies: LoadoutRequests.Dependencies): LoadoutRequests.Requests
				captured.dependencies = dependencies
				captured.factories += 1
				local handlers = LoadoutRequests.new(dependencies)
				local clear = handlers.Clear
				handlers.Clear = function()
					captured.clears += 1
					clear()
				end
				captured.handlers = handlers
				return handlers
			end,
		}
	end)
	jest.mock(limiterModule, function()
		return {
			new = function(burst: number, refill: number): LimiterDouble
				local real = RateLimiter.new(burst, refill)
				local isLoadout = burst == Configuration.requestBurst
					and refill == Configuration.requestRefillPerSecond
				return {
					Allow = function(_self: unknown, player: Player, cost: number?): boolean
						if isLoadout then
							state.admissions += 1
						end
						return real:Allow(player, cost)
					end,
					Forget = function(_self: unknown, player: Player)
						real:Forget(player)
					end,
					Clear = function(_self: unknown)
						if isLoadout then
							state.clears += 1
						end
						real:Clear()
					end,
				}
			end,
		}
	end)
	local assets, arena = Instance.new("Folder"), Instance.new("Part")
	table.insert(cleanup, function()
		assets:Destroy()
		arena:Destroy()
	end)
	local remotes: { [string]: unknown } = {}
	local callbacks: { [string]: RemoteDouble } = {}
	-- Callback slots are doubles because engine OnServerInvoke is write-only. Combat event
	-- connections still use real, disposable RemoteEvents; no authored network is touched.
	for _, name in NAMES do
		local remote: RemoteDouble = { OnServerInvoke = nil }
		callbacks[name], remotes[name] = remote, remote
	end
	for _, name in { "StartAttack", "ReportHit", "SetShieldGuard", "Reaction", "Impact" } do
		local remote = Instance.new("RemoteEvent")
		remote.Name, remote.Parent = name, assets
		remotes[name] = remote
	end
	local context = (
		{
			Configurations = { Equipment = Equipment },
			Instances = { EquipmentAssets = assets, Arena = arena },
			Remotes = { Combat = remotes },
			Services = {
				DataService = {
					GetLoadedData = function(_player: Player): Types.PlayerDoc?
						state.reads += 1
						return nil
					end,
					Load = function(_player: Player): boolean
						state.loads += 1
						return false
					end,
					Transact = function(): Types.TransactionResult
						state.transactions += 1
						return { ok = false, code = "DataUnavailable", revision = 0 }
					end,
				},
			},
		} :: unknown
	) :: ServerTypes.Context
	local service: Service? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> Service
		service = loadService(ServerScriptService.Services.CombatService)
	end)
	local api = assert(service, "[CombatLoadoutEndpoints.spec] Expected isolated service")
	table.insert(cleanup, api.Stop)
	return {
		api = api,
		context = context,
		state = state,
		captured = captured,
		callbacks = callbacks,
	}
end

local function assertDisposablePlace()
	-- Starting this owner must never initialize real players or remove authored preview rigs.
	assert(
		#Players:GetPlayers() == 0,
		"[CombatLoadoutEndpoints.spec] Requires the disposable test place"
	)
	for _, name in { "R15WeaponPositioningRig", "WeaponPosePreview" } do
		assert(
			workspace:FindFirstChild(name) == nil,
			"[CombatLoadoutEndpoints.spec] Authoring content is out of scope"
		)
	end
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(requestsModule)
	jest.unmock(limiterModule)
end)

describe("Combat loadout endpoints", function()
	it(
		"binds all four admitted handlers and routes canonical envelopes through the public facade",
		function()
			local f = fixture()
			f.api.Init(f.context)
			local handlers = assert(f.captured.handlers, "Expected real request handlers")
			local dependencies = assert(f.captured.dependencies, "Expected facade adapters")
			for _, remote in f.callbacks do
				expect(remote.OnServerInvoke).toBeNil()
			end
			assertDisposablePlace()
			f.api.Start()
			f.api.Start()
			expect(f.captured.factories).toBe(1)
			expect(f.callbacks.GetLoadout.OnServerInvoke).toBe(handlers.Get)
			expect(f.callbacks.Equip.OnServerInvoke).toBe(handlers.Equip)
			expect(f.callbacks.EquipEquipment.OnServerInvoke).toBe(handlers.EquipEquipment)
			expect(f.callbacks.UnequipEquipment.OnServerInvoke).toBe(handlers.UnequipEquipment)
			local caller = (table.freeze({}) :: unknown) :: Player
			local input = table.freeze({ targetUserId = 9001, extra = true })
			local result: Types.TransactionResult =
				{ ok = false, code = "InvalidRequest", revision = 6 }
			local frozenResult = result
			table.freeze(frozenResult)
			expect(table.isfrozen(result)).toBe(true)
			local originalEquip, originalUnequip = f.api.EquipEquipment, f.api.UnequipEquipment
			table.insert(cleanup, function()
				f.api.EquipEquipment, f.api.UnequipEquipment = originalEquip, originalUnequip
			end)
			local seen: { string } = {}
			f.api.EquipEquipment = function(player, request)
				table.insert(seen, "Equip")
				expect(player).toBe(caller)
				expect(request).toBe(input)
				return result
			end
			f.api.UnequipEquipment = function(player, request)
				table.insert(seen, "Unequip")
				expect(player).toBe(caller)
				expect(request).toBe(input)
				return result
			end
			-- Invoke only the captured delegates here; real admission is exercised below.
			expect(dependencies.equipEquipment(caller, input)).toBe(result)
			expect(dependencies.unequipEquipment(caller, input)).toBe(result)
			expect(seen).toEqual({ "Equip", "Unequip" })
			f.api.Stop()
			f.api.Stop()
			for _, remote in f.callbacks do
				expect(remote.OnServerInvoke).toBeNil()
			end
			expect(f.captured.clears).toBe(1)
			expect(f.state).toEqual({
				reads = 0,
				loads = 0,
				transactions = 0,
				admissions = 0,
				clears = 1,
			})
			expect(function()
				f.api.Start()
			end).toThrow()
		end
	)

	it(
		"rejects fake callers before admission or profile work throughout the service lifetime",
		function()
			local f = fixture()
			local folder = Instance.new("Folder")
			table.insert(cleanup, function()
				folder:Destroy()
			end)
			local retained: LoadoutRequests.Requests? = nil
			local function unavailable()
				for _, raw in { { Parent = Players, UserId = 1001 }, folder, false } do
					local player = (raw :: unknown) :: Player
					local expected = { ok = false, code = "DataUnavailable", revision = 0 }
					expect(
						f.api.EquipEquipment(player, ({} :: unknown) :: Types.EquipEquipmentRequest)
					).toEqual(expected)
					expect(
						f.api.UnequipEquipment(
							player,
							({} :: unknown) :: Types.UnequipEquipmentRequest
						)
					).toEqual(expected)
					local handlers = retained
					if handlers then
						expect(handlers.EquipEquipment(player, {})).toEqual(expected)
						expect(handlers.UnequipEquipment(player, {})).toEqual(expected)
						expect(handlers.Get(player)).toEqual({ ok = false, code = "Unavailable" })
						expect(handlers.Equip(player, "owned")).toEqual({
							ok = false,
							code = "Unavailable",
						})
					end
				end
				expect(f.state.reads).toBe(0)
				expect(f.state.loads).toBe(0)
				expect(f.state.transactions).toBe(0)
				expect(f.state.admissions).toBe(0)
			end
			unavailable()
			f.api.Init(f.context)
			retained = assert(f.captured.handlers, "Expected retained handlers")
			unavailable()
			assertDisposablePlace()
			f.api.Start()
			unavailable()
			f.api.Stop()
			unavailable()
			for _, remote in f.callbacks do
				expect(remote.OnServerInvoke).toBeNil()
			end
		end
	)
end)
