--!strict
-- ServerStorage/Tests/__tests__/CraftingStationView.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Recipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local CraftingCommands = require(ServerScriptService.Services.CraftingService.CraftingCommands)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function fixture(recipes: { [string]: Types.EquipmentRecipe }?)
	local data = copy(PlayerDataTemplate)
	assert(ProfileSchema.Prepare(data, function()
		return "craft_station"
	end, 0))
	data.currency.gold = 1_000
	for _, element in { "fire", "water", "earth", "air", "light", "dark" } do
		data.materials[`{element}_material`] = { total = 100 }
	end
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		now = 20,
		loaded = true,
		reads = 0,
		clocks = 0,
		ids = 0,
		transactions = 0,
		loads = 0,
		saves = 0,
	}
	local jobs = CraftingJobs.new({
		recipes = recipes,
		createId = function(prefix: string): string
			state.ids += 1
			return `{prefix}_{state.ids}`
		end,
	})
	local source = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			expect(caller).toBe(player)
			state.reads += 1
			return if state.loaded then data else nil
		end,
		Transact = function(): Types.TransactionResult
			state.transactions += 1
			error("Station reads must never transact")
		end,
		Load = function()
			state.loads += 1
			error("Station reads must never initiate loading")
		end,
		SaveNow = function()
			state.saves += 1
			error("Station reads must never save")
		end,
	}
	local commands = CraftingCommands.new(source, jobs, function()
		state.clocks += 1
		return state.now
	end)
	return {
		data = data,
		player = player,
		state = state,
		jobs = jobs,
		commands = commands,
		source = source,
	}
end

local function startRequest(id: string, revision: number?): Types.StartCraftingRequest
	local recipe = Recipes[id]
	local materialId, amount = next(recipe.materials)
	assert(materialId and amount, "Expected recipe input")
	return {
		requestId = "0:start",
		expectedRevision = revision or 0,
		stationInstanceId = "craft_station",
		recipeId = id,
		expectedGoldCost = recipe.goldCost,
		expectedMaterialId = materialId,
		expectedMaterialQuantity = amount,
		expectedDefinitionId = recipe.resultDefinitionId,
		expectedFinishId = recipe.resultFinishId,
		expectedQuantity = recipe.quantity,
		expectedDurationSeconds = recipe.durationSeconds,
	}
end

local function quote(view: Types.CraftingRecipeView): Types.StartCraftingRequest
	return {
		requestId = "0:quoted",
		expectedRevision = 0,
		stationInstanceId = "craft_station",
		recipeId = view.recipeId,
		expectedGoldCost = view.goldCost,
		expectedMaterialId = view.materialId,
		expectedMaterialQuantity = view.materialQuantity,
		expectedDefinitionId = view.resultDefinitionId,
		expectedFinishId = view.resultFinishId,
		expectedQuantity = view.quantity,
		expectedDurationSeconds = view.durationSeconds,
	}
end

local function read(
	jobs: CraftingJobs.CraftingJobs,
	data: Types.PlayerDoc,
	now: number
): Types.CraftingStationView
	local view, code = jobs.ReadStation(data, now, "craft_station")
	assert(view, `Expected station view, got {tostring(code)}`)
	return view
end

local function noPrivateFields(value: unknown)
	if type(value) ~= "table" then
		return
	end
	local forbidden: { [string]: boolean } = {
		receipt = true,
		paid = true,
		reservations = true,
		instanceIds = true,
		transactions = true,
		receipts = true,
		signature = true,
		profile = true,
		equipment = true,
		base = true,
		currency = true,
		inventoryUpgrades = true,
		productionClock = true,
		isStarterGrant = true,
	}
	for key, child in value :: { [string]: unknown } do
		expect(forbidden[key]).toBeNil()
		noPrivateFields(child)
	end
end

