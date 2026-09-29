--!strict
-- ServerStorage/Tests/__tests__/CraftingJobs.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Recipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function request(recipeId: string?): Types.StartCraftingRequest
	local id = recipeId or "elemental_sword_fire"
	local recipe = Recipes[id]
	local materialId, quantity = next(recipe.materials)
	assert(materialId and quantity, "[CraftingJobs.spec] Expected recipe input")
	return {
		requestId = "0:start",
		expectedRevision = 0,
		stationInstanceId = "craft_station",
		recipeId = id,
		expectedGoldCost = recipe.goldCost,
		expectedMaterialId = materialId,
		expectedMaterialQuantity = quantity,
		expectedDefinitionId = recipe.resultDefinitionId,
		expectedFinishId = recipe.resultFinishId,
		expectedQuantity = recipe.quantity,
		expectedDurationSeconds = recipe.durationSeconds,
	}
end

local function fixture(recipes: { [string]: Types.EquipmentRecipe }?)
	local data = copy(PlayerDataTemplate)
	local ready = ProfileSchema.Prepare(data, function()
		return "craft_station"
	end, 0)
	assert(ready, "[CraftingJobs.spec] Fixture preparation failed")
	data.currency.gold = 1_000
	for _, element in { "fire", "water", "earth", "air", "light", "dark" } do
		data.materials[`{element}_material`] = { total = 100 }
	end
	local ids: { string } = {}
	local jobs = CraftingJobs.new({
		recipes = recipes,
		createId = function(prefix: string): string
			local id = `{prefix}_{#ids + 1}`
			table.insert(ids, id)
			return id
		end,
	})
	return { data = data, jobs = jobs, ids = ids }
end

local function onlyJob(data: Types.PlayerDoc): (string, Types.CraftingJob)
	local saved = assert(data.craftingJobs, "[CraftingJobs.spec] Expected jobs")
	local id, job = next(saved)
	assert(id and job, "[CraftingJobs.spec] Expected one job")
	return id, job
end

