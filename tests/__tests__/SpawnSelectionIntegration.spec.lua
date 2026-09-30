--!strict
-- ServerStorage/Tests/__tests__/SpawnSelectionIntegration.spec
-- Headless composition only: this does not activate launch models or prove live Arena placement.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local MythlingSpawns = require(ReplicatedStorage.Shared.Configurations.MythlingSpawns)
local SpawnSelection = require(ServerScriptService.Services.MythlingSpawnService.SpawnSelection)
local SpawnPopulation = require(ServerScriptService.Services.MythlingSpawnService.SpawnPopulation)
local CaptureGrant = require(ServerScriptService.Services.InventoryService.CaptureGrant)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local launchChoices = {
	{
		rarity = "Common",
		roll = 0.1,
		forms = {
			"mythling_0001",
			"mythling_0004",
			"mythling_0007",
			"mythling_0010",
			"mythling_0013",
			"mythling_0016",
		},
	},
	{
		rarity = "Epic",
		roll = 0.76,
		forms = {
			"mythling_0003",
			"mythling_0006",
			"mythling_0009",
			"mythling_0012",
			"mythling_0015",
			"mythling_0018",
		},
	},
	{
		rarity = "Rare",
		roll = 0.85,
		forms = {
			"mythling_0002",
			"mythling_0005",
			"mythling_0008",
			"mythling_0011",
			"mythling_0014",
			"mythling_0017",
		},
	},
}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function pool(): SpawnSelection.Pool
	local result, problem = SpawnSelection.Build(MythlingForms, MythlingSpawns.rarityWeights)
	assert(result, `[SpawnSelectionIntegration.spec] Invalid launch pool: {tostring(problem)}`)
	return result
end

local function population(): SpawnPopulation.State
	return SpawnPopulation.New(MythlingSpawns.targetActive, MythlingSpawns.refillDeadlineSeconds)
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function captureFixture()
	-- This token is only an injected caller identity, not a simulated engine Player.
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return "selection_station"
	end, 0)
	assert(prepared, `[SpawnSelectionIntegration.spec] Invalid fixture: {tostring(problem)}`)
	data.mythlings.trained = {
		typeId = "mythling_0003",
		variantId = "regular",
		claimedAt = 1,
		level = 50,
		xp = 123,
		pendingXp = 0.75,
	}
	data.mythlings.legacy = {
		typeId = "retained_prototype",
		variantId = "old",
		claimedAt = 2,
		level = 40,
		xp = 275,
	}
	-- Saved deferred fields are deliberately outside the launch owned-record contract.
	local legacy = data.mythlings.legacy :: any
	legacy.luck = 77
	legacy.traitIds = { "lucky", "insomniac" }
	data.base.shrines = {
		retained = {
			id = "retained",
			shrineId = "fire_shrine",
			buildSlotId = 1,
			level = 1,
			stored = 17,
			progress = 0.4,
			newWork = 0.2,
			workerIdsBySlot = { ["1"] = "trained" },
		},
	}
	data.currency.gold = 321
	data.materials.fire_material = { total = 7 }
	local state = { updates = 0, clocks = 0, ids = 0, inCallback = false }
	local source: CaptureGrant.DataSource = {
		GetLoadedData = function(caller: Player): Types.PlayerDoc?
			return if caller == player then data else nil
		end,
		Update = function(
			caller: Player,
			operation: string,
			mutate: ServerTypes.ProfileMutation
		): Types.TransactionResult
			expect(caller).toBe(player)
			expect(operation).toBe("CaptureMythling")
			state.updates += 1
			local revision = Transactions.GetRevision(data)
			return Transactions.Run(data, {
				id = `{revision}:capture_{state.updates}`,
				expectedRevision = revision,
				operation = operation,
				signature = "",
			}, function(draft)
				state.inCallback = true
				local result = mutate(draft, 50.25)
				state.inCallback = false
				return result
			end, function()
				return true
			end)
		end,
	}
	local grant = CaptureGrant.new(source, function()
		assert(state.inCallback, "[SpawnSelectionIntegration.spec] Clock outside transaction")
		state.clocks += 1
		return 50.25
	end, function()
		assert(state.inCallback, "[SpawnSelectionIntegration.spec] ID outside transaction")
		state.ids += 1
		return `caught_{state.ids}`
	end)
	return { player = player, data = data, state = state, grant = grant }
end