describe("Crafting station view", function()
	it(
		"quotes all twelve sorted recipes with the exact start envelope and no read-side work",
		function()
			local recipes = copy(Recipes)
			for _, recipe in recipes do
				local raw = recipe :: any
				raw.secret = "private-config-value"
			end
			local f = fixture(recipes)
			local rawData = f.data :: any
			rawData.secret = "private-profile-value"
			local before = copy(f.data)
			local result = f.commands.GetStation(f.player, { stationInstanceId = "craft_station" })
			expect(result.ok).toBe(true)
			expect(result.revision).toBe(0)
			local view = assert(result.view, "Expected command view")
			expect(result).toEqual({ ok = true, revision = 0, view = view })
			expect(view).toEqual({
				sampledAt = 20,
				stationInstanceId = "craft_station",
				craftingStationId = "basic_crafting_station",
				busy = false,
				recipes = view.recipes,
			})
			expect(view.sampledAt).toBe(20)
			expect(view.stationInstanceId).toBe("craft_station")
			expect(view.craftingStationId).toBe("basic_crafting_station")
			expect(view.busy).toBe(false)
			expect(view.blockingCode).toBeNil()
			expect(view.activeJob).toBeNil()
			expect(#view.recipes).toBe(12)
			for index, entry in view.recipes do
				local expected = startRequest(entry.recipeId)
				expected.requestId = "0:quoted"
				expect(quote(entry)).toEqual(expected)
				expect(entry).toEqual({
					recipeId = expected.recipeId,
					goldCost = expected.expectedGoldCost,
					materialId = expected.expectedMaterialId,
					materialQuantity = expected.expectedMaterialQuantity,
					resultDefinitionId = expected.expectedDefinitionId,
					resultFinishId = expected.expectedFinishId,
					quantity = expected.expectedQuantity,
					durationSeconds = expected.expectedDurationSeconds,
					canStart = true,
				})
				expect(entry.canStart).toBe(true)
				expect(entry.startCode).toBeNil()
				if index > 1 then
					expect(view.recipes[index - 1].recipeId < entry.recipeId).toBe(true)
				end
				local other = fixture()
				expect(other.jobs.StartToDraft(other.data, view.sampledAt, quote(entry)).ok).toBe(
					true
				)
			end
			noPrivateFields(result)
			expect(f.data).toEqual(before)
			expect(f.state).toEqual({
				now = 20,
				loaded = true,
				reads = 1,
				clocks = 1,
				ids = 0,
				transactions = 0,
				loads = 0,
				saves = 0,
			})
		end
	)

	it(
		"reports the paid promise and exact cancel boundary without completing or allocating",
		function()
			local f = fixture()
			expect(f.jobs.StartToDraft(f.data, 10, startRequest("elemental_sword_fire")).ok).toBe(
				true
			)
			local saved = assert(f.data.craftingJobs, "Expected active job")
			local jobId, job = next(saved)
			assert(jobId and job, "Expected one job")
			local rawJob = job :: any
			rawJob.secret, rawJob.receipt.secret, rawJob.receipt.result.secret =
				"private-job", "private-receipt", "private-result"
			local before = copy(f.data)
			for _, now in { 20, 69.5, 70, 100_000 } do
				f.state.now = now
				local result =
					f.commands.GetStation(f.player, { stationInstanceId = "craft_station" })
				local view = assert(result.view, "Expected active station")
				local active = assert(view.activeJob, "Expected canonical promise")
				expect(view).toEqual({
					sampledAt = now,
					stationInstanceId = "craft_station",
					craftingStationId = "basic_crafting_station",
					busy = true,
					blockingCode = "StationBusy",
					recipes = view.recipes,
					activeJob = active,
				})
				local due = now >= 70
				expect(view.busy).toBe(true)
				expect(view.blockingCode).toBe("StationBusy")
				expect(active).toEqual({
					jobId = jobId,
					recipeId = "elemental_sword_fire",
					stationInstanceId = "craft_station",
					status = "Active",
					startedAt = 10,
					completesAt = 70,
					remainingSeconds = math.max(0, 70 - now),
					completionPending = due,
					resultDefinitionId = "elemental_sword",
					resultFinishId = "fire",
					quantity = 1,
					canCancel = not due,
					cancelRefundGold = if due then 0 else 50,
					cancelRefundMaterials = if due then {} else { fire_material = 5 },
				})
				for _, entry in view.recipes do
					expect(entry.canStart).toBe(false)
					expect(entry.startCode).toBe("StationBusy")
				end
				noPrivateFields(result)
				expect(f.data).toEqual(before)
			end
			expect(job.status).toBe("Active")
			expect(f.state.ids).toBe(2)
			expect(f.state.clocks).toBe(4)
			expect(f.state.transactions + f.state.loads + f.state.saves).toBe(0)
		end
	)

	it(
		"keeps nil and resolved histories idle, while opaque legacy jobs stay busy without invented promises",
		function()
			local f = fixture()
			f.data.craftingJobs = nil
			expect(read(f.jobs, f.data, 20).busy).toBe(false)
			expect(f.data.craftingJobs).toBeNil()
			expect(f.jobs.StartToDraft(f.data, 10, startRequest("elemental_sword_fire")).ok).toBe(
				true
			)
			local saved = assert(f.data.craftingJobs, "Expected canonical job")
			local id = assert(next(saved), "Expected job identity")
			expect(f.jobs.CancelToDraft(f.data, 20, id).ok).toBe(true)
			local before = copy(f.data)
			local idle = read(f.jobs, f.data, 20)
			expect(idle.busy).toBe(false)
			expect(idle.activeJob).toBeNil()
			expect(f.data).toEqual(before)
			f.data.craftingJobs = {
				legacy_a = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
				},
				legacy_b = {
					status = "Active",
					reservations = { equipment = 1, materials = { water_material = 5 } },
				},
			}
			before = copy(f.data)
			local legacy = read(f.jobs, f.data, 100_000)
			expect(legacy.busy).toBe(true)
			expect(legacy.blockingCode).toBe("UnsupportedLegacyJob")
			expect(legacy.activeJob).toBeNil()
			for _, entry in legacy.recipes do
				expect(entry.canStart).toBe(false)
			end
			noPrivateFields(legacy)
			expect(f.data).toEqual(before)
		end
	)

	it(
		"uses the shared eligibility rules for affordability, existing capacity and deadline safety",
		function()
			local cases: { { code: string, change: (Types.PlayerDoc) -> (), now: number? } } = {
				{
					code = "InsufficientGold",
					change = function(data)
						data.currency.gold = 49
					end,
				},
				{
					code = "InsufficientMaterials",
					change = function(data)
						data.materials.fire_material.total = 4
					end,
				},
				{
					code = "InventoryFull",
					change = function(data)
						for index = 1, 10 do
							data.equipment[`retained_{index}`] =
								{ definitionId = "retained_legacy_item" }
						end
					end,
				},
				{
					code = "MaterialCapacityTooSmall",
					change = function(data)
						data.materials.fire_material.total = 8_000
					end,
				},
				{ code = "ArithmeticOverflow", now = 2 ^ 53 - 20, change = function(_data) end },
			}
			for _, case in cases do
				local f = fixture()
				case.change(f.data)
				local now = case.now or 20
				local before = copy(f.data)
				local view = read(f.jobs, f.data, now)
				local found = false
				for _, entry in view.recipes do
					if entry.recipeId == "elemental_sword_fire" then
						found = true
						expect(entry.canStart).toBe(false)
						expect(entry.startCode).toBe(case.code)
						local result = f.jobs.StartToDraft(copy(f.data), now, quote(entry))
						expect(result).toEqual({ ok = false, code = case.code })
					end
				end
				expect(found).toBe(true)
				expect(f.state.ids).toBe(0)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"keeps recorded promises independent of edited or removed recipes and returns detached projections",
		function()
			local recipes = copy(Recipes)
			local f = fixture(recipes)
			expect(f.jobs.StartToDraft(f.data, 10, startRequest("elemental_sword_fire")).ok).toBe(
				true
			)
			local edited = recipes.elemental_sword_fire
			edited.goldCost, edited.durationSeconds = 75, 120
			edited.materials.fire_material = 7
			local before, configured = copy(f.data), copy(recipes)
			local view = read(f.jobs, f.data, 20)
			local originalView = copy(view)
			local active = assert(view.activeJob, "Expected recorded promise")
			expect(active.cancelRefundGold).toBe(50)
			expect(active.cancelRefundMaterials).toEqual({ fire_material = 5 })
			expect(active.completesAt).toBe(70)
			for _, entry in view.recipes do
				if entry.recipeId == "elemental_sword_fire" then
					expect(entry.goldCost).toBe(75)
					expect(entry.materialQuantity).toBe(7)
					expect(entry.durationSeconds).toBe(120)
				end
			end
			-- Mutable detached copies or frozen projections are both safe; neither may alias a save/config.
			pcall(function()
				active.cancelRefundMaterials.fire_material = 999
			end)
			pcall(function()
				view.recipes[1].goldCost = 999
			end)
			pcall(function()
				view.recipes[1] = view.recipes[2]
			end)
			expect(f.data).toEqual(before)
			expect(recipes).toEqual(configured)
			expect(read(f.jobs, f.data, 20)).toEqual(originalView)
			recipes.elemental_sword_fire = nil
			local removed = read(f.jobs, f.data, 20)
			expect(#removed.recipes).toBe(11)
			expect(removed.activeJob).toEqual(originalView.activeJob)
			noPrivateFields(removed)
			expect(f.state.ids).toBe(2)
			expect(f.data).toEqual(before)
			local saved = assert(f.data.craftingJobs, "Expected retained job")
			local _, job = next(saved)
			assert(job, "Expected retained job")
			local receipt = assert(job.receipt, "Expected retained receipt")
			receipt.result.definitionId = "retired_definition"
			receipt.result.finishId = "retired_finish"
			local retained = read(f.jobs, f.data, 20)
			local promise = assert(
				retained.activeJob,
				"Expected promise independent of current result metadata"
			)
			expect(promise.resultDefinitionId).toBe("retired_definition")
			expect(promise.resultFinishId).toBe("retired_finish")
			expect(promise.cancelRefundGold).toBe(50)
		end
	)

	it(
		"preserves a fractional-time promise and its reservations even alongside opaque or overfull state",
		function()
			local f = fixture()
			expect(f.jobs.StartToDraft(f.data, 10.75, startRequest("elemental_sword_fire")).ok).toBe(
				true
			)
			local justStarted = read(f.jobs, f.data, 10.75)
			local active = assert(justStarted.activeJob, "Expected fractional promise")
			expect(active.startedAt).toBe(10.75)
			expect(active.completesAt).toBe(70.75)
			expect(active.remainingSeconds).toBe(60)
			for index = 1, 10 do
				f.data.equipment[`retained_{index}`] = { definitionId = "retained_legacy_item" }
			end
			local saved = assert(f.data.craftingJobs, "Expected canonical job")
			saved.legacy = {
				status = "Active",
				reservations = { equipment = 1, materials = { water_material = 5 } },
			}
			local before = copy(f.data)
			local mixed = read(f.jobs, f.data, 70.75)
			expect(mixed.busy).toBe(true)
			expect(mixed.blockingCode).toBe("UnsupportedLegacyJob")
			local promise = assert(mixed.activeJob, "Expected canonical promise beside legacy data")
			expect(promise.jobId).toBe(active.jobId)
			expect(promise.completionPending).toBe(true)
			expect(promise.remainingSeconds).toBe(0)
			expect(promise.canCancel).toBe(false)
			for _, entry in mixed.recipes do
				expect(entry.canStart).toBe(false)
				expect(entry.startCode).toBe("UnsupportedLegacyJob")
			end
			expect(f.data).toEqual(before)
			expect(f.state.ids).toBe(2)
			local early, code = f.jobs.ReadStation(f.data, 10.5, "craft_station")
			expect(early).toBeNil()
			expect(code).toBe("InvalidTimestamp")
		end
	)

	it(
		"rejects malformed shared state, station identity, recipe metadata and invalid timestamps",
		function()
			-- Malformed saved values are confined to the validation boundary under test.
			local cases: { { code: string, change: (any) -> () } } = {
				{
					code = "UnsupportedVersion",
					change = function(data)
						data.version = 6
					end,
				},
				{
					code = "InvalidBaseState",
					change = function(data)
						data.base = false
					end,
				},
				{
					code = "InvalidBaseState",
					change = function(data)
						data.base.craftingStation.id = ""
					end,
				},
				{
					code = "InvalidCraftingState",
					change = function(data)
						data.craftingJobs = false
					end,
				},
				{
					code = "InvalidCraftingState",
					change = function(data)
						data.craftingJobs = { job = { status = "Unknown" } }
					end,
				},
				{
					code = "InvalidInventoryState",
					change = function(data)
						data.equipment = false
					end,
				},
				{
					code = "InvalidInventoryUpgrade",
					change = function(data)
						data.inventoryUpgrades.equipment = 3
					end,
				},
				{
					code = "InvalidCurrency",
					change = function(data)
						data.currency.gold = "bad"
					end,
				},
				{
					code = "InvalidReservations",
					change = function(data)
						data.craftingJobs = {
							legacy = {
								status = "Active",
								reservations = { equipment = -1, materials = {} },
							},
						}
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				case.change(f.data)
				local before = copy(f.data)
				local view, code = f.jobs.ReadStation(f.data, 20, "craft_station")
				expect(view).toBeNil()
				expect(code).toBe(case.code)
				expect(f.data).toEqual(before)
				expect(f.state.ids).toBe(0)
			end
			local f = fixture()
			local missing, missingCode = f.jobs.ReadStation(f.data, 20, "other_station")
			expect(missing).toBeNil()
			expect(missingCode).toBe("StationChanged")
			for _, now in { -1, math.huge, 0 / 0, 2 ^ 53 } do
				local view, code = f.jobs.ReadStation(f.data, now, "craft_station")
				expect(view).toBeNil()
				expect(code).toBe("InvalidTimestamp")
			end
			local recipes = copy(Recipes)
			recipes.elemental_sword_fire.materials = { water_material = 5 }
			local invalidRecipe = fixture(recipes)
			local view, code =
				invalidRecipe.jobs.ReadStation(invalidRecipe.data, 20, "craft_station")
			expect(view).toBeNil()
			expect(code).toBe("InvalidRecipe")
			local active = fixture()
			expect(
				active.jobs.StartToDraft(active.data, 10, startRequest("elemental_sword_fire")).ok
			).toBe(true)
			local saved = assert(active.data.craftingJobs, "Expected job")
			local _, job = next(saved)
			assert(job, "Expected job")
			local receipt = assert(job.receipt, "Expected receipt")
			receipt.stationId = "other_station"
			local wrongStation, stationCode =
				active.jobs.ReadStation(active.data, 20, "craft_station")
			expect(wrongStation).toBeNil()
			expect(stationCode).toBe("InvalidCraftingState")
		end
	)

	it(
		"validates closed station requests and revisions without loading, saving or transacting",
		function()
			local invalid: { any } = {
				false,
				"craft_station",
				{},
				{ stationInstanceId = "" },
				{ stationInstanceId = 123 },
				{ stationInstanceId = string.rep("x", 129) },
				{ stationInstanceId = "craft_station", targetUserId = 9001 },
				{ stationInstanceId = "craft_station", expectedRevision = 0 },
				setmetatable({ stationInstanceId = "craft_station" }, {}),
			}
			for _, input in invalid do
				local f = fixture()
				expect(f.commands.GetStation(f.player, input)).toEqual({
					ok = false,
					code = "InvalidRequest",
					revision = 0,
				})
				expect(f.state.clocks).toBe(0)
				expect(f.state.transactions + f.state.loads + f.state.saves + f.state.ids).toBe(0)
			end
			local f = fixture()
			f.state.loaded = false
			expect(f.commands.GetStation(f.player, { stationInstanceId = "craft_station" })).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(f.state.clocks).toBe(0)
			f.state.loaded = true
			f.data.transactions = nil
			expect(
				f.commands.GetStation(f.player, { stationInstanceId = "craft_station" }).revision
			).toBe(0)
			for _, revision in { -1, 0.5, math.huge, 2 ^ 53 } do
				f.data.transactions = { revision = revision, receipts = {} }
				expect(f.commands.GetStation(f.player, { stationInstanceId = "craft_station" })).toEqual({
					ok = false,
					code = "InvalidTransaction",
					revision = -1,
				})
			end
			f.data.transactions = { revision = 12, receipts = {} }
			f.state.now = -1
			expect(f.commands.GetStation(f.player, { stationInstanceId = "craft_station" })).toEqual({
				ok = false,
				code = "InvalidTimestamp",
				revision = 12,
			})
			for _, throws in { false, true } do
				local samples = 0
				local failedClock = CraftingCommands.new(f.source, f.jobs, function(): number
					samples += 1
					if throws then
						error("clock unavailable")
					end
					-- Malformed dependency output is confined to this runtime-validation fixture.
					return ("not-a-timestamp" :: unknown) :: number
				end)
				expect(failedClock.GetStation(f.player, { stationInstanceId = "craft_station" })).toEqual({
					ok = false,
					code = "InvalidTimestamp",
					revision = 12,
				})
				expect(samples).toBe(1)
			end
			expect(f.state.transactions + f.state.loads + f.state.saves + f.state.ids).toBe(0)
		end
	)
end)
