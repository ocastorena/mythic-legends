--!strict
-- ServerStorage/Tests/__tests__/CaptureGrant.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local PrototypeMythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local CaptureGrant = require(ServerScriptService.Services.InventoryService.CaptureGrant)
local ShrineWorkers = require(ServerScriptService.Services.BaseService.ShrineWorkers)
local ProfileProduction = require(ServerScriptService.Services.ProductionService.ProfileProduction)
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

local function legacyWorker(): Types.MythlingEntry
	return {
		typeId = "retained_form",
		variantId = "old",
		claimedAt = 1,
		level = 40,
		xp = 275,
		standId = 1,
	}
end

local function profile(count: number): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return "capture_station"
	end, 0)
	assert(prepared, `[CaptureGrant.spec] Fixture preparation failed: {tostring(problem)}`)
	for index = 1, count do
		data.mythlings[`existing_{index}`] = legacyWorker()
	end
	return data
end

local function fixture(
	count: number?,
	clockOverride: (() -> number)?,
	createIdOverride: (() -> string)?
)
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local data = profile(count or 0)
	local state = {
		now = 50.25,
		available = true,
		active = true,
		inCallback = false,
		loseSessionAfterCallback = false,
		clockCalls = 0,
		idCalls = 0,
		updateCalls = 0,
		beforeUpdate = nil :: ((Types.PlayerDoc) -> ())?,
	}
	local function transact(
		_player: Player,
		request: Types.TransactionRequest,
		mutate: ServerTypes.ProfileMutation
	): Types.TransactionResult
		return Transactions.Run(data, request, function(draft)
			state.inCallback = true
			local result = mutate(draft, state.now)
			state.inCallback = false
			if state.loseSessionAfterCallback then
				state.active = false
			end
			return result
		end, function()
			return state.active and state.available
		end)
	end
	local dataSource: CaptureGrant.DataSource & ShrineWorkers.DataSource = {
		GetLoadedData = function(requestingPlayer: Player): Types.PlayerDoc?
			return if requestingPlayer == player
					and state.active
					and state.available
				then data
				else nil
		end,
		Transact = transact,
		Update = function(requestingPlayer, operation, mutate)
			state.updateCalls += 1
			local beforeUpdate = state.beforeUpdate
			if beforeUpdate then
				beforeUpdate(data)
			end
			local revision = Transactions.GetRevision(data)
			return transact(requestingPlayer, {
				id = `{revision}:update_{state.updateCalls}`,
				expectedRevision = revision,
				operation = operation,
				signature = "",
			}, mutate)
		end,
	}
	local api = CaptureGrant.new(dataSource, function()
		state.clockCalls += 1
		assert(state.inCallback, "[CaptureGrant.spec] Clock must run inside transaction")
		return if clockOverride then clockOverride() else state.now
	end, function()
		state.idCalls += 1
		assert(state.inCallback, "[CaptureGrant.spec] ID must run inside transaction")
		return if createIdOverride then createIdOverride() else `new_{state.idCalls}`
	end)
	return { player = player, data = data, state = state, dataSource = dataSource, api = api }
end

local function grant(
	api: CaptureGrant.CaptureGrant,
	player: Player,
	formId: string?
): Types.TransactionResult
	return api.Grant(player, { typeId = formId or "mythling_0001", variantId = "regular" })
end

