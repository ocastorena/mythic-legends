--!strict
-- ServerStorage/Tests/__tests__/CraftingCommands.spec

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

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

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

local function cancel(revision: number, token: string, jobId: string): Types.CancelCraftingRequest
	return { requestId = `{revision}:{token}`, expectedRevision = revision, jobId = jobId }
end

local function fixture(saved: Types.PlayerDoc?)
	local data = saved or copy(PlayerDataTemplate)
	if not saved then
		local ready = ProfileSchema.Prepare(data, function()
			return "craft_station"
		end, 0)
		assert(ready, "[CraftingCommands.spec] Fixture preparation failed")
		data.currency.gold = 1_000
		data.materials.fire_material = { total = 100 }
	end
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		now = 10,
		active = true,
		available = true,
		loseSession = false,
		idMode = "normal",
		ids = 0,
		calls = 0,
		mutations = 0,
		operations = {} :: { string },
	}
	local jobs = CraftingJobs.new({
		createId = function(prefix: string): string
			if state.idMode == "error" then
				error("[CraftingCommands.spec] Injected ID failure")
			end
			if state.idMode == "yield" then
				coroutine.yield()
			end
			state.ids += 1
			return `{prefix}_{state.ids}`
		end,
	})
	local source: CraftingCommands.DataSource = {
		GetLoadedData = function(selected: Player): Types.PlayerDoc?
			return if selected == player and state.active and state.available then data else nil
		end,
		Transact = function(selected, request, mutate)
			state.calls += 1
			table.insert(state.operations, request.operation)
			if selected ~= player or not state.available then
				return { ok = false, code = "DataUnavailable", revision = 0 }
			end
			return Transactions.Run(data, request, function(draft)
				-- Match DataService's registered preparation and mutation using one timestamp/draft.
				local settled = jobs.SettleDueToDraft(draft, state.now)
				if not settled.ok then
					return settled
				end
				state.mutations += 1
				local result = mutate(draft, state.now)
				if state.loseSession then
					state.active = false
				end
				return result
			end, function()
				return state.active
			end)
		end,
	}
	return { data = data, player = player, state = state, api = CraftingCommands.new(source, jobs) }
end

local function jobId(result: Types.TransactionResult): string
	local values = assert(result.values, "[CraftingCommands.spec] Expected start result")
	assert(type(values.jobId) == "string", "[CraftingCommands.spec] Expected job ID")
	return values.jobId
end

