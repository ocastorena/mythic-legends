--!strict
-- ServerStorage/Tests/__tests__/ShrineActionAccess.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ShrineView = require(ServerScriptService.Services.BaseService.ShrineView)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
local ShrineUpgradePurchase =
	require(ServerScriptService.Services.BaseService.ShrineUpgradePurchase)
local ShrineRemoval = require(ServerScriptService.Services.BaseService.ShrineRemoval)
local ShrineCollector = require(ServerScriptService.Services.ProductionService.ShrineCollector)
local CraftingJobs = require(ServerScriptService.Services.CraftingService.CraftingJobs)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it
type Action = "Assign" | "Remove" | "Upgrade" | "Dismantle" | "Collect"
local ACTIONS: { Action } = { "Assign", "Remove", "Upgrade", "Dismantle", "Collect" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function request(action: Action, revision: number, token: string): { [string]: unknown }
	local result: { [string]: unknown } = {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		shrineInstanceId = "selected",
	}
	if action == "Assign" then
		result.slotId, result.workerId = 1, "worker"
	elseif action == "Remove" then
		result.slotId, result.expectedWorkerId = 1, "worker"
	elseif action == "Upgrade" then
		result.expectedLevel = 1
		result.expectedMaterialId = "fire_material"
		result.expectedGoldCost, result.expectedMaterialQuantity = 1_000, 400
	elseif action == "Dismantle" then
		result.expectedLevel = 1
	else
		result.expectedMaterialId = "fire_material"
	end
	return result
end

local function fixture(action: Action, useAccess: boolean?)
	local data = copy(PlayerDataTemplate)
	assert(ProfileSchema.Prepare(data, function()
		return "permanent_station"
	end, 0))
	data.currency.gold = 10_000
	data.materials = { fire_material = { total = 800 } }
	data.mythlings = {
		worker = {
			typeId = "mythling_0001",
			variantId = "retained_variant",
			claimedAt = 0,
			level = 1,
			xp = 17,
			pendingXp = 0.3,
		},
	}
	data.base.shrines = {
		selected = {
			id = "selected",
			shrineId = "fire_shrine",
			buildSlotId = 1,
			level = 1,
			stored = if action == "Dismantle" then 0 else 5,
			progress = 0.4,
			newWork = 0.2,
			workerIdsBySlot = if action == "Assign" or action == "Dismantle"
				then {}
				else { ["1"] = "worker" },
		},
		retained = {
			id = "retained",
			shrineId = "water_shrine",
			buildSlotId = 2,
			level = 1,
			stored = 6,
			progress = 0.3,
			newWork = 0.4,
			workerIdsBySlot = {},
		},
	}
	data.craftingJobs = {
		due_job = {
			status = "Active",
			reservations = { equipment = 1, materials = { fire_material = 5 } },
			receipt = {
				version = 1,
				recipeId = "elemental_sword_fire",
				stationId = "permanent_station",
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
	-- Identity token for injected private helpers, never an engine Player or positive live-access claim.
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local state = {
		now = 20,
		loaded = true,
		active = true,
		accessCode = nil :: string?,
		accessMode = "normal",
		clocks = 0,
		preparations = 0,
		ids = 0,
		accesses = {} :: {
			{
				data: Types.PlayerDoc,
				shrineId: string,
				outputPrepared: boolean,
				clocksSeen: number,
			}
		},
	}
	local jobs = CraftingJobs.new({
		createId = function(): string
			state.ids += 1
			error("Settling an existing promise must not allocate another identity")
		end,
	})
	local source: ShrineWorkers.DataSource = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			expect(caller).toBe(player)
			return if state.loaded and state.active then data else nil
		end,
		Transact = function(caller, envelope, mutation)
			expect(caller).toBe(player)
			return Transactions.Run(data, envelope, function(draft)
				-- The real preparation precedes feature access inside the same rollback boundary.
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
	local function access(caller: Player, draft: Types.PlayerDoc, shrineId: string): string?
		expect(caller).toBe(player)
		table.insert(state.accesses, {
			data = draft,
			shrineId = shrineId,
			outputPrepared = draft.equipment.promised_output ~= nil,
			clocksSeen = state.clocks,
		})
		if state.accessMode == "throw" then
			error("Injected Shrine access failure")
		elseif state.accessMode == "yield" then
			coroutine.yield()
		end
		return state.accessCode
	end
	local function clock(): number
		state.clocks += 1
		return state.now
	end
	local checkAccess = if useAccess == false then nil else access
	local workers = ShrineWorkers.new(source, clock, checkAccess)
	local upgrade = ShrineUpgradePurchase.new(source, clock, checkAccess)
	local removal = ShrineRemoval.new(source, clock, checkAccess)
	local collection = ShrineCollector.new(source, clock, checkAccess)
	-- One narrow untrusted-payload test boundary permits extra-field/invalid-value cases while
	-- each branch invokes its real, distinctly typed command instead of a union of functions.
	local function execute(selectedAction: Action, raw: any): Types.TransactionResult
		if selectedAction == "Assign" then
			return workers.Assign(player, raw)
		elseif selectedAction == "Remove" then
			return workers.Remove(player, raw)
		elseif selectedAction == "Upgrade" then
			return upgrade.Upgrade(player, raw)
		elseif selectedAction == "Dismantle" then
			return removal.Dismantle(player, raw)
		end
		return collection.Collect(player, raw)
	end
	return {
		data = data,
		player = player,
		state = state,
		execute = execute,
		view = ShrineView.new(source, checkAccess),
	}
end

describe("Shrine action access boundary", function()
	it(
		"admits reads after profile, revision and closed selection checks but before projection",
		function()
			local f = fixture("Assign")
			f.state.accessCode = "OutOfRange"
			f.state.loaded = false
			expect(f.view.Get(f.player, nil)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			f.state.loaded = true
			f.data.transactions = { revision = -1, receipts = {} }
			expect(f.view.Get(f.player, nil)).toEqual({
				ok = false,
				code = "InvalidTransaction",
				revision = -1,
			})
			f.data.transactions = { revision = 7, receipts = {} }
			expect(
				f.view.Get(f.player, { shrineInstanceId = "selected", targetUserId = 9001 }).code
			).toBe("InvalidRequest")
			expect(#f.state.accesses).toBe(0)
			local savedBase = f.data.base
			local raw = f.data :: any
			raw.base = nil
			local before = copy(f.data)
			expect(f.view.Get(f.player, { shrineInstanceId = "selected" })).toEqual({
				ok = false,
				code = "OutOfRange",
				revision = 7,
			})
			expect(#f.state.accesses).toBe(1)
			expect(f.state.accesses[1].data).toBe(f.data)
			expect(f.state.accesses[1].shrineId).toBe("selected")
			expect(f.state.accesses[1].outputPrepared).toBe(false)
			expect(f.state.clocks + f.state.preparations + f.state.ids).toBe(0)
			expect(f.data).toEqual(before)
			f.data.base = savedBase
			f.state.accessCode = nil
			local allowed = f.view.Get(f.player, { shrineInstanceId = "selected" })
			expect(allowed.ok).toBe(true)
			expect(allowed.revision).toBe(7)
			expect(f.state.clocks + f.state.preparations + f.state.ids).toBe(0)
			expect(f.data.equipment.promised_output).toBeNil()
		end
	)

	it(
		"runs every fresh action with its exact selection on the prepared draft before its clock",
		function()
			for _, action in ACTIONS do
				local f = fixture(action)
				local result = f.execute(action, request(action, 0, "allowed"))
				expect(result.ok).toBe(true)
				expect(result.revision).toBe(1)
				expect(#f.state.accesses).toBe(1)
				local accessed = f.state.accesses[1]
				expect(accessed.data == f.data).toBe(false)
				expect(accessed.shrineId).toBe("selected")
				expect(accessed.outputPrepared).toBe(true)
				expect(accessed.clocksSeen).toBe(0)
				expect(f.state.clocks).toBe(1)
				expect(f.state.preparations).toBe(1)
				expect(f.state.ids).toBe(0)
				expect(f.data.equipment.promised_output.definitionId).toBe("elemental_sword")
				local shrines = assert(f.data.base.shrines, "Expected retained Shrine ownership")
				if action == "Assign" then
					expect(shrines.selected.workerIdsBySlot).toEqual({ ["1"] = "worker" })
				elseif action == "Remove" then
					expect(shrines.selected.workerIdsBySlot).toEqual({})
				elseif action == "Upgrade" then
					expect(shrines.selected.level).toBe(2)
					expect(f.data.currency.gold).toBe(9_000)
					expect(f.data.materials.fire_material.total).toBe(400)
				elseif action == "Dismantle" then
					expect(shrines.selected).toBeNil()
				else
					expect(shrines.selected.stored).toBe(0)
					expect(f.data.materials.fire_material.total).toBe(805)
				end
				expect(shrines.retained.stored).toBe(6)
			end
		end
	)

	it(
		"replays all successful actions after access loss, reset and removed Shrine or Base",
		function()
			for _, action in ACTIONS do
				local f = fixture(action)
				local selected = request(action, 0, "committed")
				local committed = f.execute(action, selected)
				expect(committed.ok).toBe(true)
				for _, accessCode in { "OutOfRange", "CharacterUnavailable", "ShrineUnavailable" } do
					f.state.accessCode, f.state.now = accessCode, 100_000
					-- World/character failure is injected; no live spatial access is claimed by this test.
					local raw = f.data :: any
					raw.base = nil
					local before = copy(f.data)
					expect(f.execute(action, selected)).toEqual({
						ok = true,
						revision = committed.revision,
						values = committed.values,
						replayed = true,
					})
					expect(f.data).toEqual(before)
				end
				expect(#f.state.accesses).toBe(1)
				expect(f.state.clocks).toBe(1)
				expect(f.state.preparations).toBe(1)
				expect(f.state.ids).toBe(0)
			end
		end
	)

	it(
		"rolls back due preparation and each denied action and preserves the original rejection receipt",
		function()
			for _, action in ACTIONS do
				local f = fixture(action)
				f.state.accessCode = "OutOfRange"
				local before = gameplay(f.data)
				local selected = request(action, 0, "denied")
				expect(f.execute(action, selected)).toEqual({
					ok = false,
					code = "OutOfRange",
					revision = 1,
				})
				expect(f.state.accesses[1].outputPrepared).toBe(true)
				expect(f.state.accesses[1].shrineId).toBe("selected")
				expect(f.state.accesses[1].data == f.data).toBe(false)
				expect(f.state.accesses[1].clocksSeen).toBe(0)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.data.equipment.promised_output).toBeNil()
				f.state.accessCode = nil
				local rejected = { ok = false, code = "OutOfRange", revision = 1, replayed = true }
				expect(f.execute(action, selected)).toEqual(rejected)
				expect(gameplay(f.data)).toEqual(before)
				f.state.accessCode = "CharacterUnavailable"
				local raw = f.data :: any
				raw.base = nil
				local removed = copy(f.data)
				expect(f.execute(action, selected)).toEqual(rejected)
				expect(f.data).toEqual(removed)
				expect(#f.state.accesses).toBe(1)
				expect(f.state.preparations).toBe(1)
				expect(f.state.clocks + f.state.ids).toBe(0)
			end
		end
	)

	it(
		"skips guards, clocks and preparation for stale, conflicting and malformed envelopes",
		function()
			for _, action in ACTIONS do
				local f = fixture(action)
				local selected = request(action, 0, "committed")
				expect(f.execute(action, selected).ok).toBe(true)
				f.state.accessMode = "throw"
				local changed = table.clone(selected)
				changed.shrineInstanceId = "retained"
				expect(f.execute(action, changed).code).toBe("RequestConflict")
				expect(f.execute(action, request(action, 0, "stale")).code).toBe("StaleRevision")
				local forged = request(action, 1, "forged")
				forged.targetUserId = 9001
				expect(f.execute(action, forged).code).toBe("InvalidRequest")
				expect(f.execute(action, nil).code).toBe("InvalidRequest")
				expect(#f.state.accesses).toBe(1)
				expect(f.state.clocks).toBe(1)
				expect(f.state.preparations).toBe(1)
				expect(f.state.ids).toBe(0)
			end
		end
	)

	it(
		"contains throwing and yielding guards without committing due output or a decision receipt",
		function()
			for _, action in ACTIONS do
				for _, mode in { "throw", "yield" } do
					local f = fixture(action)
					f.state.accessMode = mode
					local before = copy(f.data)
					local result = f.execute(action, request(action, 0, "failed"))
					expect(result.code).toBe(
						if mode == "throw" then "MutationFailed" else "MutationYielded"
					)
					expect(f.state.accesses[1].outputPrepared).toBe(true)
					expect(f.state.accesses[1].clocksSeen).toBe(0)
					expect(f.state.clocks + f.state.ids).toBe(0)
					expect(f.data).toEqual(before)
				end
			end
		end
	)

	it(
		"retains optional headless construction and avoids guards for unavailable profiles",
		function()
			for _, action in ACTIONS do
				local headless = fixture(action, false)
				headless.state.accessCode = "OutOfRange"
				expect(headless.view.Get(headless.player, { shrineInstanceId = "selected" }).ok).toBe(
					true
				)
				expect(headless.execute(action, request(action, 0, "headless")).ok).toBe(true)
				expect(#headless.state.accesses).toBe(0)
				expect(headless.state.clocks).toBe(1)
				local missing = fixture(action)
				missing.state.loaded = false
				expect(missing.execute(action, request(action, 0, "missing"))).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
				expect(#missing.state.accesses).toBe(0)
				expect(missing.state.clocks + missing.state.preparations + missing.state.ids).toBe(
					0
				)
			end
		end
	)
end)
