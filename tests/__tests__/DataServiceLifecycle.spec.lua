--!strict
-- ServerStorage/Tests/__tests__/DataServiceLifecycle.spec
-- Exercise the real service with a mocked persistence vendor, never live stores or engine Players.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Configuration = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ShopCommands = require(ServerScriptService.Services.ShopService.ShopCommands)
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

-- Match the vendor's missing-string-key reconciliation so lifecycle tests can detect accidental
-- grants/slot defaults introduced by the canonical template; this does not model durable storage.
local function reconcile(data: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if data[key] == nil then
			data[key] = copy(value)
		elseif type(data[key]) == "table" and type(value) == "table" then
			reconcile(data[key], value)
		end
	end
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
		Reconcile = function(self: FakeProfile)
			state.reconcileCalls += 1
			reconcile(self.Data :: any, PlayerDataTemplate :: any)
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
		storeNames = {} :: { string },
		profileKeys = {} :: { string },
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
			key: string,
			parameters: { Cancel: () -> boolean }
		): FakeProfile?
			state.loads += 1
			table.insert(state.profileKeys, key)
			if parameters.Cancel() then
				return nil
			end
			local nextProfile = pending[state.loads]
			return if nextProfile then nextProfile.profile else nil
		end,
	}
	local vendor = {
		IsClosing = false,
		New = function(storeName: string)
			state.newCalls += 1
			table.insert(state.storeNames, storeName)
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
	it("opens only the configured development namespace and stable player key", function()
		local f = fixture()
		f.api.Start()
		expect(f.state.newCalls).toBe(1)
		expect(f.state.storeNames).toEqual({ "MythicLegends_MVP_v1" })
		expect(f.state.storeNames[1]).toBe(Configuration.storeName)
		expect(f.api.Load(f.player)).toBe(true)
		expect(f.state.profileKeys).toEqual({ "Player_1001" })
		expect(f.state.profileKeys[1]).toBe(Configuration.profileKeyPrefix .. f.player.UserId)
	end)

	it(
		"preserves personal Shop usage through reconciliation without replicating its ledger",
		function()
			local f = fixture()
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			expect(f.first.profile.Data.shop).toBeNil()
			local saved: Types.ShopState = {
				periodId = 6,
				purchased = { fire_material = 10, featured_sword = 1, retired_offer = 2 },
			}
			expect(f.api.Update(f.player, "Test.ShopUsage", function(draft)
				draft.shop = copy(saved)
				return { ok = true }
			end).ok).toBe(true)
			f.api.Release(f.player)
			f.second.profile.Data = copy(f.first.profile.Data)
			expect(f.api.Load(f.player)).toBe(true)
			expect(f.second.profile.Data.shop).toEqual(saved)
			local now = 6 * 3_600 + 1
			local shop = ShopCommands.new(f.api, {
				clock = function()
					return now
				end,
			})
			local current =
				assert(shop.Get(f.player).view, "[DataServiceLifecycle.spec] Expected Shop view")
			expect(current.offers[1].remainingStock).toBe(0)
			expect(current.offers[7].remainingStock).toBe(0)
			now = 20 * 3_600
			local refreshed = assert(
				shop.Get(f.player).view,
				"[DataServiceLifecycle.spec] Expected refreshed view"
			)
			expect(refreshed.offers[1].remainingStock).toBe(10)
			expect(refreshed.offers[7].remainingStock).toBe(1)
			expect(f.second.profile.Data.shop).toEqual(saved)
			for _, packet in f.state.packets do
				expect(packet.values.shop).toBeNil()
			end
		end
	)

	for _, removeOwnership in { false, true } do
		it(
			`preserves empty slots across reconnect reconciliation (missing ownership: {removeOwnership})`,
			function()
				local f = fixture()
				f.api.Start()
				expect(f.api.Load(f.player)).toBe(true)
				local data = f.first.profile.Data
				expect(data.equipment.starter_wooden_sword.isStarterGrant).toBe(true)
				expect(data.combatLoadout.primaryWeaponInstanceId).toBe("starter_wooden_sword")
				expect(f.api.Update(f.player, "Test.EmptyLoadout", function(draft)
					draft.combatLoadout.primaryWeaponInstanceId = nil
					draft.combatLoadout.shieldInstanceId = nil
					return { ok = true }
				end).ok).toBe(true)
				f.api.Release(f.player)
				f.second.profile.Data = copy(data)
				if removeOwnership then
					-- Simulate an established retained profile, never an allowed destructive command.
					table.clear(f.second.profile.Data.equipment)
				end
				local expectedEquipment = copy(f.second.profile.Data.equipment)
				expect(f.api.Load(f.player)).toBe(true)
				expect(f.second.state.reconcileCalls).toBe(1)
				expect(f.second.profile.Data.combatLoadout).toEqual({})
				expect(f.second.profile.Data.equipment).toEqual(expectedEquipment)
			end
		)
	end

	it(
		"delivers a saved due crafting promise before first publication without exposing its receipt",
		function()
			local f = fixture()
			f.first.profile.Data.craftingJobs = {
				retained = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
					receipt = {
						version = 1,
						recipeId = "old_recipe",
						stationId = "old_station",
						craftingStationId = "basic_crafting_station",
						startedAt = 1,
						completesAt = 2,
						result = {
							definitionId = "elemental_sword",
							finishId = "fire",
							quantity = 1,
							instanceIds = { "promised_sword" },
						},
						paid = { gold = 50, materials = { fire_material = 5 } },
					},
				},
			}
			local jobs = CraftingJobs.new()
			f.api.RegisterMutationPreparation("Crafting", jobs.SettleDueToDraft)
			f.api.RegisterProfileSettlement("Crafting", function(draft, now)
				return jobs.SettleDueToDraft(draft, now)
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			local data = f.first.profile.Data
			local savedJobs =
				assert(data.craftingJobs, "[DataServiceLifecycle.spec] Expected saved jobs")
			expect(savedJobs.retained.status).toBe("Completed")
			expect(savedJobs.retained.reservations.equipment).toBe(0)
			expect(data.equipment.promised_sword).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
			expect(data.currency.gold).toBe(100)
			expect(data.materials.fire_material).toBeNil()
			expect(f.state.packets[1].values.equipment.promised_sword).toEqual(
				data.equipment.promised_sword
			)
			expect(f.state.packets[1].values.craftingJobs).toBeNil()
			local retained = copy(savedJobs.retained)
			expect(f.api.Checkpoint(f.player).ok).toBe(true)
			expect(savedJobs.retained).toEqual(retained)
			f.api.Release(f.player)
			expect(savedJobs.retained).toEqual(retained)
		end
	)

	it("prepares and mutates one draft at one time with one published revision", function()
		local f = fixture()
		local calls = 0
		local preparedAt: number? = nil
		f.api.RegisterMutationPreparation("Crafting", function(draft, now)
			calls += 1
			preparedAt = now
			draft.currency.gold += 10
			return { ok = true }
		end)
		f.api.Start()
		expect(f.api.Load(f.player)).toBe(true)
		expect(calls).toBe(0)
		local data = f.first.profile.Data
		local revision = Transactions.GetRevision(data)
		local request = {
			id = `{revision}:prepared`,
			expectedRevision = revision,
			operation = "Test.Prepared",
			signature = "amount=5",
		}
		local function mutate(draft: Types.PlayerDoc, now: number): Types.TransactionOutcome
			expect(now).toBe(preparedAt)
			expect(now > 0).toBe(true)
			expect(draft.currency.gold).toBe(110)
			draft.currency.gold -= 5
			return { ok = true }
		end
		expect(f.api.Transact(f.player, request, mutate).ok).toBe(true)
		expect(data.currency.gold).toBe(105)
		expect(Transactions.GetRevision(data)).toBe(revision + 1)
		expect(calls).toBe(1)
		expect(#f.state.packets).toBe(2)
		expect(f.state.packets[2].values.currency.gold).toBe(105)
		expect(f.api.Transact(f.player, request, mutate).replayed).toBe(true)
		local conflict = table.clone(request)
		conflict.signature = "amount=6"
		expect(f.api.Transact(f.player, conflict, mutate).code).toBe("RequestConflict")
		local stale = table.clone(request)
		stale.id = `{revision}:stale`
		expect(f.api.Transact(f.player, stale, mutate).code).toBe("StaleRevision")
		expect(calls).toBe(1)
		expect(data.currency.gold).toBe(105)
	end)

	it("prepares Update but does not silently extend the legacy MarkDirty contract", function()
		local f = fixture()
		local calls = 0
		local preparedAt: number? = nil
		f.api.RegisterMutationPreparation("Crafting", function(draft, now)
			calls += 1
			preparedAt = now
			draft.currency.gold += 10
			return { ok = true }
		end)
		f.api.Start()
		expect(f.api.Load(f.player)).toBe(true)
		expect(f.api.MarkDirty(f.player)).toBe(true)
		expect(calls).toBe(0)
		expect(f.api.Update(f.player, "Test.Update", function(draft, now)
			expect(now).toBe(preparedAt)
			expect(draft.currency.gold).toBe(110)
			return { ok = true }
		end).ok).toBe(true)
		expect(calls).toBe(1)
		expect(f.first.profile.Data.currency.gold).toBe(110)
	end)

	it("seals mutation preparations before admitting profiles", function()
		local f = fixture()
		local hook: ServerTypes.MutationPreparation = function()
			return { ok = true }
		end
		f.api.RegisterMutationPreparation("Crafting", hook)
		expect(function()
			f.api.RegisterMutationPreparation("Crafting", hook)
		end).toThrow()
		f.api.Start()
		expect(function()
			f.api.RegisterMutationPreparation("Late", hook)
		end).toThrow()
	end)

	for _, failure in
		{
			"PreparationReject",
			"PreparationError",
			"PreparationYield",
			"ActionReject",
			"SessionLoss",
		}
	do
		it(`rolls back prepared changes on {failure}`, function()
			local f = fixture()
			local actionCalls = 0
			f.api.RegisterMutationPreparation("Crafting", function(draft)
				draft.currency.gold = 999
				if failure == "PreparationReject" then
					return { ok = false, code = "UnsafePreparation" }
				elseif failure == "PreparationError" then
					error("[DataServiceLifecycle.spec] deliberate preparation error")
				elseif failure == "PreparationYield" then
					coroutine.yield()
				end
				return { ok = true }
			end)
			f.api.Start()
			expect(f.api.Load(f.player)).toBe(true)
			local result = f.api.Update(f.player, "Test.Rollback", function(draft)
				actionCalls += 1
				expect(draft.currency.gold).toBe(999)
				draft.currency.gold = 555
				if failure == "SessionLoss" then
					f.first.state.active = false
					return { ok = true }
				end
				return { ok = false, code = "ActionRejected" }
			end)
			local expectedCodes: { [string]: string } = {
				PreparationReject = "UnsafePreparation",
				PreparationError = "MutationFailed",
				PreparationYield = "MutationYielded",
				ActionReject = "ActionRejected",
				SessionLoss = "DataUnavailable",
			}
			expect(result.ok).toBe(false)
			expect(result.code).toBe(expectedCodes[failure])
			expect(actionCalls).toBe(
				if failure == "ActionReject" or failure == "SessionLoss" then 1 else 0
			)
			expect(f.first.profile.Data.currency.gold).toBe(100)
		end)
	end

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