describe("CraftingCommands", function()
	it(
		"starts and cancels through distinct revision-bound operations with exactly-once charges/refunds",
		function()
			local f = fixture()
			local selected = start(0, "start")
			local started = f.api.Start(f.player, selected)
			expect(started.ok).toBe(true)
			expect(started.revision).toBe(1)
			local id = jobId(started)
			local afterStart = copy(f.data)
			expect(f.api.Start(f.player, selected)).toEqual({
				ok = true,
				revision = 1,
				values = started.values,
				replayed = true,
			})
			expect(f.data).toEqual(afterStart)
			local cancelled = f.api.Cancel(f.player, cancel(1, "cancel", id))
			expect(cancelled).toEqual({
				ok = true,
				revision = 2,
				values = { jobId = id, status = "Cancelled", goldRefunded = 50 },
			})
			expect(f.data.currency.gold).toBe(1_000)
			expect(f.data.materials.fire_material.total).toBe(100)
			local afterCancel = copy(f.data)
			expect(f.api.Cancel(f.player, cancel(1, "cancel", id)).replayed).toBe(true)
			expect(f.data).toEqual(afterCancel)
			expect(f.state.mutations).toBe(2)
			expect(f.state.operations[1]).toBe("Crafting.Start")
			expect(f.state.operations[3]).toBe("Crafting.Cancel")
		end
	)

	it(
		"lets due completion win cancellation inside the same transaction and clock sample",
		function()
			local f = fixture()
			local id = jobId(f.api.Start(f.player, start(0, "start")))
			f.state.now = 70
			expect(f.api.Cancel(f.player, cancel(1, "due", id))).toEqual({
				ok = true,
				revision = 2,
				values = { jobId = id, status = "Completed", goldRefunded = 0 },
			})
			expect(f.data.currency.gold).toBe(950)
			expect(f.data.materials.fire_material.total).toBe(95)
			local job = assert(f.data.craftingJobs, "[CraftingCommands.spec] Expected jobs")[id]
			local receipt = assert(job.receipt, "[CraftingCommands.spec] Expected receipt")
			expect(receipt.resolvedAt).toBe(70)
			expect(f.data.equipment[receipt.result.instanceIds[1]]).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
		end
	)

	it(
		"retains the just-completed job through preparation pruning so boundary cancellation reports completion",
		function()
			local f = fixture()
			local id = jobId(f.api.Start(f.player, start(0, "start")))
			local jobs = assert(f.data.craftingJobs, "[CraftingCommands.spec] Expected jobs")
			local active = jobs[id]
			local receipt = assert(active.receipt, "[CraftingCommands.spec] Expected receipt")
			-- All 32 old results tie the new resolution time. The active target sorts before them,
			-- so naive oldest-first pruning would erase it between preparation and cancellation.
			for index = 1, 32 do
				local historyId = string.format("z_history_%02d", index)
				expect(id < historyId).toBe(true)
				local historical = copy(active)
				historical.status = "Completed"
				historical.reservations = { equipment = 0, materials = {} }
				local historicalReceipt =
					assert(historical.receipt, "[CraftingCommands.spec] Expected history")
				historicalReceipt.resolvedAt = 70
				historicalReceipt.result.instanceIds = { `old_output_{index}` }
				jobs[historyId] = historical
			end
			f.state.now = 70
			expect(f.api.Cancel(f.player, cancel(1, "boundary", id))).toEqual({
				ok = true,
				revision = 2,
				values = { jobId = id, status = "Completed", goldRefunded = 0 },
			})
			expect(jobs[id].status).toBe("Completed")
			expect(f.data.equipment[receipt.result.instanceIds[1]]).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
			expect(f.data.currency.gold).toBe(950)
			expect(f.data.materials.fire_material.total).toBe(95)
			local retained = 0
			for _ in jobs do
				retained += 1
			end
			expect(retained).toBe(32)
		end
	)

	it(
		"settles an old due job before starting another but rolls both changes back on rejection",
		function()
			local f = fixture()
			local first = jobId(f.api.Start(f.player, start(0, "first")))
			f.state.now = 70
			local rejected = start(1, "bad-quote")
			rejected.expectedGoldCost = 49
			local before = gameplay(f.data)
			expect(f.api.Start(f.player, rejected).code).toBe("RecipeChanged")
			expect(gameplay(f.data)).toEqual(before)
			local second = f.api.Start(f.player, start(2, "next"))
			expect(second.ok).toBe(true)
			expect(jobId(second) == first).toBe(false)
			local jobs = assert(f.data.craftingJobs, "[CraftingCommands.spec] Expected jobs")
			expect(jobs[first].status).toBe("Completed")
			expect(jobs[jobId(second)].status).toBe("Active")
			expect(f.data.currency.gold).toBe(900)
			expect(f.data.materials.fire_material.total).toBe(90)
		end
	)

	it(
		"rejects a second unfinished job and preserves that failure receipt after the station becomes idle",
		function()
			local f = fixture()
			local id = jobId(f.api.Start(f.player, start(0, "first")))
			local blocked = start(1, "busy")
			expect(f.api.Start(f.player, blocked).code).toBe("StationBusy")
			expect(f.api.Cancel(f.player, cancel(2, "free", id)).ok).toBe(true)
			local before = copy(f.data)
			expect(f.api.Start(f.player, blocked)).toEqual({
				ok = false,
				code = "StationBusy",
				revision = 2,
				replayed = true,
			})
			expect(f.data).toEqual(before)
		end
	)

	it("binds every quoted input and result to the original start receipt", function()
		local f = fixture()
		local selected = start(0, "binding")
		expect(f.api.Start(f.player, selected).ok).toBe(true)
		local before = copy(f.data)
		local changes: { [string]: string | number } = {
			stationInstanceId = "other_station",
			recipeId = "elemental_shield_fire",
			expectedGoldCost = 51,
			expectedMaterialId = "water_material",
			expectedMaterialQuantity = 6,
			expectedDefinitionId = "elemental_shield",
			expectedFinishId = "water",
			expectedQuantity = 2,
			expectedDurationSeconds = 61,
		}
		for field, value in changes do
			local changed: any = copy(selected)
			changed[field] = value
			expect(f.api.Start(f.player, changed).code).toBe("RequestConflict")
		end
		expect(f.data).toEqual(before)
		expect(f.state.mutations).toBe(1)
		for _, field in { "expectedGoldCost", "expectedMaterialQuantity", "expectedQuantity" } do
			local other = fixture()
			local large: any = start(0, "large")
			large[field] = 2 ^ 52
			expect(other.api.Start(other.player, large).ok).toBe(false)
			large[field] += 1
			expect(other.api.Start(other.player, large).code).toBe("RequestConflict")
		end
	end)

	it("rejects malformed or forged start/cancel envelopes before transaction admission", function()
		local invalid: { any } = { false, setmetatable(start(0, "meta"), {}) }
		for _, field in
			{
				"requestId",
				"expectedRevision",
				"stationInstanceId",
				"recipeId",
				"expectedGoldCost",
				"expectedMaterialId",
				"expectedMaterialQuantity",
				"expectedDefinitionId",
				"expectedFinishId",
				"expectedQuantity",
				"expectedDurationSeconds",
			}
		do
			local selected: any = start(0, "missing")
			selected[field] = nil
			table.insert(invalid, selected)
		end
		for _, field in
			{
				"player",
				"receipt",
				"paid",
				"result",
				"completesAt",
				"status",
				"operation",
				"signature",
			}
		do
			local selected: any = start(0, "extra")
			selected[field] = 1
			table.insert(invalid, selected)
		end
		for _, field in
			{
				"expectedRevision",
				"expectedGoldCost",
				"expectedMaterialQuantity",
				"expectedQuantity",
				"expectedDurationSeconds",
			}
		do
			for _, value in { -1, math.huge, 0 / 0, "50" } do
				local selected: any = start(0, "number")
				selected[field] = value
				table.insert(invalid, selected)
			end
		end
		for _, selected in invalid do
			local f = fixture()
			local before = copy(f.data)
			expect(f.api.Start(f.player, selected).code).toBe("InvalidRequest")
			expect(f.data).toEqual(before)
			expect(f.state.calls).toBe(0)
		end
		for _, selected in
			{
				false,
				{ requestId = "0:bad", expectedRevision = 0, jobId = "" },
				{ requestId = "0:bad", expectedRevision = 0, jobId = "job", refund = 1 },
				{ requestId = "0:bad", expectedRevision = 0 },
			}
		do
			local f = fixture()
			expect(f.api.Cancel(f.player, selected :: any).code).toBe("InvalidRequest")
			expect(f.state.calls).toBe(0)
		end
	end)

	it(
		"restores paid promises and successful receipts across reconnect without duplicate output",
		function()
			local f = fixture()
			local selected = start(0, "persisted")
			local result = f.api.Start(f.player, selected)
			local restored = fixture(copy(f.data))
			expect(restored.api.Start(restored.player, selected)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.state.ids).toBe(0)
			restored.state.now = 10_000
			local resolved =
				restored.api.Cancel(restored.player, cancel(1, "offline", jobId(result)))
			expect(resolved.ok).toBe(true)
			local before = copy(restored.data)
			expect(
				restored.api.Cancel(restored.player, cancel(1, "offline", jobId(result))).replayed
			).toBe(true)
			expect(restored.data).toEqual(before)
			expect(restored.state.ids).toBe(0)
		end
	)

	it(
		"rolls back costs, reservations, output and request receipt when the session is lost",
		function()
			for _, action in { "start", "cancel", "complete" } do
				local f = fixture()
				local id = "unused"
				if action ~= "start" then
					id = jobId(f.api.Start(f.player, start(0, "prior")))
				end
				if action == "complete" then
					f.state.now = 70
				end
				local before = copy(f.data)
				f.state.loseSession = true
				local result = if action == "start"
					then f.api.Start(f.player, start(0, "lost"))
					else f.api.Cancel(f.player, cancel(1, "lost", id))
				expect(result.code).toBe("DataUnavailable")
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"rolls back allocator exceptions or yields instead of persisting partially generated promises",
		function()
			for _, mode in { "error", "yield" } do
				local f = fixture()
				f.state.idMode = mode
				local before = copy(f.data)
				expect(f.api.Start(f.player, start(0, "allocator")).code).toBe(
					if mode == "error" then "MutationFailed" else "MutationYielded"
				)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"rolls back released reservations when an invalid near-limit balance cannot accept its refund",
		function()
			local f = fixture()
			local id = jobId(f.api.Start(f.player, start(0, "start")))
			f.data.currency.gold = 2 ^ 53 - 1 - 49
			local before = gameplay(f.data)
			expect(f.api.Cancel(f.player, cancel(1, "overflow", id)).code).toBe(
				"ArithmeticOverflow"
			)
			expect(gameplay(f.data)).toEqual(before)
		end
	)

	it("rejects unavailable profiles and stale revisions without advancing due jobs", function()
		local f = fixture()
		local before = copy(f.data)
		f.state.available = false
		expect(f.api.Start(f.player, start(0, "unloaded")).code).toBe("DataUnavailable")
		expect(f.state.calls).toBe(0)
		f.state.available = true
		expect(f.api.Start(f.player, start(1, "stale")).code).toBe("StaleRevision")
		expect(f.state.mutations).toBe(0)
		expect(f.data).toEqual(before)
	end)
end)