describe("canonical spawn selection integration", function()
	it("independently fills all twelve without enforcing rarity or element quotas", function()
		local selection = pool()
		local state = population()
		local selections = 0
		local function choose(): string?
			selections += 1
			return SpawnSelection.Choose(selection, 0.76, 0.1)
		end
		SpawnPopulation.QueueDeficits(state, 0, 100, choose)
		expect(selections).toBe(12)
		local attempts = SpawnPopulation.GetPending(state)
		expect(#attempts).toBe(12)
		expect(SpawnPopulation.OpenIfFilled(state, 0)).toBe(false)
		for index, attempt in attempts do
			expect(attempt.typeId).toBe("mythling_0003")
			expect(attempt.missingSince).toBe(100)
			expect(attempt.deadlineAt).toBe(103)
			SpawnPopulation.Complete(state, attempt.id)
			if index < 12 then
				expect(SpawnPopulation.OpenIfFilled(state, index)).toBe(false)
			end
		end
		expect(SpawnPopulation.OpenIfFilled(state, 12)).toBe(true)
		-- Registered overtime contests still occupy all twelve slots: no new random selections.
		SpawnPopulation.QueueDeficits(state, 12, 340, choose)
		expect(selections).toBe(12)
		expect(#SpawnPopulation.GetPending(state)).toBe(0)
	end)

	it(
		"retains independent replacement forms and original simultaneous deadlines through retries",
		function()
			local selection = pool()
			local state = population()
			expect(SpawnPopulation.OpenIfFilled(state, 12)).toBe(true)
			local selections = 0
			local function choose(): string?
				selections += 1
				local choice = launchChoices[(selections - 1) % #launchChoices + 1]
				return SpawnSelection.Choose(selection, choice.roll, 0.9)
			end
			SpawnPopulation.QueueDeficits(state, 4, 500, choose)
			local attempts = SpawnPopulation.GetPending(state)
			expect(#attempts).toBe(8)
			for index, attempt in attempts do
				local choice = launchChoices[(index - 1) % #launchChoices + 1]
				expect(attempt.typeId).toBe(choice.forms[6])
				expect(attempt.missingSince).toBe(500)
				expect(attempt.deadlineAt).toBe(503)
			end
			local beforeRetries = copy(attempts)
			-- Failed placement leaves pending attempts in place, even if its deadline is missed.
			for _, now in { 500.1, 501, 502.9, 504 } do
				SpawnPopulation.QueueDeficits(state, 4, now, choose)
				expect(SpawnPopulation.GetPending(state)).toEqual(beforeRetries)
			end
			SpawnPopulation.Complete(state, attempts[2].id)
			SpawnPopulation.QueueDeficits(state, 5, 504.1, choose)
			expect(selections).toBe(8)
			expect(#SpawnPopulation.GetPending(state)).toBe(7)
			for _, attempt in SpawnPopulation.GetPending(state) do
				expect(attempt).toBe(attempts[attempt.id])
				expect(attempt.deadlineAt).toBe(503)
			end
		end
	)

	it(
		"grants each of the eighteen queued forms unchanged without rewriting prior earnings",
		function()
			local selection = pool()
			local f = captureFixture()
			local expected = gameplay(f.data)
			local granted = 0
			for _, choice in launchChoices do
				for index, expectedFormId in choice.forms do
					local state = population()
					SpawnPopulation.QueueDeficits(state, 11, 50, function()
						return SpawnSelection.Choose(selection, choice.roll, (index - 0.5) / 6)
					end)
					local attempt = SpawnPopulation.GetPending(state)[1]
					expect(attempt.typeId).toBe(expectedFormId)
					expect(MythlingForms[expectedFormId].rarity).toBe(choice.rarity)
					local formId =
						assert(attempt.typeId, "[SpawnSelectionIntegration.spec] Missing form")
					granted += 1
					local instanceId = `caught_{granted}`
					expect(f.grant.Grant(f.player, { typeId = formId, variantId = "regular" })).toEqual({
						ok = true,
						revision = granted,
						values = { instanceId = instanceId },
					})
					-- Exact keys rule out owned rarity, stage, Luck/Trait rolls, or copied Yield.
					local record: Types.MythlingEntry = {
						typeId = expectedFormId,
						variantId = "regular",
						claimedAt = 50.25,
						level = 1,
						xp = 0,
						pendingXp = 0,
					}
					expect(f.data.mythlings[instanceId]).toEqual(record)
					expected.mythlings[instanceId] = record
					expect(gameplay(f.data)).toEqual(expected)
				end
			end
			expect(granted).toBe(18)
			expect(f.state.updates).toBe(18)
			expect(f.state.clocks).toBe(18)
			expect(f.state.ids).toBe(18)
		end
	)
end)