describe("CaptureGrant", function()
	it(
		"grants every canonical form at level 1 with complete zero-XP accounting and no bonus fields",
		function()
			local count = 0
			for formId in MythlingForms do
				count += 1
				local f = fixture()
				local before = gameplay(f.data)
				expect(grant(f.api, f.player, formId)).toEqual({
					ok = true,
					revision = 1,
					values = { instanceId = "new_1" },
				})
				expect(f.data.mythlings.new_1).toEqual({
					typeId = formId,
					variantId = "regular",
					claimedAt = 50.25,
					level = 1,
					xp = 0,
					pendingXp = 0,
				})
				before.mythlings.new_1 = copy(f.data.mythlings.new_1)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.state.clockCalls).toBe(1)
				expect(f.state.idCalls).toBe(1)
				expect(f.state.updateCalls).toBe(1)
			end
			expect(count).toBe(18)
		end
	)

	it(
		"temporarily accepts only configured prototype forms and their configured variants",
		function()
			for formId, definition in PrototypeMythlings do
				for variantId in definition.variants do
					local f = fixture()
					expect(f.api.Grant(f.player, { typeId = formId, variantId = variantId }).ok).toBe(
						true
					)
					expect(f.data.mythlings.new_1).toEqual({
						typeId = formId,
						variantId = variantId,
						claimedAt = 50.25,
						level = 1,
						xp = 0,
						pendingXp = 0,
					})
				end
			end
		end
	)

	it(
		"never resets trained owned progression or activates retained legacy Luck and Traits",
		function()
			local f = fixture(1)
			local trained: Types.MythlingEntry = {
				typeId = "mythling_0003",
				variantId = "regular",
				claimedAt = 20,
				level = 50,
				xp = 27.5,
				pendingXp = 0.75,
			}
			f.data.mythlings.trained = trained
			local legacy = f.data.mythlings.existing_1 :: any
			legacy.luck = 77
			legacy.traitIds = { "lucky", "insomniac" }
			local before = gameplay(f.data)
			expect(grant(f.api, f.player, "mythling_0003").ok).toBe(true)
			before.mythlings.new_1 = copy(f.data.mythlings.new_1)
			expect(gameplay(f.data)).toEqual(before)
			expect(f.data.mythlings.trained).toBe(trained)
			expect(f.data.mythlings.existing_1).toBe(legacy)
			expect(f.data.mythlings.new_1.level).toBe(1)
		end
	)

	it(
		"rejects unknown definitions, canonical cosmetic variants, and unconfigured prototype variants",
		function()
			for _, request in
				{
					{ typeId = "unknown_form", variantId = "regular", code = "InvalidMythling" },
					{ typeId = "mythling_0001", variantId = "shiny", code = "InvalidVariant" },
					{ typeId = "dragon", variantId = "shiny", code = "InvalidVariant" },
				}
			do
				local f = fixture()
				local before = gameplay(f.data)
				expect(
					f.api.Grant(
						f.player,
						{ typeId = request.typeId, variantId = request.variantId }
					).code
				).toBe(request.code)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.state.clockCalls).toBe(0)
				expect(f.state.idCalls).toBe(0)
			end
		end
	)

	it(
		"accepts only a closed two-ID request and rejects client-supplied progression or payout",
		function()
			local invalid: { any } = {
				false,
				"form",
				{},
				setmetatable({ typeId = "mythling_0001", variantId = "regular" }, {}),
			}
			for _, field in
				{
					"level",
					"xp",
					"pendingXp",
					"luck",
					"traitIds",
					"claimedAt",
					"instanceId",
					"player",
					"gold",
					"rarity",
				}
			do
				local request: any = { typeId = "mythling_0001", variantId = "regular" }
				request[field] = 1
				table.insert(invalid, request)
			end
			for _, field in { "typeId", "variantId" } do
				for _, value in { "", string.rep("x", 129), 5, false } do
					local request: any = { typeId = "mythling_0001", variantId = "regular" }
					request[field] = value
					table.insert(invalid, request)
				end
			end
			for _, request in invalid do
				local f = fixture()
				local before = copy(f.data)
				expect(f.api.Grant(f.player, request).code).toBe("InvalidRequest")
				expect(f.data).toEqual(before)
				expect(f.state.updateCalls).toBe(0)
			end
		end
	)

	it(
		"uses purchased limits and counts legacy or assigned entries toward the final slot",
		function()
			for upgrade, limit in { [0] = 24, [1] = 36, [2] = 48 } do
				local f = fixture(limit - 1)
				f.data.inventoryUpgrades = { mythlings = upgrade }
				expect(grant(f.api, f.player).ok).toBe(true)
				local after = gameplay(f.data)
				expect(grant(f.api, f.player).code).toBe("InventoryFull")
				expect(gameplay(f.data)).toEqual(after)
				expect(f.state.clockCalls).toBe(1)
				expect(f.state.idCalls).toBe(1)
			end
			local f = fixture(49)
			f.data.inventoryUpgrades = { mythlings = 2 }
			local before = gameplay(f.data)
			expect(grant(f.api, f.player).code).toBe("InventoryFull")
			expect(gameplay(f.data)).toEqual(before)
		end
	)

	it(
		"rechecks capacity inside the transaction after another grant fills the last slot",
		function()
			local f = fixture(23)
			f.state.beforeUpdate = function(data)
				data.mythlings.competing = legacyWorker()
			end
			expect(grant(f.api, f.player).code).toBe("InventoryFull")
			expect(f.data.mythlings.competing).never.toBeNil()
			expect(f.data.mythlings.new_1).toBeNil()
			expect(f.state.clockCalls).toBe(0)
			expect(f.state.idCalls).toBe(0)
		end
	)

	it(
		"fails closed for invalid schema, ownership maps, records, and purchased upgrade state",
		function()
			for _, failure in
				{
					"version",
					"map",
					"record",
					"key",
					"typeId",
					"upgrades",
					"negative",
					"fractional",
					"past-cap",
				}
			do
				local f = fixture(1)
				local raw = f.data :: any
				local code = "InvalidInventoryState"
				if failure == "version" then
					f.data.version = 3
					code = "UnsupportedVersion"
				elseif failure == "map" then
					raw.mythlings = false
				elseif failure == "record" then
					raw.mythlings.existing_1 = "broken"
				elseif failure == "key" then
					f.data.mythlings[""] = legacyWorker()
				elseif failure == "typeId" then
					f.data.mythlings.existing_1.typeId = ""
				else
					code = "InvalidInventoryUpgrade"
					if failure == "upgrades" then
						raw.inventoryUpgrades = false
					else
						f.data.inventoryUpgrades = {
							mythlings = if failure == "negative"
								then -1
								elseif failure == "fractional" then 0.5
								else 3,
						}
					end
				end
				local before = gameplay(f.data)
				expect(grant(f.api, f.player).code).toBe(code)
				expect(gameplay(f.data)).toEqual(before)
				expect(f.state.clockCalls).toBe(0)
				expect(f.state.idCalls).toBe(0)
			end
		end
	)

	it("never loads unavailable profiles or commits after its session ends", function()
		local f = fixture()
		local before = copy(f.data)
		f.state.available = false
		expect(grant(f.api, f.player).code).toBe("DataUnavailable")
		expect(f.state.updateCalls).toBe(0)
		f.state.available = true
		f.state.loseSessionAfterCallback = true
		expect(grant(f.api, f.player).code).toBe("DataUnavailable")
		expect(f.data).toEqual(before)
		expect(f.state.clockCalls).toBe(1)
		expect(f.state.idCalls).toBe(1)
	end)

	it(
		"rejects colliding or malformed generated IDs instead of overwriting existing owned work",
		function()
			for _, id in { "existing_1", "", string.rep("x", 129) } do
				local f = fixture(1, nil, function()
					return id
				end)
				local before = gameplay(f.data)
				expect(grant(f.api, f.player).code).toBe("InstanceIdConflict")
				expect(gameplay(f.data)).toEqual(before)
				expect(f.state.idCalls).toBe(1)
			end
		end
	)

	it(
		"rejects non-finite or negative server timestamps before allocating an owned identity",
		function()
			for _, timestamp in { -1, math.huge, 0 / 0, 2 ^ 53 } do
				local f = fixture()
				f.state.now = timestamp
				local before = gameplay(f.data)
				expect(grant(f.api, f.player).code).toBe("InvalidTimestamp")
				expect(gameplay(f.data)).toEqual(before)
				expect(f.state.idCalls).toBe(0)
			end
		end
	)

	it("rolls back clock or ID errors and yields without an owned record or receipt", function()
		for _, source in { "clock", "id" } do
			for _, yields in { false, true } do
				local function badClock(): number
					if yields then
						coroutine.yield()
					end
					error("intentional clock failure")
				end
				local function badId(): string
					if yields then
						coroutine.yield()
					end
					error("intentional ID failure")
				end
				local f = fixture(
					0,
					if source == "clock" then badClock else nil,
					if source == "id" then badId else nil
				)
				local before = copy(f.data)
				expect(grant(f.api, f.player).code).toBe(
					if yields then "MutationYielded" else "MutationFailed"
				)
				expect(f.data).toEqual(before)
			end
		end
	end)

	it(
		"produces a canonical record usable by Ready, assignment, and checkpoint settlement",
		function()
			local f = fixture()
			f.state.now = 0
			expect(grant(f.api, f.player).ok).toBe(true)
			f.data.base.shrines = {
				first = {
					id = "first",
					shrineId = "fire_shrine",
					buildSlotId = 1,
					level = 1,
					stored = 0,
					progress = 0,
					newWork = 0,
					workerIdsBySlot = {},
				},
			}
			expect(f.dataSource.Update(f.player, "Test.Ready", function(draft)
				return ProfileProduction.Settle(draft, 10, "Ready")
			end).ok).toBe(true)
			expect(f.data.mythlings.new_1.level).toBe(1)
			expect(f.data.mythlings.new_1.xp).toBe(0)
			local workers = ShrineWorkers.new(f.dataSource, function()
				return 10
			end)
			expect(workers.Assign(f.player, {
				requestId = "2:assign",
				expectedRevision = 2,
				shrineInstanceId = "first",
				slotId = 1,
				workerId = "new_1",
			}).ok).toBe(true)
			expect(f.dataSource.Update(f.player, "Test.Checkpoint", function(draft)
				return ProfileProduction.Settle(draft, 11, "Checkpoint")
			end).ok).toBe(true)
			expect(f.data.mythlings.new_1.level).toBe(1)
			expect(f.data.mythlings.new_1.xp).toBe(1)
			expect(f.data.mythlings.new_1.pendingXp).toBe(0)
			local shrines = assert(f.data.base.shrines, "[CaptureGrant.spec] Expected built Shrine")
			expect(shrines.first.progress).toBeCloseTo(12 / 3_600, 10)
			expect(shrines.first.workerIdsBySlot).toEqual({ ["1"] = "new_1" })
			expect(f.data.productionClock).toEqual({
				lastAccruedAt = 11,
				nextBatchAt = 12,
				lastOnlineCheckpointAt = 11,
			})
		end
	)
end)
