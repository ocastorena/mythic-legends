--!strict
-- ServerScriptService/Services/CraftingService/CraftingJobs
-- Pure transaction-draft transitions; receipts preserve agreed output, refunds, and deadlines.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local Crafting = require(ReplicatedStorage.Shared.Configurations.Crafting)
local Recipes = require(ReplicatedStorage.Shared.Configurations.EquipmentRecipes)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local BaseState = require(ServerScriptService.Shared.BaseState)
local InventoryCapacity = require(ServerScriptService.Shared.InventoryCapacity)
local GoldCreditUtil = require(ServerScriptService.Shared.GoldCreditUtil)

export type Options = {
	recipes: { [string]: Types.EquipmentRecipe }?,
	createId: ((string) -> string)?,
}
export type CraftingJobs = {
	SettleDueToDraft: (Types.PlayerDoc, number) -> Types.TransactionOutcome,
	StartToDraft: (Types.PlayerDoc, number, Types.StartCraftingRequest) -> Types.TransactionOutcome,
	CancelToDraft: (Types.PlayerDoc, number, string) -> Types.TransactionOutcome,
}
type JobMap = { [string]: Types.CraftingJob }
type Record = { [string]: unknown }

local CraftingJobs = {}
local MAX_SAFE_INTEGER = 9007199254740991
local CATEGORIES = { "materials", "mythlings", "equipment" }

