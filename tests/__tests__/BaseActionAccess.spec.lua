--!strict
-- ServerStorage/Tests/__tests__/BaseActionAccess.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseView = require(ServerScriptService.Services.BaseService.BaseView)
local ShrineConstruction = require(ServerScriptService.Services.BaseService.ShrineConstruction)
local BaseExpansionPurchase =
	require(ServerScriptService.Services.BaseService.BaseExpansionPurchase)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
local MATERIALS = {
	"air_material",
	"dark_material",
	"earth_material",
	"fire_material",
	"light_material",
	"water_material",
}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function build(revision: number, token: string): Types.BuildShrineRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineId = "fire_shrine",
		expectedGoldCost = 100,
	}
end

local function expand(revision: number, token: string): Types.ExpandBaseRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		expectedUpgradeCount = 0,
		expectedGoldCost = 10_000,
		expectedMaterialQuantity = 50,
	}
end

local function fixture(useAccess: boolean?)
	local data = copy(PlayerDataTemplate)
	assert(ProfileSchema.Prepare(data, function()
		return "base_station"
	end, 0))
	data.currency.gold = 1_000_000
	for _, materialId in MATERIALS do
		data.materials[materialId] = { total = 1_000 }
	end
	-- These private helpers receive an opaque caller token, not a fabricated engine Player.
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		now = 20,
		loaded = true,
		active = true,
		accessCode = nil :: string?,
		accessMode = "normal",
		ids = 0,
		preparations = 0,
		accesses = {} :: { { data: Types.PlayerDoc, outputPrepared: boolean } },
	}
	local jobs = CraftingJobs.new()
	local source: ShrineConstruction.DataSource = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			expect(caller).toBe(player)
			return if state.loaded and state.active then data else nil
		end,
		Transact = function(caller, request, mutation)
			expect(caller).toBe(player)
			return Transactions.Run(data, request, function(draft)
				-- Match DataService: due promises and the action share a draft and timestamp.
				state.preparations += 1
				local settled = jobs.SettleDueToDraft(draft, state.now)
				if not settled.ok then
					return settled
				end
				return mutation(draft, state.now)
			end, function()
				return state.active
			end)
		end,
	}
	local function access(caller: Player, selectedData: Types.PlayerDoc): string?
		expect(caller).toBe(player)
		table.insert(state.accesses, {
			data = selectedData,
			outputPrepared = selectedData.equipment.promised_output ~= nil,
		})
		if state.accessMode == "throw" then
			error("Injected Base access failure")
		elseif state.accessMode == "yield" then
			coroutine.yield()
		end
		return state.accessCode
	end
	local checkAccess = if useAccess == false then nil else access
	return {
		data = data,
		player = player,
		state = state,
		view = BaseView.new(source, checkAccess),
		build = ShrineConstruction.new(source, function()
			state.ids += 1
			return `new_shrine_{state.ids}`
		end, checkAccess),
		expand = BaseExpansionPurchase.new(source, checkAccess),
	}
end

