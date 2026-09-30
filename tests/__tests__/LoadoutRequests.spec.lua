--!strict
-- ServerStorage/Tests/__tests__/LoadoutRequests.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local Configuration = require(ReplicatedStorage.Shared.Configurations.LoadoutRequests)
local LoadoutRequests = require(ServerScriptService.Services.CombatService.LoadoutRequests)
local LoadoutCommands = require(ServerScriptService.Services.CombatService.LoadoutCommands)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function fixture()
	-- The request boundary forwards Player as an opaque identity to injected callbacks.
	local player = (table.freeze({}) :: unknown) :: Player
	local state = {
		now = 10,
		isAvailable = true,
		isAllowed = true,
		isReady = true,
		admissions = 0,
		reads = 0,
		loads = 0,
		resolutions = 0,
		snapshots = 0,
		equips = 0,
		equippedId = "old",
		commandCalls = {} :: { string },
		caller = nil :: Player?,
		payload = nil :: unknown,
		receipt = { ok = true, revision = 4, values = { changed = true } } :: Types.TransactionResult,
	}
	local dataService = {
		GetLoadedData = function(_player: Player)
			state.reads += 1
			return if state.isReady then PlayerDataTemplate else nil
		end,
		Load = function(_player: Player)
			state.loads += 1
			return true
		end,
	}
	local api = LoadoutRequests.new({
		DataService = dataService,
		isAvailable = function(_player)
			return state.isAvailable
		end,
		allowRequest = function(_player)
			state.admissions += 1
			return state.isAllowed
		end,
		snapshotLoadout = function(_player)
			state.snapshots += 1
			return { equipment = {}, primaryWeaponInstanceId = state.equippedId }
		end,
		equipOwnedInstance = function(_player, instanceId)
			state.equips += 1
			if instanceId ~= "owned" then
				return false, "NotOwned"
			end
			state.equippedId = instanceId
			return true, nil
		end,
		equipEquipment = function(caller: Player, payload: unknown): Types.TransactionResult
			table.insert(state.commandCalls, "EquipEquipment")
			state.caller, state.payload = caller, payload
			return state.receipt
		end,
		unequipEquipment = function(caller: Player, payload: unknown): Types.TransactionResult
			table.insert(state.commandCalls, "UnequipEquipment")
			state.caller, state.payload = caller, payload
			return state.receipt
		end,
		now = function()
			return state.now
		end,
	})
	return { player = player, state = state, api = api }
end

local function mutate(
	requests: LoadoutRequests.Requests,
	method: string,
	player: Player,
	payload: unknown
): (boolean, string?)
	if method == "Equip" then
		local result = requests.Equip(player, payload)
		return result.ok, result.code
	elseif method == "EquipEquipment" then
		local result = requests.EquipEquipment(player, payload)
		return result.ok, result.code
	end
	local result = requests.UnequipEquipment(player, payload)
	return result.ok, result.code
end