local function plain(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

local function isId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end

local function number(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 53
end

local function whole(value: unknown): boolean
	return number(value) and (value :: number) % 1 == 0
end

local function positiveWhole(value: unknown): boolean
	return whole(value) and (value :: number) > 0
end

local function reject(code: string): Types.TransactionOutcome
	return { ok = false, code = code }
end

local function validQuantities(value: unknown, allowEmpty: boolean): boolean
	if not plain(value) then
		return false
	end
	local count = 0
	for id, quantity in value :: Record do
		if not isId(id) or not positiveWhole(quantity) then
			return false
		end
		count += 1
	end
	return allowEmpty or count > 0
end

local function equalQuantities(left: { [string]: number }, right: { [string]: number }): boolean
	for id, quantity in left do
		if right[id] ~= quantity then
			return false
		end
	end
	for id, quantity in right do
		if left[id] ~= quantity then
			return false
		end
	end
	return true
end

local function validReceipt(job: Types.CraftingJob): boolean
	local rawReceipt: unknown = job.receipt
	if not plain(rawReceipt) then
		return false
	end
	local receipt = rawReceipt :: Record
	if
		receipt.version ~= Crafting.receiptVersion
		or not isId(receipt.recipeId)
		or not isId(receipt.stationId)
		or not isId(receipt.craftingStationId)
		or not number(receipt.startedAt)
		or not number(receipt.completesAt)
		or (receipt.completesAt :: number) <= (receipt.startedAt :: number)
		or not plain(receipt.result)
		or not plain(receipt.paid)
	then
		return false
	end
	local result = receipt.result :: Record
	local paid = receipt.paid :: Record
	if
		not isId(result.definitionId)
		or not isId(result.finishId)
		or not positiveWhole(result.quantity)
		or not plain(result.instanceIds)
		or not whole(paid.gold)
		or not validQuantities(paid.materials, false)
	then
		return false
	end
	local count = 0
	local identities: { [string]: boolean } = {}
	for index, instanceId in result.instanceIds :: { [unknown]: unknown } do
		if
			not positiveWhole(index)
			or (index :: number) > (result.quantity :: number)
			or not isId(instanceId)
			or identities[instanceId :: string]
		then
			return false
		end
		identities[instanceId :: string] = true
		count += 1
	end
	if count ~= result.quantity then
		return false
	end
	local reservations = job.reservations
	if not plain(reservations) or not validQuantities(reservations.materials, true) then
		return false
	end
	if job.status == "Active" then
		return receipt.resolvedAt == nil
			and reservations.equipment == result.quantity
			and equalQuantities(reservations.materials, paid.materials :: { [string]: number })
	end
	if
		not number(receipt.resolvedAt)
		or (receipt.resolvedAt :: number) < (receipt.startedAt :: number)
		or reservations.equipment ~= 0
		or next(reservations.materials) ~= nil
	then
		return false
	end
	return if job.status == "Completed"
		then (receipt.resolvedAt :: number) >= (receipt.completesAt :: number)
		else (receipt.resolvedAt :: number) < (receipt.completesAt :: number)
end

local function validateJobs(draft: Types.PlayerDoc, now: number): (JobMap?, string?)
	if draft.version ~= PlayerData.schemaVersion then
		return nil, "UnsupportedVersion"
	end
	if not number(now) then
		return nil, "InvalidTimestamp"
	end
	if Crafting.receiptVersion ~= 1 or not positiveWhole(Crafting.maxResolvedJobs) then
		return nil, "InvalidCraftingState"
	end
	local jobs = draft.craftingJobs
	if jobs == nil then
		return {}, nil
	end
	if not plain(jobs) then
		return nil, "InvalidCraftingState"
	end
	local active = 0
	local promisedIds: { [string]: boolean } = {}
	for id, job in jobs do
		if
			not isId(id)
			or not plain(job)
			or (job.status ~= "Active" and job.status ~= "Completed" and job.status ~= "Cancelled")
		then
			return nil, "InvalidCraftingState"
		end
		if job.receipt ~= nil then
			if not validReceipt(job) then
				return nil, "InvalidCraftingState"
			end
			if job.status == "Active" then
				active += 1
			end
			for _, instanceId in (job.receipt :: Types.CraftingReceipt).result.instanceIds do
				if promisedIds[instanceId] or jobs[instanceId] ~= nil then
					return nil, "InvalidCraftingState"
				end
				promisedIds[instanceId] = true
			end
		end
	end
	if active > 1 then
		return nil, "InvalidCraftingState"
	end
	return jobs, nil
end

local function validateInventory(draft: Types.PlayerDoc): string?
	local materialError = InventoryCapacity.ValidateMaterialState(draft)
	if materialError then
		return materialError
	end
	local upgrades = draft.inventoryUpgrades
	if upgrades ~= nil then
		if not plain(upgrades) then
			return "InvalidInventoryUpgrade"
		end
		for _, category in CATEGORIES do
			local level = upgrades[category]
			if
				level ~= nil
				and (not whole(level) or level >= #Inventory.capacityByCategory[category])
			then
				return "InvalidInventoryUpgrade"
			end
		end
	end
	if not plain(draft.equipment) then
		return "InvalidInventoryState"
	end
	for id, entry in draft.equipment do
		if
			not isId(id)
			or not plain(entry)
			or not isId(entry.definitionId)
			or (entry.finishId ~= nil and not isId(entry.finishId))
		then
			return "InvalidInventoryState"
		end
	end
	return nil
end

local function pruneResolved(jobs: JobMap, keepId: string?)
	local resolved: { { id: string, time: number } } = {}
	for id, job in jobs do
		local receipt = job.receipt
		if receipt and job.status ~= "Active" then
			table.insert(resolved, { id = id, time = receipt.resolvedAt :: number })
		end
	end
	table.sort(
		resolved,
		function(left: { id: string, time: number }, right: { id: string, time: number })
			return if left.time == right.time then left.id < right.id else left.time < right.time
		end
	)
	local remove = #resolved - Crafting.maxResolvedJobs
	for _, entry in resolved do
		if remove <= 0 then
			break
		end
		if entry.id ~= keepId then
			jobs[entry.id] = nil
			remove -= 1
		end
	end
end

local function releaseReservations(
	job: Types.CraftingJob,
	now: number,
	status: "Completed" | "Cancelled"
)
	job.status = status
	job.reservations.equipment = 0
	table.clear(job.reservations.materials)
	local receipt = job.receipt :: Types.CraftingReceipt
	receipt.resolvedAt = now
end

local function complete(draft: Types.PlayerDoc, job: Types.CraftingJob, now: number): string?
	local receipt = job.receipt :: Types.CraftingReceipt
	for _, instanceId in receipt.result.instanceIds do
		if draft.equipment[instanceId] ~= nil then
			return "InstanceIdConflict"
		end
	end
	-- Already-paid promises survive recipe edits and capacity reductions. Grant only recorded IDs;
	-- current metadata is not a substitute for the agreed result and no loadout is changed.
	for _, instanceId in receipt.result.instanceIds do
		draft.equipment[instanceId] = {
			definitionId = receipt.result.definitionId,
			finishId = receipt.result.finishId,
		}
	end
	releaseReservations(job, now, "Completed")
	return nil
end

local function recipeMaterial(recipe: Types.EquipmentRecipe?): (string?, string?)
	if
		not recipe
		or not plain(recipe)
		or not isId(recipe.craftingStationId)
		or not positiveWhole(recipe.goldCost)
		or not positiveWhole(recipe.quantity)
		or not positiveWhole(recipe.durationSeconds)
		or not validQuantities(recipe.materials, false)
	then
		return nil, "InvalidRecipe"
	end
	local result = EquipmentCatalog.Resolve(recipe.resultDefinitionId, recipe.resultFinishId)
	if not result or not result.element or not result.finishId or result.profile.stage ~= 1 then
		return nil, "InvalidRecipe"
	end
	local materialId: string? = nil
	for id in recipe.materials do
		local definition = Materials[id]
		if
			materialId ~= nil
			or not definition
			or definition.launchEnabled ~= true
			or definition.category ~= "material"
			or definition.element ~= result.element
			or definition.stackLimit ~= Inventory.materialStackLimit
		then
			return nil, "InvalidRecipe"
		end
		materialId = id
	end
	return materialId, nil
end

function CraftingJobs.new(options: Options?): CraftingJobs
	local recipes = if options and options.recipes then options.recipes else Recipes
	local createId = if options and options.createId
		then options.createId
		else function(prefix: string): string
			return `{prefix}_{HttpService:GenerateGUID(false)}`
		end
	local api = {}

	function api.SettleDueToDraft(draft: Types.PlayerDoc, now: number): Types.TransactionOutcome
		local jobs, problem = validateJobs(draft, now)
		if not jobs then
			return reject(problem or "InvalidCraftingState")
		end
		local completedId: string? = nil
		for id, job in jobs do
			local receipt = job.receipt
			if receipt and job.status == "Active" and now >= receipt.completesAt then
				local inventoryError = validateInventory(draft)
				if inventoryError then
					return reject(inventoryError)
				end
				local completionError = complete(draft, job, now)
				if completionError then
					return reject(completionError)
				end
				completedId = id
			end
		end
		if completedId then
			-- Preserve the just-resolved job so a cancellation at this boundary can report that
			-- completion won, including when retained resolved records share this timestamp.
			pruneResolved(jobs, completedId)
		end
		return { ok = true }
	end

	function api.StartToDraft(
		draft: Types.PlayerDoc,
		now: number,
		request: Types.StartCraftingRequest
	): Types.TransactionOutcome
		local settled = api.SettleDueToDraft(draft, now)
		if not settled.ok then
			return settled
		end
		local jobs: JobMap = draft.craftingJobs or {}
		for _, job in jobs do
			if job.status == "Active" then
				return reject("StationBusy")
			end
		end
		if not plain(draft.base) or not plain(draft.base.craftingStation) then
			return reject("InvalidBaseState")
		end
		local base = BaseState.GetStatus(draft.base)
		if not base then
			return reject("InvalidBaseState")
		end
		local station = base.craftingStation
		if station.id ~= request.stationInstanceId then
			return reject("StationChanged")
		end
		local recipe = recipes[request.recipeId]
		local materialId, recipeError = recipeMaterial(recipe)
		if
			not materialId
			or not recipe
			or recipe.craftingStationId ~= station.craftingStationId
		then
			return reject(recipeError or "InvalidRecipe")
		end
		if
			recipe.goldCost ~= request.expectedGoldCost
			or materialId ~= request.expectedMaterialId
			or recipe.materials[materialId] ~= request.expectedMaterialQuantity
			or recipe.resultDefinitionId ~= request.expectedDefinitionId
			or recipe.resultFinishId ~= request.expectedFinishId
			or recipe.quantity ~= request.expectedQuantity
			or recipe.durationSeconds ~= request.expectedDurationSeconds
		then
			return reject("RecipeChanged")
		end
		local inventoryError = validateInventory(draft)
		if inventoryError then
			return reject(inventoryError)
		end
		if not plain(draft.currency) or not whole(draft.currency.gold) then
			return reject("InvalidCurrency")
		end
		local refundGold, refundError = GoldCreditUtil.GetRefundReserve(draft)
		if refundGold == nil then
			return reject(refundError or "InvalidCraftingState")
		end
		if refundGold > MAX_SAFE_INTEGER - draft.currency.gold then
			return reject("ArithmeticOverflow")
		end
		local materialCapacity = InventoryCapacity.GetUsage(draft, "materials")
		if materialCapacity.used > materialCapacity.limit then
			return reject("MaterialCapacityTooSmall")
		end
		local equipmentCapacity = InventoryCapacity.GetUsage(draft, "equipment")
		if recipe.quantity > equipmentCapacity.limit - equipmentCapacity.used then
			return reject("InventoryFull")
		end
		if draft.currency.gold < recipe.goldCost then
			return reject("InsufficientGold")
		end
		for id, quantity in recipe.materials do
			local owned = draft.materials[id]
			if not owned or owned.total < quantity then
				return reject("InsufficientMaterials")
			end
		end
		local completesAt = now + recipe.durationSeconds
		if
			recipe.durationSeconds > MAX_SAFE_INTEGER - now
			or not number(completesAt)
			or completesAt <= now
		then
			return reject("ArithmeticOverflow")
		end
		-- Allocate only after eligibility/payment/capacity checks. The owning transaction catches
		-- a throwing/yielding generator and discards the entire detached transition.
		local usedIds: { [string]: boolean } = {}
		for id in draft.equipment do
			usedIds[id] = true
		end
		for id, job in jobs do
			usedIds[id] = true
			if job.receipt then
				for _, instanceId in job.receipt.result.instanceIds do
					usedIds[instanceId] = true
				end
			end
		end
		local jobId = createId("craft")
		if not isId(jobId) or usedIds[jobId] then
			return reject("InstanceIdConflict")
		end
		usedIds[jobId] = true
		local instanceIds: { string } = {}
		for _ = 1, recipe.quantity do
			local instanceId = createId("equipment")
			if not isId(instanceId) or usedIds[instanceId] then
				return reject("InstanceIdConflict")
			end
			usedIds[instanceId] = true
			table.insert(instanceIds, instanceId)
		end
		local receipt: Types.CraftingReceipt = {
			version = Crafting.receiptVersion,
			recipeId = request.recipeId,
			stationId = station.id,
			craftingStationId = station.craftingStationId,
			startedAt = now,
			completesAt = completesAt,
			result = {
				definitionId = recipe.resultDefinitionId,
				finishId = recipe.resultFinishId,
				quantity = recipe.quantity,
				instanceIds = instanceIds,
			},
			paid = { gold = recipe.goldCost, materials = table.clone(recipe.materials) },
		}
		for id, quantity in receipt.paid.materials do
			local owned = draft.materials[id]
			owned.total -= quantity
			if owned.total == 0 then
				draft.materials[id] = nil
			end
		end
		draft.currency.gold -= receipt.paid.gold
		jobs[jobId] = {
			status = "Active",
			reservations = {
				equipment = recipe.quantity,
				materials = table.clone(receipt.paid.materials),
			},
			receipt = receipt,
		}
		draft.craftingJobs = jobs
		pruneResolved(jobs, nil)
		return {
			ok = true,
			values = {
				jobId = jobId,
				status = "Active",
				completesAt = completesAt,
				resultDefinitionId = receipt.result.definitionId,
				resultFinishId = receipt.result.finishId,
				quantity = receipt.result.quantity,
				stationInstanceId = station.id,
				goldSpent = receipt.paid.gold,
			},
		}
	end

	function api.CancelToDraft(
		draft: Types.PlayerDoc,
		now: number,
		jobId: string
	): Types.TransactionOutcome
		local settled = api.SettleDueToDraft(draft, now)
		if not settled.ok then
			return settled
		end
		local jobs = draft.craftingJobs
		local job = if jobs then jobs[jobId] else nil
		if not job then
			return reject("JobNotFound")
		end
		local receipt = job.receipt
		if not receipt then
			return reject("UnsupportedLegacyJob")
		end
		if job.status ~= "Active" then
			return { ok = true, values = { jobId = jobId, status = job.status, goldRefunded = 0 } }
		end
		if now < receipt.startedAt then
			return reject("InvalidTimestamp")
		end
		local inventoryError = validateInventory(draft)
		if inventoryError then
			return reject(inventoryError)
		end
		for id, quantity in receipt.paid.materials do
			local owned = draft.materials[id]
			local total = if owned then owned.total else 0
			if quantity > MAX_SAFE_INTEGER - total then
				return reject("ArithmeticOverflow")
			end
		end
		-- Retire this claim before crediting it. Other active paid claims remain protected by the
		-- shared Gold-credit guard; a failure is discarded by the caller's transaction.
		releaseReservations(job, now, "Cancelled")
		local goldError = GoldCreditUtil.CreditToDraft(draft, receipt.paid.gold)
		if goldError then
			return reject(goldError)
		end
		for id, quantity in receipt.paid.materials do
			local owned = draft.materials[id]
			if owned then
				owned.total += quantity
			else
				draft.materials[id] = { total = quantity }
			end
		end
		pruneResolved(jobs :: JobMap, jobId)
		return {
			ok = true,
			values = { jobId = jobId, status = "Cancelled", goldRefunded = receipt.paid.gold },
		}
	end

	return api
end

return table.freeze(CraftingJobs)