local function seedDuePromise(data: Types.PlayerDoc)
	data.craftingJobs = {
		due_job = {
			status = "Active",
			reservations = { equipment = 1, materials = { fire_material = 5 } },
			receipt = {
				version = 1,
				recipeId = "elemental_sword_fire",
				stationId = "base_station",
				craftingStationId = "basic_crafting_station",
				startedAt = 0,
				completesAt = 10,
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
	local shrines = assert(data.base.shrines, "Expected prepared Shrine map")
	shrines.retained_shrine = {
		id = "retained_shrine",
		shrineId = "water_shrine",
		buildSlotId = 1,
		level = 1,
		stored = 123,
		progress = 0.5,
		newWork = 0.25,
		workerIdsBySlot = {},
	}
end

describe("Base action access boundary", function()
	it("checks read access after loaded revision but before projecting saved state", function()
		local f = fixture()
		f.state.accessCode = "OutOfRange"
		f.state.loaded = false
		expect(f.view.Get(f.player)).toEqual({ ok = false, code = "DataUnavailable", revision = 0 })
		f.state.loaded = true
		f.data.transactions = { revision = -1, receipts = {} }
		expect(f.view.Get(f.player)).toEqual({
			ok = false,
			code = "InvalidTransaction",
			revision = -1,
		})
		expect(#f.state.accesses).toBe(0)
		f.data.transactions = { revision = 7, receipts = {} }
		local savedBase = f.data.base
		local raw = f.data :: any
		raw.base = nil
		local before = copy(f.data)
		expect(f.view.Get(f.player)).toEqual({ ok = false, code = "OutOfRange", revision = 7 })
		expect(#f.state.accesses).toBe(1)
		expect(f.state.accesses[1].data).toBe(f.data)
		expect(f.state.preparations + f.state.ids).toBe(0)
		expect(f.data).toEqual(before)
		f.state.accessCode = nil
		expect(f.view.Get(f.player).code).toBe("InvalidBaseState")
		f.data.base = savedBase
		expect(f.view.Get(f.player).ok).toBe(true)
		expect(f.state.preparations + f.state.ids).toBe(0)
	end)

	it(
		"checks allowed mutations only against the draft and keeps an optional headless path",
		function()
			local f = fixture()
			expect(f.build.Build(f.player, build(0, "build")).ok).toBe(true)
			expect(f.expand.Expand(f.player, expand(1, "expand")).ok).toBe(true)
			expect(#f.state.accesses).toBe(2)
			for _, call in f.state.accesses do
				expect(call.data == f.data).toBe(false)
			end
			expect(f.state.preparations).toBe(2)
			expect(f.state.ids).toBe(1)
			expect(f.data.currency.gold).toBe(989_900)
			expect(f.data.base.buildSlotUpgrades).toBe(1)
			for _, materialId in MATERIALS do
				expect(f.data.materials[materialId].total).toBe(950)
			end
			local headless = fixture(false)
			headless.state.accessCode = "OutOfRange"
			expect(headless.view.Get(headless.player).ok).toBe(true)
			expect(headless.build.Build(headless.player, build(0, "headless_build")).ok).toBe(true)
			expect(headless.expand.Expand(headless.player, expand(1, "headless_expand")).ok).toBe(
				true
			)
			expect(#headless.state.accesses).toBe(0)
		end
	)

	it(
		"replays original purchases without access or preparation after access and Base loss",
		function()
			for _, accessCode in { "OutOfRange", "CharacterUnavailable", "BaseUnavailable" } do
				local f = fixture()
				local buildRequest, expandRequest = build(0, "build"), expand(1, "expand")
				local built = f.build.Build(f.player, buildRequest)
				local expanded = f.expand.Expand(f.player, expandRequest)
				expect(built.ok and expanded.ok).toBe(true)
				f.state.accessCode, f.state.now = accessCode, 100_000
				-- Inject current-world failures; no live character or spatial behavior is claimed here.
				local raw = f.data :: any
				raw.base = nil
				local before = copy(f.data)
				expect(f.build.Build(f.player, buildRequest)).toEqual({
					ok = true,
					revision = built.revision,
					values = built.values,
					replayed = true,
				})
				expect(f.expand.Expand(f.player, expandRequest)).toEqual({
					ok = true,
					revision = expanded.revision,
					values = expanded.values,
					replayed = true,
				})
				expect(#f.state.accesses).toBe(2)
				expect(f.state.preparations).toBe(2)
				expect(f.state.ids).toBe(1)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"rolls back due output and all gameplay on denial while preserving its rejection receipt",
		function()
			for _, isExpansion in { false, true } do
				local f = fixture()
				seedDuePromise(f.data)
				f.state.accessCode = "OutOfRange"
				local before = gameplay(f.data)
				local buildRequest, expandRequest = build(0, "denied"), expand(0, "denied")
				local function execute(): Types.TransactionResult
					return if isExpansion
						then f.expand.Expand(f.player, expandRequest)
						else f.build.Build(f.player, buildRequest)
				end
				expect(execute()).toEqual({ ok = false, code = "OutOfRange", revision = 1 })
				expect(f.state.accesses[1].outputPrepared).toBe(true)
				expect(f.state.accesses[1].data == f.data).toBe(false)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.data.equipment.promised_output).toBeNil()
				expect(f.state.ids).toBe(0)
				f.state.accessCode = nil
				expect(execute()).toEqual({
					ok = false,
					code = "OutOfRange",
					revision = 1,
					replayed = true,
				})
				expect(#f.state.accesses).toBe(1)
				expect(f.state.preparations).toBe(1)
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it("does not evaluate access for conflicting, stale or malformed mutation requests", function()
		local f = fixture()
		local selected = build(0, "build")
		expect(f.build.Build(f.player, selected).ok).toBe(true)
		f.state.accessCode = "OutOfRange"
		local changed = table.clone(selected)
		changed.shrineId = "water_shrine"
		expect(f.build.Build(f.player, changed).code).toBe("RequestConflict")
		expect(f.expand.Expand(f.player, expand(0, "build")).code).toBe("RequestConflict")
		expect(f.build.Build(f.player, build(0, "stale")).code).toBe("StaleRevision")
		expect(f.expand.Expand(f.player, expand(0, "stale")).code).toBe("StaleRevision")
		local forgedBuild: any = build(1, "forged")
		forgedBuild.targetUserId = 9001
		expect(f.build.Build(f.player, forgedBuild).code).toBe("InvalidRequest")
		local forgedExpansion: any = expand(1, "forged")
		forgedExpansion.buildSlotId = 6
		expect(f.expand.Expand(f.player, forgedExpansion).code).toBe("InvalidRequest")
		expect(#f.state.accesses).toBe(1)
		expect(f.state.preparations).toBe(1)
		expect(f.state.ids).toBe(1)
	end)

	it(
		"contains throwing or yielding access in the same atomic boundary as due preparation",
		function()
			for _, mode in { "throw", "yield" } do
				for _, isExpansion in { false, true } do
					local f = fixture()
					seedDuePromise(f.data)
					f.state.accessMode = mode
					local before = copy(f.data)
					local result = if isExpansion
						then f.expand.Expand(f.player, expand(0, "failed"))
						else f.build.Build(f.player, build(0, "failed"))
					expect(result.code).toBe(
						if mode == "throw" then "MutationFailed" else "MutationYielded"
					)
					expect(f.state.accesses[1].outputPrepared).toBe(true)
					expect(f.data).toEqual(before)
					expect(f.state.ids).toBe(0)
				end
			end
		end
	)
end)