describe("LoadoutRequests", function()
	it("rejects rate-limited requests before profile reads, loads, or protected work", function()
		local f = fixture()
		f.state.isAllowed = false
		expect(f.api.Get(f.player)).toEqual({ ok = false, code = "RateLimited" })
		expect(f.api.Equip(f.player, "owned")).toEqual({ ok = false, code = "RateLimited" })
		expect(f.state.reads).toBe(0)
		expect(f.state.loads).toBe(0)
		expect(f.state.resolutions).toBe(0)
		expect(f.state.snapshots).toBe(0)
		expect(f.state.equips).toBe(0)
		expect(f.state.equippedId).toBe("old")
	end)

	it("returns NotReady without initiating a load, building a snapshot, or mutating", function()
		local f = fixture()
		f.state.isReady = false
		expect(f.api.Get(f.player)).toEqual({ ok = false, code = "NotReady" })
		expect(f.api.Equip(f.player, "owned")).toEqual({ ok = false, code = "NotReady" })
		expect(f.state.admissions).toBe(2)
		expect(f.state.reads).toBe(2)
		expect(f.state.loads).toBe(0)
		expect(f.state.resolutions).toBe(0)
		expect(f.state.snapshots).toBe(0)
		expect(f.state.equips).toBe(0)
		expect(f.state.equippedId).toBe("old")
	end)

	it("rejects requests after departure or shutdown without allocating admission state", function()
		local f = fixture()
		f.state.isAvailable = false
		expect(f.api.Get(f.player)).toEqual({ ok = false, code = "Unavailable" })
		expect(f.api.Equip(f.player, "owned")).toEqual({ ok = false, code = "Unavailable" })
		expect(f.state.admissions).toBe(0)
		expect(f.state.reads).toBe(0)
		expect(f.state.loads).toBe(0)
		expect(f.state.resolutions).toBe(0)
		expect(f.state.snapshots).toBe(0)
		expect(f.state.equips).toBe(0)
	end)

	it("returns a successful snapshot from already-loaded state", function()
		local f = fixture()
		expect(f.api.Get(f.player)).toEqual({
			ok = true,
			snapshot = { equipment = {}, primaryWeaponInstanceId = "old" },
		})
		expect(f.state.resolutions).toBe(0)
		expect(f.state.snapshots).toBe(1)
		expect(f.state.loads).toBe(0)
		expect(f.state.equips).toBe(0)
	end)

	it("permits a ready retry without charging an Equip cooldown for NotReady", function()
		local f = fixture()
		f.state.isReady = false
		expect(f.api.Equip(f.player, "owned").ok).toBe(false)
		f.state.isReady = true
		expect(f.api.Equip(f.player, "owned")).toEqual({
			ok = true,
			snapshot = { equipment = {}, primaryWeaponInstanceId = "owned" },
		})
		expect(f.state.loads).toBe(0)
		expect(f.state.equips).toBe(1)
		expect(f.state.snapshots).toBe(1)
	end)

	it(
		"rejects repeated Equip before profile work while allowing the next cooldown deadline",
		function()
			local f = fixture()
			expect(f.api.Equip(f.player, "owned").ok).toBe(true)
			f.state.now = 10.49
			expect(f.api.Equip(f.player, "owned")).toEqual({ ok = false, code = "RateLimited" })
			expect(f.state.reads).toBe(1)
			expect(f.state.equips).toBe(1)
			expect(f.state.snapshots).toBe(1)
			f.state.now = 10.5
			expect(f.api.Equip(f.player, "owned").ok).toBe(true)
			expect(f.state.equips).toBe(2)
			expect(f.state.loads).toBe(0)
		end
	)

	it("returns a small ownership rejection without building a snapshot", function()
		local f = fixture()
		expect(f.api.Equip(f.player, "not-owned")).toEqual({ ok = false, code = "NotOwned" })
		expect(f.state.equippedId).toBe("old")
		expect(f.state.snapshots).toBe(0)
		expect(f.state.loads).toBe(0)
	end)

	it("releases per-player and service cooldown state through its owner cleanup", function()
		local f = fixture()
		expect(f.api.Equip(f.player, "owned").ok).toBe(true)
		f.api.Forget(f.player)
		expect(f.api.Equip(f.player, "owned").ok).toBe(true)
		f.api.Clear()
		expect(f.api.Equip(f.player, "owned").ok).toBe(true)
	end)

	it(
		"maps canonical admission failures before commands or snapshots and permits ready retries",
		function()
			for _, name in { "EquipEquipment", "UnequipEquipment" } do
				local f = fixture()
				local command = if name == "EquipEquipment"
					then f.api.EquipEquipment
					else f.api.UnequipEquipment
				f.state.isAvailable = false
				expect(command(f.player, {})).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
				expect(f.state.admissions).toBe(0)
				f.state.isAvailable = true
				f.state.isAllowed = false
				expect(command(f.player, {})).toEqual({
					ok = false,
					code = "RateLimited",
					revision = 0,
				})
				expect(f.state.reads).toBe(0)
				f.state.isAllowed = true
				f.state.isReady = false
				expect(command(f.player, {})).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
				expect(f.state.reads).toBe(1)
				expect(f.state.commandCalls).toEqual({})
				f.state.isReady = true
				expect(command(f.player, {})).toBe(f.state.receipt)
				expect(f.state.commandCalls).toEqual({ name })
				expect(f.state.loads).toBe(0)
				expect(f.state.snapshots).toBe(0)
				expect(f.state.equips).toBe(0)
			end
		end
	)

	it("shares one configured change interval across every mutation route, but not Get", function()
		expect(Configuration.requestBurst).toBe(12)
		expect(Configuration.requestRefillPerSecond).toBe(4)
		expect(Configuration.mutationIntervalSeconds).toBe(0.5)
		for _, first in { "Equip", "EquipEquipment", "UnequipEquipment" } do
			for _, second in { "Equip", "EquipEquipment", "UnequipEquipment" } do
				local f = fixture()
				expect((mutate(f.api, first, f.player, "owned"))).toBe(true)
				f.state.now = 10.49
				local ok, code = mutate(f.api, second, f.player, "owned")
				expect(ok).toBe(false)
				expect(code).toBe("RateLimited")
				expect(f.state.reads).toBe(1)
				expect(f.api.Get(f.player).ok).toBe(true)
				f.state.now = 10.5
				expect((mutate(f.api, second, f.player, "owned"))).toBe(true)
				expect(f.state.admissions).toBe(4)
				expect(f.state.reads).toBe(3)
				expect(f.state.loads).toBe(0)
			end
		end
	end)

	it(
		"forwards raw caller and payload, preserving frozen success, replay, and rejection receipts",
		function()
			for _, name in { "EquipEquipment", "UnequipEquipment" } do
				local receipts: { Types.TransactionResult } = {
					{ ok = true, revision = 7, values = { changed = true, finishId = "fire" } },
					{ ok = true, revision = 7, replayed = true, values = { changed = true } },
					{ ok = false, revision = 8, code = "SlotChanged" },
				}
				for _, receipt in receipts do
					local f = fixture()
					local command = if name == "EquipEquipment"
						then f.api.EquipEquipment
						else f.api.UnequipEquipment
					f.state.receipt = receipt
					-- Install the typed alias before freeze narrows this local to read-only fields.
					if receipt.values then
						table.freeze(receipt.values)
					end
					table.freeze(receipt)
					local payload = table.freeze({ targetUserId = 9001, unexpected = true })
					expect(command(f.player, payload)).toBe(receipt)
					expect(f.state.caller).toBe(f.player)
					expect(f.state.payload).toBe(payload)
					expect(f.state.commandCalls).toEqual({ name })
					expect(f.state.snapshots).toBe(0)
					expect(f.state.equips).toBe(0)
					expect(command(f.player, payload)).toEqual({
						ok = false,
						code = "RateLimited",
						revision = 0,
					})
					expect(f.state.reads).toBe(1)
				end
			end
		end
	)

	it(
		"keeps per-player cooldowns independent and releases canonical state on Forget and Clear",
		function()
			local f = fixture()
			local other = (table.freeze({}) :: unknown) :: Player
			expect(f.api.EquipEquipment(f.player, {}).ok).toBe(true)
			expect(f.api.UnequipEquipment(other, {}).ok).toBe(true)
			f.api.Forget(f.player)
			expect(f.api.UnequipEquipment(f.player, {}).ok).toBe(true)
			expect(f.api.EquipEquipment(other, {}).code).toBe("RateLimited")
			f.api.Clear()
			expect(f.api.EquipEquipment(f.player, {}).ok).toBe(true)
			expect(f.api.UnequipEquipment(other, {}).ok).toBe(true)
		end
	)

	it(
		"replays real equip and unequip transactions without reselecting a now-empty slot",
		function()
			local data = (
				HttpService:JSONDecode(HttpService:JSONEncode(PlayerDataTemplate)) :: unknown
			) :: Types.PlayerDoc
			assert(ProfileSchema.Prepare(data, function()
				return "request_station"
			end, 0))
			data.equipment.selected = { definitionId = "elemental_sword", finishId = "fire" }
			data.combatLoadout = {}
			local owned = data.equipment.selected
			local player = (table.freeze({}) :: unknown) :: Player
			local state = { now = 10, mutations = 0, snapshots = 0 }
			local source: LoadoutCommands.DataSource = {
				GetLoadedData = function(_player: Player): Types.PlayerDoc?
					return data
				end,
				Transact = function(_player, request, mutation)
					return Transactions.Run(data, request, function(draft)
						state.mutations += 1
						return mutation(draft, state.now)
					end, function()
						return true
					end)
				end,
			}
			local commands = LoadoutCommands.new(source)
			local requests = LoadoutRequests.new({
				DataService = source,
				isAvailable = function()
					return true
				end,
				allowRequest = function()
					return true
				end,
				snapshotLoadout = function()
					state.snapshots += 1
					return { equipment = {} }
				end,
				equipOwnedInstance = function()
					error("Canonical commands must not use the legacy adapter")
				end,
				equipEquipment = function(caller: Player, input: unknown): Types.TransactionResult
					return commands.Equip(caller, input :: Types.EquipEquipmentRequest)
				end,
				unequipEquipment = function(
					caller: Player,
					input: unknown
				): Types.TransactionResult
					return commands.Unequip(caller, input :: Types.UnequipEquipmentRequest)
				end,
				now = function()
					return state.now
				end,
			})
			local equip: Types.EquipEquipmentRequest = {
				requestId = "0:equip",
				expectedRevision = 0,
				instanceId = "selected",
				expectedDefinitionId = "elemental_sword",
				expectedFinishId = "fire",
			}
			local equipped = requests.EquipEquipment(player, equip)
			expect(equipped.ok).toBe(true)
			expect(data.combatLoadout.primaryWeaponInstanceId).toBe("selected")
			state.now += 0.5
			local unequip: Types.UnequipEquipmentRequest = {
				requestId = "1:unequip",
				expectedRevision = 1,
				slot = "PrimaryWeapon",
				expectedInstanceId = "selected",
			}
			local unequipped = requests.UnequipEquipment(player, unequip)
			expect(unequipped.ok).toBe(true)
			state.now += 0.5
			local replayedEquip = requests.EquipEquipment(player, equip)
			expect(replayedEquip.replayed).toBe(true)
			expect(replayedEquip.values).toEqual(equipped.values)
			expect(data.combatLoadout.primaryWeaponInstanceId).toBeNil()
			state.now += 0.5
			local replayedUnequip = requests.UnequipEquipment(player, unequip)
			expect(replayedUnequip.replayed).toBe(true)
			expect(replayedUnequip.values).toEqual(unequipped.values)
			expect(state.mutations).toBe(2)
			state.now += 0.5
			local forged: any = table.clone(equip)
			forged.requestId, forged.expectedRevision, forged.targetUserId = "2:forged", 2, 9001
			expect(requests.EquipEquipment(player, forged).code).toBe("InvalidRequest")
			expect(state.mutations).toBe(2)
			expect(data.combatLoadout.primaryWeaponInstanceId).toBeNil()
			expect(data.equipment.selected).toBe(owned)
			expect(state.snapshots).toBe(0)
		end
	)
end)
