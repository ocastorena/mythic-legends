--!strict
-- ServerStorage/Tests/__tests__/CraftingService.spec

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Crafting = require(ReplicatedStorage.Shared.Configurations.Crafting)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local schedulerModule = ServerScriptService.Services.CraftingService.DueJobs
local cleanup: { () -> () } = {}

type Service = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	StartJob: (Player, Types.StartCraftingRequest) -> Types.TransactionResult,
	CancelJob: (Player, Types.CancelCraftingRequest) -> Types.TransactionResult,
}

local function profile(): Types.PlayerDoc
	local data: Types.PlayerDoc = HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate))
	local ready = ProfileSchema.Prepare(data, function()
		return "craft_station"
	end, 0)
	assert(ready, "[CraftingService.spec] Fixture preparation failed")
	data.currency.gold = 50
	data.craftingJobs = {
		job = {
			status = "Active",
			reservations = { equipment = 1, materials = { fire_material = 5 } },
			receipt = {
				version = 1,
				recipeId = "elemental_sword_fire",
				stationId = "craft_station",
				craftingStationId = "basic_crafting_station",
				startedAt = 0,
				completesAt = 60,
				result = {
					definitionId = "elemental_sword",
					finishId = "fire",
					quantity = 1,
					instanceIds = { "promised_output" },
				},
				paid = { gold = 50, materials = { fire_material = 5 } },
			},
		},
	}
	return data
end

local function fixture()
	local state = {
		reads = 0,
		transactions = 0,
		ticks = 0,
		schedulerCalls = 0,
		interval = 0,
		registrations = {} :: { string },
		preparation = nil :: ServerTypes.MutationPreparation?,
		settlement = nil :: ServerTypes.ProfileSettlement?,
	}
	local source = {
		GetLoadedData = function(_player: Player): Types.PlayerDoc?
			state.reads += 1
			return nil
		end,
		Transact = function(): Types.TransactionResult
			state.transactions += 1
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end,
		Update = function(): Types.TransactionResult
			state.transactions += 1
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end,
		RegisterMutationPreparation = function(
			owner: string,
			hook: ServerTypes.MutationPreparation
		)
			table.insert(state.registrations, `prepare:{owner}`)
			state.preparation = hook
		end,
		RegisterProfileSettlement = function(owner: string, hook: ServerTypes.ProfileSettlement)
			table.insert(state.registrations, `settle:{owner}`)
			state.settlement = hook
		end,
	}
	jest.mock(schedulerModule, function()
		return {
			new = function(
				dataSource: unknown,
				players: () -> { Player },
				interval: number,
				clock: unknown
			)
				expect(dataSource).toBe(source)
				expect(type(players())).toBe("table")
				expect(clock).toBeNil()
				state.schedulerCalls += 1
				state.interval = interval
				return {
					Step = function(_delta: number)
						state.ticks += 1
					end,
				}
			end,
		}
	end)
	local service: Service? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> Service
		service = loadService(ServerScriptService.Services.CraftingService)
	end)
	local api = assert(service, "[CraftingService.spec] Expected isolated service")
	table.insert(cleanup, api.Stop)
	return {
		api = api,
		state = state,
		context = ({ Services = { DataService = source } } :: unknown) :: ServerTypes.Context,
	}
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(schedulerModule)
end)

describe("CraftingService", function()
	it("registers both pure hooks once during Init and retains them after terminal Stop", function()
		local f = fixture()
		f.api.Init(f.context)
		expect(f.state.registrations).toEqual({ "prepare:Crafting", "settle:Crafting" })
		expect(f.state.schedulerCalls).toBe(1)
		expect(f.state.interval).toBe(Crafting.resolutionIntervalSeconds)
		f.api.Start()
		f.api.Start()
		f.api.Stop()
		f.api.Stop()
		local prepare = assert(f.state.preparation, "[CraftingService.spec] Expected preparation")
		local settle = assert(f.state.settlement, "[CraftingService.spec] Expected settlement")
		local first, second = profile(), profile()
		expect(prepare(first, 60).ok).toBe(true)
		expect(settle(second, 60, "Release").ok).toBe(true)
		for _, data in { first, second } do
			local jobs = assert(data.craftingJobs, "[CraftingService.spec] Expected jobs")
			expect(jobs.job.status).toBe("Completed")
			expect(jobs.job.reservations).toEqual({ equipment = 0, materials = {} })
			expect(data.equipment.promised_output).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
			expect(data.currency.gold).toBe(50)
		end
		expect(f.state.reads).toBe(0)
		expect(f.state.transactions).toBe(0)
		expect(function()
			f.api.Start()
		end).toThrow()
	end)

	it(
		"rejects stopped services and non-Player callers without reading or transacting profiles",
		function()
			local f = fixture()
			local folder = Instance.new("Folder")
			table.insert(cleanup, function()
				folder:Destroy()
			end)
			local fakePlayer = { UserId = 1001, Parent = Players }
			local function unavailable()
				for _, raw in { fakePlayer, folder, false } do
					local player = (raw :: unknown) :: Player
					expect(f.api.StartJob(player, ({} :: unknown) :: Types.StartCraftingRequest)).toEqual({
						ok = false,
						code = "DataUnavailable",
						revision = 0,
					})
					expect(f.api.CancelJob(player, ({} :: unknown) :: Types.CancelCraftingRequest)).toEqual({
						ok = false,
						code = "DataUnavailable",
						revision = 0,
					})
				end
				expect(f.state.reads).toBe(0)
				expect(f.state.transactions).toBe(0)
			end
			unavailable()
			f.api.Init(f.context)
			unavailable()
			f.api.Start()
			unavailable()
			f.api.Stop()
			unavailable()
		end
	)

	it(
		"uses identical saved deadlines for Ready, Checkpoint, Release, and mutation preparation",
		function()
			local f = fixture()
			f.api.Init(f.context)
			local settle = assert(f.state.settlement, "[CraftingService.spec] Expected settlement")
			local prepare =
				assert(f.state.preparation, "[CraftingService.spec] Expected preparation")
			local boundaries: { ServerTypes.ProfileBoundary } = { "Ready", "Checkpoint", "Release" }
			for _, boundary in boundaries do
				local data = profile()
				expect(settle(data, 59, boundary).ok).toBe(true)
				expect(data.equipment.promised_output).toBeNil()
				expect(settle(data, 60, boundary).ok).toBe(true)
				expect(prepare(data, 100).ok).toBe(true)
				local jobs = assert(data.craftingJobs, "[CraftingService.spec] Expected jobs")
				local receipt = assert(jobs.job.receipt, "[CraftingService.spec] Expected receipt")
				expect(receipt.resolvedAt).toBe(60)
			end
		end
	)
end)
