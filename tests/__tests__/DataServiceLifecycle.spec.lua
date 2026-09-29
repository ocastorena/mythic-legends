--!strict
-- ServerStorage/Tests/__tests__/DataServiceLifecycle.spec
-- Exercise the real service with a mocked persistence vendor, never live stores or engine Players.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local afterEach = JestGlobals.afterEach
local jest = JestGlobals.jest
local vendorModule = ServerScriptService.Packages.ProfileStore
local cleanup: { () -> () } = {}

type Connection = { Connected: boolean, Disconnect: (Connection) -> () }
type Signal = {
	Connect: (Signal, () -> ()) -> Connection,
	Fire: (Signal) -> (),
	Capture: () -> { () -> () },
	Count: () -> number,
}
type FakeProfile = {
	Data: Types.PlayerDoc,
	OnLastSave: Signal,
	OnSessionEnd: Signal,
	IsActive: (FakeProfile) -> boolean,
	AddUserId: (FakeProfile, number) -> (),
	Reconcile: (FakeProfile) -> (),
	Save: (FakeProfile) -> (),
	EndSession: (FakeProfile) -> (),
}
type DataApi = ServerTypes.DataApi & {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	OnLoaded: RBXScriptSignal,
	OnReleased: RBXScriptSignal,
}
type PublicProbe = {
	loaded: Types.PlayerDoc?,
	load: boolean,
	dirty: boolean,
	transaction: string?,
	update: string?,
	checkpoint: string?,
	save: boolean,
	mutated: boolean,
}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function signal(): Signal
	local listeners: { { callback: () -> (), connection: Connection } } = {}
	return {
		Connect = function(_self: Signal, callback: () -> ()): Connection
			local connection: Connection = {
				Connected = true,
				Disconnect = function(self: Connection)
					self.Connected = false
				end,
			}
			table.insert(listeners, { callback = callback, connection = connection })
			return connection
		end,
		Fire = function(_self: Signal)
			-- Vendor listeners begin synchronously; a boundary callback must never yield.
			for _, listener in table.clone(listeners) do
				if listener.connection.Connected then
					listener.callback()
				end
			end
		end,
		Capture = function(): { () -> () }
			local result: { () -> () } = {}
			for _, listener in listeners do
				if listener.connection.Connected then
					table.insert(result, listener.callback)
				end
			end
			return result
		end,
		Count = function(): number
			local count = 0
			for _, listener in listeners do
				if listener.connection.Connected then
					count += 1
				end
			end
			return count
		end,
	}
end

local function fakeProfile()
	local state = {
		active = true,
		endCalls = 0,
		saveCalls = 0,
		reconcileCalls = 0,
		users = {} :: { number },
		saved = {} :: { Types.PlayerDoc },
	}
	local profile: FakeProfile = {
		Data = copy(PlayerDataTemplate),
		OnLastSave = signal(),
		OnSessionEnd = signal(),
		IsActive = function(): boolean
			return state.active
		end,
		AddUserId = function(_self: FakeProfile, userId: number)
			table.insert(state.users, userId)
		end,
		Reconcile = function()
			state.reconcileCalls += 1
		end,
		Save = function(self: FakeProfile)
			state.saveCalls += 1
			table.insert(state.saved, copy(self.Data))
		end,
		EndSession = function(self: FakeProfile)
			if not state.active then
				return
			end
			state.endCalls += 1
			self.OnLastSave:Fire()
			state.active = false
			self.OnSessionEnd:Fire()
		end,
	}
	return { profile = profile, state = state }
end

local function fixture()
	local first, second = fakeProfile(), fakeProfile()
	local pending = { first, second }
	local state = {
		loads = 0,
		newCalls = 0,
		kicks = {} :: { string },
		packets = {} :: { Types.StatePacket },
		packetPlayers = {} :: { Player },
	}
	local rawPlayer = {
		UserId = 1001,
		Parent = Players,
		Kick = function(_self: unknown, message: string)
			table.insert(state.kicks, message)
		end,
	}
	local player = (rawPlayer :: unknown) :: Player
	local request: { OnServerInvoke: unknown } = { OnServerInvoke = nil }
	local update = {
		FireClient = function(_self: unknown, recipient: Player, packet: Types.StatePacket)
			table.insert(state.packetPlayers, recipient)
			table.insert(state.packets, copy(packet))
		end,
	}
	local store = {
		StartSessionAsync = function(
			_self: unknown,
			_key: string,
			parameters: { Cancel: () -> boolean }
		): FakeProfile?
			state.loads += 1
			if parameters.Cancel() then
				return nil
			end
			local nextProfile = pending[state.loads]
			return if nextProfile then nextProfile.profile else nil
		end,
	}
	local vendor = {
		IsClosing = false,
		New = function()
			state.newCalls += 1
			return { Mock = store, StartSessionAsync = store.StartSessionAsync }
		end,
	}
	local service: DataApi? = nil
	jest.mock(vendorModule, function()
		return vendor
	end)
	jest.isolateModules(function()
		-- The real service and private modules execute through Jest's isolated loader. The only
		-- mock is the vendor factory; no Source rewriting or engine-capability emulation occurs.
		local loadService = require :: (ModuleScript) -> DataApi
		service = loadService(ServerScriptService.Services.DataService)
	end)
	local api = assert(service, "[DataServiceLifecycle.spec] Expected isolated service")
	api.Init(
		(
				{ Remotes = { State = { Update = update, Request = request } } } :: unknown
			) :: ServerTypes.Context
	)
	table.insert(cleanup, function()
		api.Stop()
	end)
	return {
		api = api,
		player = player,
		state = state,
		first = first,
		second = second,
		vendor = vendor,
		request = request,
	}
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(vendorModule)
end)