describe("CraftingJobs", function()
	it(
		"starts every launch recipe with exact costs, promised IDs, and both reservations",
		function()
			for recipeId, recipe in Recipes do
				local f = fixture()
				local before = copy(f.data)
				local result = f.jobs.StartToDraft(f.data, 10, request(recipeId))
				expect(result.ok).toBe(true)
				local id, job = onlyJob(f.data)
				local receipt = assert(job.receipt, "[CraftingJobs.spec] Expected receipt")
				expect(result.values).toEqual({
					jobId = id,
					status = "Active",
					completesAt = 70,
					resultDefinitionId = recipe.resultDefinitionId,
					resultFinishId = recipe.resultFinishId,
					quantity = 1,
					stationInstanceId = "craft_station",
					goldSpent = 50,
				})
				expect(job.status).toBe("Active")
				expect(job.reservations).toEqual({ equipment = 1, materials = recipe.materials })
				expect(receipt.version).toBe(1)
				expect(receipt.recipeId).toBe(recipeId)
				expect(receipt.stationId).toBe("craft_station")
				expect(receipt.craftingStationId).toBe("basic_crafting_station")
				expect(receipt.startedAt).toBe(10)
				expect(receipt.completesAt).toBe(70)
				expect(receipt.paid).toEqual({ gold = 50, materials = recipe.materials })
				expect(receipt.result.definitionId).toBe(recipe.resultDefinitionId)
				expect(receipt.result.finishId).toBe(recipe.resultFinishId)
				expect(#receipt.result.instanceIds).toBe(1)
				expect(f.data.currency.gold).toBe(950)
				for materialId in recipe.materials do
					expect(f.data.materials[materialId].total).toBe(95)
				end
				expect(f.data.equipment).toEqual(before.equipment)
				expect(f.data.combatLoadout).toEqual(before.combatLoadout)
				expect(f.data.mythlings).toEqual(before.mythlings)
				expect(f.data.productionClock).toEqual(before.productionClock)
				expect(f.data.base).toEqual(before.base)
				expect(InventoryCapacity.GetUsage(f.data, "equipment")).toEqual({
					used = 3,
					limit = 12,
				})
				expect(InventoryCapacity.GetUsage(f.data, "materials").used).toBe(6)
			end
		end
	)

	it(
		"completes at the saved deadline or after offline elapsed time exactly once without auto-equip",
		function()
			for _, now in { 70, 100_000 } do
				local f = fixture()
				expect(f.jobs.StartToDraft(f.data, 10, request()).ok).toBe(true)
				local id, active = onlyJob(f.data)
				local receipt = assert(active.receipt, "[CraftingJobs.spec] Expected receipt")
				local outputId = receipt.result.instanceIds[1]
				local before = copy(f.data)
				expect(f.jobs.SettleDueToDraft(f.data, 69.999).ok).toBe(true)
				expect(f.data).toEqual(before)
				f.data = copy(f.data)
				expect(f.jobs.SettleDueToDraft(f.data, now).ok).toBe(true)
				local _, completed = onlyJob(f.data)
				expect(completed.status).toBe("Completed")
				expect(completed.reservations).toEqual({ equipment = 0, materials = {} })
				expect(f.data.equipment[outputId]).toEqual({
					definitionId = "elemental_sword",
					finishId = "fire",
				})
				expect(f.data.currency.gold).toBe(950)
				expect(f.data.materials.fire_material.total).toBe(95)
				expect(f.data.combatLoadout).toEqual(before.combatLoadout)
				local after = copy(f.data)
				expect(f.jobs.SettleDueToDraft(f.data, now + 1).ok).toBe(true)
				expect(f.jobs.CancelToDraft(f.data, now + 1, id).values).toEqual({
					jobId = id,
					status = "Completed",
					goldRefunded = 0,
				})
				expect(f.data).toEqual(after)
			end
		end
	)

	it(
		"refunds exactly paid costs only before the deadline and lets due completion win cancellation",
		function()
			for _, now in { 69.999, 70 } do
				local f = fixture()
				expect(f.jobs.StartToDraft(f.data, 10, request()).ok).toBe(true)
				local id, job = onlyJob(f.data)
				local receipt = assert(job.receipt, "[CraftingJobs.spec] Expected receipt")
				local outputId = receipt.result.instanceIds[1]
				local cancelled = now < 70
				expect(f.jobs.CancelToDraft(f.data, now, id).values).toEqual({
					jobId = id,
					status = if cancelled then "Cancelled" else "Completed",
					goldRefunded = if cancelled then 50 else 0,
				})
				expect(f.data.currency.gold).toBe(if cancelled then 1_000 else 950)
				expect(f.data.materials.fire_material.total).toBe(if cancelled then 100 else 95)
				expect(f.data.equipment[outputId] == nil).toBe(cancelled)
				expect(job.reservations).toEqual({ equipment = 0, materials = {} })
				local after = copy(f.data)
				expect(f.jobs.CancelToDraft(f.data, 100, id).ok).toBe(true)
				expect(f.jobs.SettleDueToDraft(f.data, 1_000).ok).toBe(true)
				expect(f.data).toEqual(after)
			end
		end
	)

	it("honors saved output, costs, and deadline after recipe removal or tuning changes", function()
		for _, cancel in { true, false } do
			local f = fixture()
			expect(f.jobs.StartToDraft(f.data, 10, request()).ok).toBe(true)
			local id, job = onlyJob(f.data)
			local receipt = assert(job.receipt, "[CraftingJobs.spec] Expected receipt")
			local beforeReceipt = copy(receipt)
			local changed = CraftingJobs.new({ recipes = {} })
			local result = if cancel
				then changed.CancelToDraft(f.data, 50, id)
				else changed.SettleDueToDraft(f.data, 70)
			expect(result.ok).toBe(true)
			expect(receipt.paid).toEqual(beforeReceipt.paid)
			expect(receipt.result).toEqual(beforeReceipt.result)
			expect(receipt.completesAt).toBe(70)
			expect(f.data.currency.gold).toBe(if cancel then 1_000 else 950)
		end
	end)

	it(
		"reserves and delivers each configured output copy with a distinct retained instance ID",
		function()
			local recipes = copy(Recipes)
			recipes.elemental_sword_fire.quantity = 2
			local f = fixture(recipes)
			local selected = request()
			selected.expectedQuantity = 2
			expect(f.jobs.StartToDraft(f.data, 0, selected).ok).toBe(true)
			local _, job = onlyJob(f.data)
			local receipt = assert(job.receipt, "[CraftingJobs.spec] Expected receipt")
			expect(job.reservations.equipment).toBe(2)
			expect(#receipt.result.instanceIds).toBe(2)
			expect(receipt.result.instanceIds[1] == receipt.result.instanceIds[2]).toBe(false)
			expect(f.jobs.SettleDueToDraft(f.data, 60).ok).toBe(true)
			for _, id in receipt.result.instanceIds do
				expect(f.data.equipment[id]).toEqual({
					definitionId = "elemental_sword",
					finishId = "fire",
				})
			end
		end
	)

	it(
		"counts equipped starters and rejects starting without output or existing Material room",
		function()
			for _, reason in { "equipment", "materials", "gold", "ingredients", "station", "quote" } do
				local f = fixture()
				local selected = request()
				local code = "InventoryFull"
				if reason == "equipment" then
					for index = 1, 10 do
						f.data.equipment[`old_{index}`] = { definitionId = "retained_gear" }
					end
				elseif reason == "materials" then
					f.data.materials.legacy = { total = 7_000 }
					code = "MaterialCapacityTooSmall"
				elseif reason == "gold" then
					f.data.currency.gold = 49
					code = "InsufficientGold"
				elseif reason == "ingredients" then
					f.data.materials.fire_material.total = 4
					code = "InsufficientMaterials"
				elseif reason == "station" then
					selected.stationInstanceId = "other_station"
					code = "StationChanged"
				else
					selected.expectedFinishId = "water"
					code = "RecipeChanged"
				end
				local before = copy(f.data)
				expect(f.jobs.StartToDraft(f.data, 0, selected).code).toBe(code)
				expect(f.data).toEqual(before)
			end
			local f = fixture()
			for index = 1, 9 do
				f.data.equipment[`old_{index}`] = { definitionId = "retained_gear" }
			end
			expect(f.jobs.StartToDraft(f.data, 0, request()).ok).toBe(true)
			expect(InventoryCapacity.GetUsage(f.data, "equipment")).toEqual({
				used = 12,
				limit = 12,
			})
		end
	)

	it(
		"preserves multiple opaque active legacy jobs without imposing the canonical job limit",
		function()
			local f = fixture()
			local saved = assert(f.data.craftingJobs, "[CraftingJobs.spec] Expected jobs")
			for _, id in { "legacy_first", "legacy_second" } do
				saved[id] = {
					status = "Active",
					reservations = { equipment = 1, materials = { fire_material = 5 } },
				}
			end
			local before = copy(f.data)
			expect(f.jobs.SettleDueToDraft(f.data, 1_000).ok).toBe(true)
			for _, id in { "legacy_first", "legacy_second" } do
				expect(f.jobs.CancelToDraft(f.data, 1_000, id).code).toBe("UnsupportedLegacyJob")
			end
			expect(f.jobs.StartToDraft(f.data, 1_000, request()).code).toBe("StationBusy")
			expect(f.data).toEqual(before)
		end
	)

	it(
		"settles a canonical promise alongside multiple active legacy jobs without resolving them",
		function()
			local f = fixture()
			expect(f.jobs.StartToDraft(f.data, 0, request()).ok).toBe(true)
			local id, job = onlyJob(f.data)
			local receipt = assert(job.receipt, "[CraftingJobs.spec] Expected receipt")
			local saved = assert(f.data.craftingJobs, "[CraftingJobs.spec] Expected jobs")
			for _, legacyId in { "legacy_first", "legacy_second" } do
				saved[legacyId] = {
					status = "Active",
					reservations = { equipment = 1, materials = { water_material = 5 } },
				}
			end
			local first, second = copy(saved.legacy_first), copy(saved.legacy_second)
			expect(f.jobs.SettleDueToDraft(f.data, 60).ok).toBe(true)
			expect(saved[id].status).toBe("Completed")
			expect(f.data.equipment[receipt.result.instanceIds[1]]).toEqual({
				definitionId = "elemental_sword",
				finishId = "fire",
			})
			expect(saved.legacy_first).toEqual(first)
			expect(saved.legacy_second).toEqual(second)
			expect(f.data.currency.gold).toBe(950)
			expect(f.data.materials.fire_material.total).toBe(95)
			expect(f.data.materials.water_material.total).toBe(100)
			expect(f.jobs.StartToDraft(f.data, 60, request()).code).toBe("StationBusy")
		end
	)

	it("rejects colliding generated IDs before charging or reserving anything", function()
		for _, id in { "starter_wooden_sword", "", string.rep("x", 129) } do
			local f = fixture()
			local jobs = CraftingJobs.new({
				createId = function(_prefix: string): string
					return id
				end,
			})
			local before = copy(f.data)
			expect(jobs.StartToDraft(f.data, 0, request()).code).toBe("InstanceIdConflict")
			expect(f.data).toEqual(before)
		end
	end)

	it(
		"rejects malformed canonical receipts instead of delivering partial output or refund",
		function()
			for _, reason in { "version", "deadline", "reservation", "quantity", "paid" } do
				local f = fixture()
				expect(f.jobs.StartToDraft(f.data, 0, request()).ok).toBe(true)
				local id, job = onlyJob(f.data)
				local raw = job :: any
				if reason == "version" then
					raw.receipt.version = 2
				elseif reason == "deadline" then
					raw.receipt.completesAt = -1
				elseif reason == "reservation" then
					raw.reservations.equipment = 0
				elseif reason == "quantity" then
					raw.receipt.result.quantity = 2
				else
					raw.receipt.paid.gold = -1
				end
				local before = copy(f.data)
				expect(f.jobs.SettleDueToDraft(f.data, 100).ok).toBe(false)
				expect(f.jobs.CancelToDraft(f.data, 100, id).ok).toBe(false)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"checks every promised output ID before granting any part of a due multi-copy job",
		function()
			local recipes = copy(Recipes)
			recipes.elemental_sword_fire.quantity = 2
			local f = fixture(recipes)
			local selected = request()
			selected.expectedQuantity = 2
			expect(f.jobs.StartToDraft(f.data, 0, selected).ok).toBe(true)
			local _, job = onlyJob(f.data)
			local receipt = assert(job.receipt, "[CraftingJobs.spec] Expected receipt")
			f.data.equipment[receipt.result.instanceIds[2]] = { definitionId = "retained_gear" }
			local before = copy(f.data)
			expect(f.jobs.SettleDueToDraft(f.data, 60).code).toBe("InstanceIdConflict")
			expect(f.data).toEqual(before)
		end
	)

	it("keeps refund addition exact at the maximum safe Gold balance", function()
		local f = fixture()
		expect(f.jobs.StartToDraft(f.data, 0, request()).ok).toBe(true)
		local id = onlyJob(f.data)
		f.data.currency.gold = 2 ^ 53 - 1 - 50
		expect(f.jobs.CancelToDraft(f.data, 1, id).ok).toBe(true)
		expect(f.data.currency.gold).toBe(2 ^ 53 - 1)
	end)

	it("bounds resolved canonical history while retaining unrelated legacy records", function()
		local f = fixture()
		local saved = assert(f.data.craftingJobs, "[CraftingJobs.spec] Expected jobs")
		saved.legacy = { status = "Completed", reservations = { equipment = 0, materials = {} } }
		local legacy = copy(saved.legacy)
		for index = 1, 35 do
			local result = f.jobs.StartToDraft(f.data, index, request())
			expect(result.ok).toBe(true)
			local values = assert(result.values, "[CraftingJobs.spec] Expected start result")
			expect(f.jobs.CancelToDraft(f.data, index, values.jobId :: string).ok).toBe(true)
		end
		local canonical = 0
		for _, job in saved do
			if job.receipt then
				canonical += 1
			end
		end
		expect(canonical).toBe(32)
		expect(saved.legacy).toEqual(legacy)
		expect(f.data.currency.gold).toBe(1_000)
		expect(f.data.materials.fire_material.total).toBe(100)
	end)
end)
