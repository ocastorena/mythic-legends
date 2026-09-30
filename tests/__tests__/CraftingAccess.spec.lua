--!strict
-- ServerStorage/Tests/__tests__/CraftingAccess.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local CraftingCommands = require(ServerScriptService.Services.CraftingService.CraftingCommands)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function start(revision: number, token: string): Types.StartCraftingRequest
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		stationInstanceId = "craft_station",
		recipeId = "elemental_sword_fire",
		expectedGoldCost = 50,
		expectedMaterialId = "fire_material",
		expectedMaterialQuantity = 5,
		expectedDefinitionId = "elemental_sword",
		expectedFinishId = "fire",
		expectedQuantity = 1,
		expectedDurationSeconds = 60,
	}
end

local function cancel(revision: number, token: string, id: string): Types.CancelCraftingRequest
	return { requestId = `{revision}:{token}`, expectedRevision = revision, jobId = id }
end

local function fixture(useAccess: boolean?)
	local data = copy(PlayerDataTemplate)
	assert(ProfileSchema.Prepare(data, function()
		return "craft_station"
	end, 0))
	data.currency.gold = 1_000
	data.materials.fire_material = { total = 100 }
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		now = 10,
		loaded = true,
		active = true,
		accessCode = nil :: string?,
		accessMode = "normal",
		clocks = 0,
		viewReads = 0,
		ids = 0,
		preparations = 0,
		accesses = {} :: { { data: Types.PlayerDoc, stationId: string?, outputPrepared: boolean } },
	}
	local jobs = CraftingJobs.new({
		createId = function(prefix: string): string
			state.ids += 1
			return `{prefix}_{state.ids}`
		end,
	})
	local observedJobs: CraftingJobs.CraftingJobs = {
		SettleDueToDraft = jobs.SettleDueToDraft,
		StartToDraft = jobs.StartToDraft,
		CancelToDraft = jobs.CancelToDraft,
		ReadStation = function(saved, now, stationId)
			state.viewReads += 1
			return jobs.ReadStation(saved, now, stationId)
		end,
	}
	local source: CraftingCommands.DataSource = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			expect(caller).toBe(player)
			return if state.loaded and state.active then data else nil
		end,
		Transact = function(caller, request, mutation)
			expect(caller).toBe(player)
			return Transactions.Run(data, request, function(draft)
				-- Match DataService: preparation and command share one timestamp and rollback boundary.
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
	local function access(
		caller: Player,
		selectedData: Types.PlayerDoc,
		stationId: string?
	): string?
		expect(caller).toBe(player)
		table.insert(state.accesses, {
			data = selectedData,
			stationId = stationId,
			outputPrepared = selectedData.equipment.equipment_2 ~= nil,
		})
		if state.accessMode == "throw" then
			error("Injected access failure")
		elseif state.accessMode == "yield" then
			coroutine.yield()
		end
		return state.accessCode
	end
	local commands = CraftingCommands.new(source, observedJobs, function()
		state.clocks += 1
		return state.now
	end, if useAccess == false then nil else access)
	return { data = data, player = player, state = state, api = commands }
end

local function jobId(result: Types.TransactionResult): string
	local values = assert(result.values, "Expected start values")
	assert(type(values.jobId) == "string", "Expected job identity")
	return values.jobId
end

describe("Crafting access boundary", function()
	it(
		"admits station reads only after profile, revision and payload checks but before clock or projection",
		function()
			local f = fixture()
			f.state.accessCode = "OutOfRange"
			f.state.loaded = false
			expect(f.api.GetStation(f.player, { stationInstanceId = "craft_station" }).code).toBe(
				"DataUnavailable"
			)
			f.state.loaded = true
			f.data.transactions = { revision = -1, receipts = {} }
			expect(f.api.GetStation(f.player, { stationInstanceId = "craft_station" }).code).toBe(
				"InvalidTransaction"
			)
			f.data.transactions = { revision = 7, receipts = {} }
			local forged: any = { stationInstanceId = "craft_station", targetUserId = 9001 }
			expect(f.api.GetStation(f.player, forged).code).toBe("InvalidRequest")
			expect(#f.state.accesses).toBe(0)
			local before = copy(f.data)
			expect(f.api.GetStation(f.player, { stationInstanceId = "craft_station" })).toEqual({
				ok = false,
				code = "OutOfRange",
				revision = 7,
			})
			expect(#f.state.accesses).toBe(1)
			expect(f.state.accesses[1].data).toBe(f.data)
			expect(f.state.accesses[1].stationId).toBe("craft_station")
			expect(f.state.clocks + f.state.viewReads + f.state.ids + f.state.preparations).toBe(0)
			expect(f.data).toEqual(before)
			f.state.accessCode = nil
			expect(f.api.GetStation(f.player, { stationInstanceId = "craft_station" }).ok).toBe(
				true
			)
			expect(f.state.clocks).toBe(1)
			expect(f.state.viewReads).toBe(1)
		end
	)

	it(
		"checks exact Start selection and saved-station Cancel access only inside the transaction draft",
		function()
			local f = fixture()
			local started = f.api.Start(f.player, start(0, "start"))
			expect(started.ok).toBe(true)
			local id = jobId(started)
			expect(#f.state.accesses).toBe(1)
			expect(f.state.accesses[1].data == f.data).toBe(false)
			expect(f.state.accesses[1].stationId).toBe("craft_station")
			expect(f.api.Cancel(f.player, cancel(1, "cancel", id)).ok).toBe(true)
			expect(#f.state.accesses).toBe(2)
			expect(f.state.accesses[2].data == f.data).toBe(false)
			expect(f.state.accesses[2].stationId).toBeNil()
			local station = assert(
				f.state.accesses[2].data.base.craftingStation,
				"Expected saved permanent station"
			)
			expect(station.id).toBe("craft_station")
			expect(f.data.currency.gold).toBe(1_000)
			expect(f.data.materials.fire_material.total).toBe(100)
			expect(f.state.ids).toBe(2)
			expect(f.state.clocks + f.state.viewReads).toBe(0)
			local headless = fixture(false)
			headless.state.accessCode = "OutOfRange"
			expect(headless.api.Start(headless.player, start(0, "headless")).ok).toBe(true)
			expect(#headless.state.accesses).toBe(0)
		end
	)

	it(
		"replays successful starts and cancels after access loss, reset and removed station or job",
		function()
			for _, accessCode in { "OutOfRange", "CharacterUnavailable", "StationUnavailable" } do
				local f = fixture()
				local startRequest = start(0, "start")
				local started = f.api.Start(f.player, startRequest)
				local cancelRequest = cancel(1, "cancel", jobId(started))
				local cancelled = f.api.Cancel(f.player, cancelRequest)
				expect(cancelled.ok).toBe(true)
				f.state.accessCode = accessCode
				f.state.now = 100_000
				-- A replaced world/character and pruned saved history cannot rewrite recorded outcomes.
				local raw = f.data :: any
				raw.base.craftingStation = nil
				f.data.craftingJobs = nil
				local before = copy(f.data)
				expect(f.api.Start(f.player, startRequest)).toEqual({
					ok = true,
					revision = started.revision,
					values = started.values,
					replayed = true,
				})
				expect(f.api.Cancel(f.player, cancelRequest)).toEqual({
					ok = true,
					revision = cancelled.revision,
					values = cancelled.values,
					replayed = true,
				})
				expect(#f.state.accesses).toBe(2)
				expect(f.state.preparations).toBe(2)
				expect(f.state.ids).toBe(2)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"rolls back due preparation and every gameplay edit when a fresh Start or Cancel is denied",
		function()
			for _, isCancel in { false, true } do
				local f = fixture()
				local id = jobId(f.api.Start(f.player, start(0, "seed")))
				f.state.now, f.state.accessCode = 70, "OutOfRange"
				local before = gameplay(f.data)
				local selectedStart, selectedCancel = start(1, "denied"), cancel(1, "denied", id)
				local function execute(): Types.TransactionResult
					return if isCancel
						then f.api.Cancel(f.player, selectedCancel)
						else f.api.Start(f.player, selectedStart)
				end
				local denied = execute()
				expect(denied).toEqual({ ok = false, code = "OutOfRange", revision = 2 })
				expect(f.state.accesses[2].outputPrepared).toBe(true)
				expect(f.state.accesses[2].stationId).toBe(
					if isCancel then nil else "craft_station"
				)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.data.equipment.equipment_2).toBeNil()
				expect(f.state.ids).toBe(2)
				f.state.accessCode = nil
				expect(execute()).toEqual({
					ok = false,
					code = "OutOfRange",
					revision = 2,
					replayed = true,
				})
				expect(#f.state.accesses).toBe(2)
				expect(f.state.preparations).toBe(2)
				expect(gameplay(f.data)).toEqual(before)
			end
			local fresh = fixture()
			fresh.state.accessCode = "OutOfRange"
			local before = gameplay(fresh.data)
			expect(fresh.api.Start(fresh.player, start(0, "denied")).code).toBe("OutOfRange")
			expect(fresh.state.ids).toBe(0)
			expect(gameplay(fresh.data)).toEqual(before)
		end
	)

	it("does not evaluate access for conflicting, stale or malformed mutation envelopes", function()
		local f = fixture()
		local selected = start(0, "start")
		local id = jobId(f.api.Start(f.player, selected))
		f.state.accessCode = "OutOfRange"
		local changed = table.clone(selected)
		changed.stationInstanceId = "another_station"
		expect(f.api.Start(f.player, changed).code).toBe("RequestConflict")
		expect(f.api.Cancel(f.player, cancel(0, "start", id)).code).toBe("RequestConflict")
		expect(f.api.Start(f.player, start(0, "stale")).code).toBe("StaleRevision")
		expect(f.api.Cancel(f.player, cancel(0, "stale", id)).code).toBe("StaleRevision")
		local forgedStart: any = start(1, "forged")
		forgedStart.targetUserId = 9001
		expect(f.api.Start(f.player, forgedStart).code).toBe("InvalidRequest")
		local forgedCancel: any = cancel(1, "forged", id)
		forgedCancel.stationInstanceId = "craft_station"
		expect(f.api.Cancel(f.player, forgedCancel).code).toBe("InvalidRequest")
		expect(#f.state.accesses).toBe(1)
		expect(f.state.preparations).toBe(1)
		expect(f.state.ids).toBe(2)
	end)

	it(
		"contains throwing or yielding access checks inside the same atomic mutation boundary",
		function()
			for _, mode in { "throw", "yield" } do
				local f = fixture()
				local id = jobId(f.api.Start(f.player, start(0, "seed")))
				f.state.now, f.state.accessMode = 70, mode
				local before = copy(f.data)
				expect(f.api.Cancel(f.player, cancel(1, "failed", id)).code).toBe(
					if mode == "throw" then "MutationFailed" else "MutationYielded"
				)
				expect(f.state.accesses[2].outputPrepared).toBe(true)
				expect(f.data).toEqual(before)
				expect(f.state.ids).toBe(2)
			end
		end
	)
end)