local function probePublic(api: DataApi, player: Player): PublicProbe
	local mutated = false
	local function mutation(_draft: Types.PlayerDoc): Types.TransactionOutcome
		mutated = true
		return { ok = true }
	end
	return {
		loaded = api.GetLoadedData(player),
		load = api.Load(player),
		dirty = api.MarkDirty(player),
		transaction = api.Transact(
			player,
			{ id = "0:closing", expectedRevision = 0, operation = "Test.Closing", signature = "" },
			mutation
		).code,
		update = api.Update(player, "Test.Closing", mutation).code,
		checkpoint = api.Checkpoint(player).code,
		save = api.SaveNow(player),
		mutated = mutated,
	}
end

local function expectBlocked(result: PublicProbe)
	expect(result.loaded).toBeNil()
	expect(result.load).toBe(false)
	expect(result.dirty).toBe(false)
	expect(result.transaction).toBe("DataUnavailable")
	expect(result.update).toBe("DataUnavailable")
	expect(result.checkpoint).toBe("DataUnavailable")
	expect(result.save).toBe(false)
	expect(result.mutated).toBe(false)
end

describe("DataService profile lifecycle", function()
	it(
		"settles every Ready hook before loaded data, first publication, or OnLoaded exposure",
		function()
			local f = fixture()
			local readyCalls, loadedCalls = 0, 0
			local loadedGold: number? = nil
			local firstTime: number? = nil
			f.api.RegisterProfileSettlement("first", function(draft, timestamp, boundary)
				if boundary == "Ready" then
					readyCalls += 1
					expect(f.api.GetLoadedData(f.player)).toBeNil()
					expect(#f.state.packets).toBe(0)
					expect(loadedCalls).toBe(0)
					firstTime = timestamp
					draft.currency.gold = 321
				end
				return { ok = true }
			end)
			f.api.RegisterProfileSettlement("second", function(draft, timestamp, boundary)
				if boundary == "Ready" then
					readyCalls += 1
					expect(timestamp).toBe(firstTime)
					expect(draft.currency.gold).toBe(321)
					draft.currency.gold = 456
				end
				return { ok = true }
			end)
			f.api.OnLoaded:Connect(function(player: Player, data: Types.PlayerDoc)
				-- BindableEvent copies table arguments; real engine Player identity is not modeled.
				expect(player.UserId).toBe(f.player.UserId)
				expect(player.Parent).toBe(Players)
				loadedCalls += 1
				loadedGold = data.currency.gold
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			task.wait()
			expect(readyCalls).toBe(2)
			expect(loadedCalls).toBe(1)
			expect(loadedGold).toBe(456)
			expect(f.api.GetLoadedData(f.player)).toBe(f.first.profile.Data)
			expect(#f.state.packets).toBe(1)
			expect(f.state.packets[1].values.currency.gold).toBe(456)
			expect(f.state.packets[1].values.transactionRevision).toBe(1)
			expect(f.api.Load(f.player)).toBe(true)
			expect(f.state.loads).toBe(1)
			expect(readyCalls).toBe(2)
			expect(f.first.state.users).toEqual({ 1001 })
		end
	)

	it("rejects duplicate registration and registration after service startup", function()
		local f = fixture()
		local hook: ServerTypes.ProfileSettlement = function()
			return { ok = true }
		end
		f.api.RegisterProfileSettlement("Production", hook)
		expect(function()
			f.api.RegisterProfileSettlement("Production", hook)
		end).toThrow()
		f.api.Start()
		expect(function()
			f.api.RegisterProfileSettlement("late", hook)
		end).toThrow()
	end)

	it(
		"never exposes a profile whose later Ready hook rejects and rolls back earlier hook edits",
		function()
			local f = fixture()
			local loadedCalls = 0
			f.api.OnLoaded:Connect(function()
				loadedCalls += 1
			end)
			f.api.RegisterProfileSettlement("first", function(draft)
				draft.currency.gold = 999
				return { ok = true }
			end)
			f.api.RegisterProfileSettlement("reject", function()
				return { ok = false, code = "UnsafeBoundary" }
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(false)
			task.wait()
			expect(f.api.GetLoadedData(f.player)).toBeNil()
			expect(#f.state.packets).toBe(0)
			expect(loadedCalls).toBe(0)
			expect(f.first.profile.Data.currency.gold).toBe(100)
			expect(f.first.state.endCalls).toBe(1)
			expect(#f.state.kicks).toBe(1)
		end
	)

	it(
		"finalizes manual Release once before the vendor ends ownership and blocks closing mutations",
		function()
			local f = fixture()
			local releases = 0
			local releaseState: PublicProbe? = nil
			f.api.RegisterProfileSettlement("Production", function(draft, _timestamp, boundary)
				if boundary == "Release" then
					releases += 1
					expect(f.first.state.active).toBe(true)
					draft.currency.gold = 222
				end
				return { ok = true }
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			f.first.profile.OnLastSave:Connect(function()
				releaseState = probePublic(f.api, f.player)
				expect(f.first.profile.Data.currency.gold).toBe(222)
			end)
			f.api.Release(f.player)
			f.api.Release(f.player)
			expect(releases).toBe(1)
			expect(f.first.state.endCalls).toBe(1)
			expectBlocked(
				(assert(releaseState, "[DataServiceLifecycle.spec] Expected release probe"))
			)
			expect(f.api.GetLoadedData(f.player)).toBeNil()
			expect(#f.state.kicks).toBe(0)
		end
	)

	it(
		"handles vendor-first final save before a later Stop without repeating settlement",
		function()
			local f = fixture()
			local releases = 0
			local releaseState: PublicProbe? = nil
			f.api.RegisterProfileSettlement("Production", function(draft, _timestamp, boundary)
				if boundary == "Release" then
					releases += 1
					expect(f.first.state.active).toBe(true)
					draft.currency.gold = 234
				end
				return { ok = true }
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			f.first.profile.OnLastSave:Connect(function()
				releaseState = probePublic(f.api, f.player)
			end)
			f.vendor.IsClosing = true
			f.first.profile:EndSession()
			f.api.Stop()
			expect(releases).toBe(1)
			expect(f.first.profile.Data.currency.gold).toBe(234)
			expect(f.first.state.endCalls).toBe(1)
			expectBlocked(
				(assert(releaseState, "[DataServiceLifecycle.spec] Expected vendor probe"))
			)
			expectBlocked(probePublic(f.api, f.player))
		end
	)

	it(
		"handles main-first Stop by settling active profiles before destroying their listeners",
		function()
			local f = fixture()
			local releases = 0
			f.api.RegisterProfileSettlement("Production", function(draft, _timestamp, boundary)
				if boundary == "Release" then
					releases += 1
					expect(f.first.profile.OnLastSave.Count()).toBe(1)
					expect(f.first.profile.OnSessionEnd.Count()).toBe(1)
					expect(f.first.state.active).toBe(true)
					draft.currency.gold = 345
				end
				return { ok = true }
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			f.api.Stop()
			f.api.Stop()
			expect(releases).toBe(1)
			expect(f.first.state.endCalls).toBe(1)
			expect(f.first.profile.Data.currency.gold).toBe(345)
			expect(f.first.profile.OnLastSave.Count()).toBe(0)
			expect(f.first.profile.OnSessionEnd.Count()).toBe(0)
			expect(f.request.OnServerInvoke).toBeNil()
			expectBlocked(probePublic(f.api, f.player))
		end
	)

	it(
		"checkpoints before SaveNow and does not request a save when a checkpoint rejects",
		function()
			local f = fixture()
			local shouldReject = false
			f.api.RegisterProfileSettlement("Production", function(draft, _timestamp, boundary)
				if boundary == "Checkpoint" then
					draft.currency.gold += 10
					if shouldReject then
						return { ok = false, code = "UnsafeCheckpoint" }
					end
				end
				return { ok = true }
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			expect(f.api.SaveNow(f.player)).toBe(true)
			expect(f.first.state.saveCalls).toBe(1)
			expect(f.first.state.saved[1].currency.gold).toBe(110)
			shouldReject = true
			expect(f.api.SaveNow(f.player)).toBe(false)
			expect(f.first.state.saveCalls).toBe(1)
			expect(f.first.profile.Data.currency.gold).toBe(110)
		end
	)

	it("does not let a late old-session callback erase a replacement profile", function()
		local f = fixture()
		f.api.RegisterProfileSettlement("Production", function()
			return { ok = true }
		end)
		f.api.Start()
		expect(f.api.Load(f.player)).toBe(true)
		local oldCallbacks = f.first.profile.OnSessionEnd.Capture()
		expect(#oldCallbacks).toBe(1)
		f.api.Release(f.player)
		expect(f.api.Load(f.player)).toBe(true)
		expect(f.api.GetLoadedData(f.player)).toBe(f.second.profile.Data)
		for _, callback in oldCallbacks do
			callback()
		end
		expect(f.api.GetLoadedData(f.player)).toBe(f.second.profile.Data)
		expect(f.second.state.active).toBe(true)
		expect(f.second.state.endCalls).toBe(0)
		expect(#f.state.kicks).toBe(0)
	end)
end)
