--!strict
-- ServerStorage/Tests/__tests__/LoadoutCommands.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(ReplicatedStorage.Shared.Configurations.PlayerData)
local EquipmentCatalog = require(ReplicatedStorage.Shared.EquipmentCatalog)
local LoadoutCommands = require(ServerScriptService.Services.CombatService.LoadoutCommands)
local ProfileSchema = require(ServerScriptService.Services.DataService.ProfileSchema)
local Transactions = require(ServerScriptService.Services.DataService.Transactions)
local PlayerDataTemplate = require(ServerStorage.Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local FINISHES = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function gameplay(data: Types.PlayerDoc): Types.PlayerDoc
	local result = copy(data)
	result.transactions = nil
	return result
end

local function profile(): Types.PlayerDoc
	local data = copy(PlayerDataTemplate)
	local prepared, problem = ProfileSchema.Prepare(data, function()
		return "loadout_station"
	end, 0)
	assert(prepared, `[LoadoutCommands.spec] Fixture preparation failed: {tostring(problem)}`)
	data.equipment.selected = { definitionId = "elemental_sword", finishId = "fire" }
	data.equipment.shield = { definitionId = "elemental_shield", finishId = "water" }
	data.materials.fire_material = { total = 15 }
	data.mythlings.worker = {
		typeId = "mythling_0001",
		variantId = "regular",
		claimedAt = 0,
		level = 6,
		xp = 12,
		pendingXp = 0.5,
	}
	data.base.shrines = {
		first = {
			id = "first",
			shrineId = "fire_shrine",
			buildSlotId = 1,
			level = 1,
			stored = 20,
			progress = 0.25,
			newWork = 0.01,
			workerIdsBySlot = { ["1"] = "worker" },
		},
	}
	data.craftingJobs = {
		legacy = {
			status = "Active",
			reservations = { equipment = 1, materials = { fire_material = 5 } },
		},
	}
	return data
end

-- Forged payload cases are confined to this untrusted input boundary.
local function equip(revision: number, token: string): any
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		instanceId = "selected",
		expectedDefinitionId = "elemental_sword",
		expectedFinishId = "fire",
	}
end

local function unequip(revision: number, token: string): any
	return {
		requestId = `{revision}:{token}`,
		expectedRevision = revision,
		slot = "PrimaryWeapon",
		expectedInstanceId = "starter_wooden_sword",
	}
end

local function fixture(saved: Types.PlayerDoc?, resolver: LoadoutCommands.Resolver?)
	-- Private commands only forward identity; the public facade validates engine Players.
	local player = (table.freeze({ UserId = 1001 }) :: unknown) :: Player
	local data = saved or profile()
	local state = {
		now = 10,
		active = true,
		available = true,
		loseSessionAfterCallback = false,
		transactionCalls = 0,
		callbackCalls = 0,
		operations = {} :: { string },
	}
	local source: LoadoutCommands.DataSource = {
		GetLoadedData = function(requestingPlayer: Player): Types.PlayerDoc?
			return if requestingPlayer == player
					and state.active
					and state.available
				then data
				else nil
		end,
		Transact = function(requestingPlayer, request, mutate)
			state.transactionCalls += 1
			table.insert(state.operations, request.operation)
			if requestingPlayer ~= player or not state.available then
				return { ok = false, code = "DataUnavailable", revision = 0 }
			end
			return Transactions.Run(data, request, function(draft)
				state.callbackCalls += 1
				local result = mutate(draft, state.now)
				if state.loseSessionAfterCallback then
					state.active = false
				end
				return result
			end, function()
				return state.active
			end)
		end,
	}
	return {
		player = player,
		data = data,
		state = state,
		api = LoadoutCommands.new(source, resolver),
	}
end

local function resolveFuture(definitionId: unknown, finishId: unknown?): Types.ResolvedEquipment?
	if definitionId == "future_two_hand" and finishId == nil then
		-- Isolated compatibility data, never an enabled launch definition or attack archetype.
		local resolved = copy(assert(EquipmentCatalog.Resolve("wooden_sword", nil)))
		resolved.definitionId = "future_two_hand"
		resolved.profile.handsRequired = 2
		return resolved
	end
	return EquipmentCatalog.Resolve(definitionId, finishId)
end

local function futureSelection(revision: number, token: string): any
	local request = equip(revision, token)
	request.instanceId = "future"
	request.expectedDefinitionId = "future_two_hand"
	request.expectedFinishId = nil
	return request
end

local function shieldSelection(revision: number, token: string): any
	local request = equip(revision, token)
	request.instanceId = "shield"
	request.expectedDefinitionId = "elemental_shield"
	request.expectedFinishId = "water"
	return request
end

describe("LoadoutCommands", function()
	it(
		"equips all twelve named variants without touching ownership, economics, or progression",
		function()
			for _, definitionId in { "elemental_sword", "elemental_shield" } do
				for _, finishId in FINISHES do
					local f = fixture()
					f.data.equipment.selected = { definitionId = definitionId, finishId = finishId }
					local before = gameplay(f.data)
					local request = equip(0, "variant")
					request.expectedDefinitionId = definitionId
					request.expectedFinishId = finishId
					local isSword = definitionId == "elemental_sword"
					expect(f.api.Equip(f.player, request)).toEqual({
						ok = true,
						revision = 1,
						values = {
							instanceId = "selected",
							definitionId = definitionId,
							finishId = finishId,
							slot = if isSword then "PrimaryWeapon" else "Shield",
							changed = true,
							shieldUnequipped = false,
						},
					})
					if isSword then
						before.combatLoadout.primaryWeaponInstanceId = "selected"
					else
						before.combatLoadout.shieldInstanceId = "selected"
					end
					expect(gameplay(f.data)).toEqual(before)
					expect(f.state.operations).toEqual({ "Combat.EquipEquipment" })
				end
			end
		end
	)

	it(
		"permits protected starter selections without requiring finishes or changing starter flags",
		function()
			for _, kind in { "sword", "shield" } do
				local f = fixture()
				f.data.combatLoadout = {}
				local before = gameplay(f.data)
				local request = equip(0, "starter")
				request.instanceId = `starter_wooden_{kind}`
				request.expectedDefinitionId = `wooden_{kind}`
				request.expectedFinishId = nil
				expect(f.api.Equip(f.player, request).ok).toBe(true)
				if kind == "sword" then
					before.combatLoadout.primaryWeaponInstanceId = request.instanceId
				else
					before.combatLoadout.shieldInstanceId = request.instanceId
				end
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"allows independent empty slots and a Shield with no primary without automatic restoration",
		function()
			local f = fixture()
			local before = gameplay(f.data)
			expect(f.api.Unequip(f.player, unequip(0, "empty-primary")).ok).toBe(true)
			expect(f.data.combatLoadout).toEqual({ shieldInstanceId = "starter_wooden_shield" })
			expect(f.api.Equip(f.player, shieldSelection(1, "shield-only")).ok).toBe(true)
			local removeShield = unequip(2, "empty-shield")
			removeShield.slot = "Shield"
			removeShield.expectedInstanceId = "shield"
			expect(f.api.Unequip(f.player, removeShield).ok).toBe(true)
			expect(f.data.combatLoadout).toEqual({})
			before.combatLoadout = {}
			expect(gameplay(f.data)).toEqual(before)
			expect(f.state.operations).toEqual({
				"Combat.UnequipEquipment",
				"Combat.EquipEquipment",
				"Combat.UnequipEquipment",
			})
		end
	)

	it("returns an unchanged success for re-equipping the same compatible instance", function()
		local f = fixture()
		f.data.combatLoadout.primaryWeaponInstanceId = "selected"
		local before = gameplay(f.data)
		expect(f.api.Equip(f.player, equip(0, "same"))).toEqual({
			ok = true,
			revision = 1,
			values = {
				instanceId = "selected",
				definitionId = "elemental_sword",
				finishId = "fire",
				slot = "PrimaryWeapon",
				changed = false,
				shieldUnequipped = false,
			},
		})
		expect(gameplay(f.data)).toEqual(before)
	end)

	it(
		"clears only the Shield reference for future two-hand weapons and never restores it automatically",
		function()
			for _, returnByUnequip in { false, true } do
				local f = fixture(nil, resolveFuture)
				f.data.equipment.future = { definitionId = "future_two_hand" }
				local owned = copy(f.data.equipment)
				local result = f.api.Equip(f.player, futureSelection(0, "two-hand"))
				expect(result.ok).toBe(true)
				expect(result.values).toEqual({
					instanceId = "future",
					definitionId = "future_two_hand",
					slot = "PrimaryWeapon",
					changed = true,
					shieldUnequipped = true,
				})
				expect(f.data.combatLoadout).toEqual({ primaryWeaponInstanceId = "future" })
				if returnByUnequip then
					local request = unequip(1, "remove-two-hand")
					request.expectedInstanceId = "future"
					expect(f.api.Unequip(f.player, request).ok).toBe(true)
				else
					expect(f.api.Equip(f.player, equip(1, "one-hand")).ok).toBe(true)
				end
				expect(f.data.combatLoadout.shieldInstanceId).toBeNil()
				expect(f.data.equipment).toEqual(owned)
				expect(f.api.Equip(f.player, shieldSelection(2, "manual-shield")).ok).toBe(true)
			end
		end
	)

	it(
		"repairs same two-hand selection compatibility and rejects even the already-selected Shield",
		function()
			local f = fixture(nil, resolveFuture)
			f.data.equipment.future = { definitionId = "future_two_hand" }
			f.data.combatLoadout =
				{ primaryWeaponInstanceId = "future", shieldInstanceId = "shield" }
			local before = gameplay(f.data)
			expect(f.api.Equip(f.player, shieldSelection(0, "blocked")).code).toBe(
				"ShieldIncompatible"
			)
			expect(gameplay(f.data)).toEqual(before)
			local repaired = f.api.Equip(f.player, futureSelection(1, "repair"))
			expect(repaired.ok).toBe(true)
			expect(repaired.values).toEqual({
				instanceId = "future",
				definitionId = "future_two_hand",
				slot = "PrimaryWeapon",
				changed = true,
				shieldUnequipped = true,
			})
			local same = f.api.Equip(f.player, futureSelection(2, "same-two-hand"))
			expect(same.values).toEqual({
				instanceId = "future",
				definitionId = "future_two_hand",
				slot = "PrimaryWeapon",
				changed = false,
				shieldUnequipped = false,
			})
		end
	)

	it(
		"rejects stale owned identity and unsupported metadata without using display names or fallback items",
		function()
			local cases: { { code: string, mutate: (any, any) -> () } } = {
				{
					code = "NotOwned",
					mutate = function(data, _request)
						data.equipment.selected = nil
					end,
				},
				{
					code = "EquipmentChanged",
					mutate = function(_data, request)
						request.expectedDefinitionId = "elemental_shield"
					end,
				},
				{
					code = "EquipmentChanged",
					mutate = function(_data, request)
						request.expectedFinishId = "dark"
					end,
				},
				{
					code = "EquipmentChanged",
					mutate = function(_data, request)
						request.expectedFinishId = nil
					end,
				},
				{
					code = "NotEquippable",
					mutate = function(data, request)
						data.equipment.selected.definitionId = "legacy_weapon"
						request.expectedDefinitionId = "legacy_weapon"
					end,
				},
				{
					code = "NotEquippable",
					mutate = function(data, request)
						data.equipment.selected.finishId = "Vulcan Sword"
						request.expectedFinishId = "Vulcan Sword"
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				local request = equip(0, "selection")
				case.mutate(f.data, request)
				local before = gameplay(f.data)
				expect(f.api.Equip(f.player, request).code).toBe(case.code)
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"requires an exact nonempty slot selection and permits recovery of dangling or unsupported references",
		function()
			for _, instanceId in { "missing", "legacy" } do
				local f = fixture()
				f.data.equipment.legacy = { definitionId = "legacy_weapon" }
				f.data.combatLoadout.primaryWeaponInstanceId = instanceId
				local before = gameplay(f.data)
				expect(f.api.Equip(f.player, shieldSelection(0, "cannot-resolve")).code).toBe(
					"InvalidLoadoutState"
				)
				expect(f.api.Unequip(f.player, unequip(1, "stale")).code).toBe("SlotChanged")
				expect(gameplay(f.data)).toEqual(before)
				local request = unequip(2, "recover")
				request.expectedInstanceId = instanceId
				expect(f.api.Unequip(f.player, request).ok).toBe(true)
				before.combatLoadout.primaryWeaponInstanceId = nil
				expect(gameplay(f.data)).toEqual(before)
				expect(f.api.Unequip(f.player, unequip(3, "already-empty")).code).toBe(
					"SlotChanged"
				)
			end
		end
	)

	it(
		"unequips exactly one selected slot while retaining opaque ownership and loadout fields",
		function()
			for _, slot in { "PrimaryWeapon", "Shield" } do
				local f = fixture()
				local field = if slot == "PrimaryWeapon"
					then "primaryWeaponInstanceId"
					else "shieldInstanceId"
				local loadout: any = f.data.combatLoadout
				loadout[field] = "legacy"
				loadout.retainedFutureField = { value = "keep" }
				local equipment: any = f.data.equipment
				equipment.legacy = { retained = "opaque" }
				for index = 1, 40 do
					f.data.equipment[`retained_{index}`] = { definitionId = "legacy_weapon" }
				end
				local before = gameplay(f.data)
				local request = unequip(0, "one-slot")
				request.slot = slot
				request.expectedInstanceId = "legacy"
				expect(f.api.Unequip(f.player, request)).toEqual({
					ok = true,
					revision = 1,
					values = { instanceId = "legacy", slot = slot, changed = true },
				})
				local expectedLoadout: any = before.combatLoadout
				expectedLoadout[field] = nil
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"requires the requesting player's loaded active profile before admitting either command",
		function()
			for _, equipping in { false, true } do
				for _, unavailable in { "unloaded", "ended", "other-player" } do
					local f = fixture()
					local player = f.player
					if unavailable == "unloaded" then
						f.state.available = false
					elseif unavailable == "ended" then
						f.state.active = false
					else
						player = (table.freeze({ UserId = 1002 }) :: unknown) :: Player
					end
					local before = copy(f.data)
					local result = if equipping
						then f.api.Equip(player, equip(0, "unavailable"))
						else f.api.Unequip(player, unequip(0, "unavailable"))
					expect(result.code).toBe("DataUnavailable")
					expect(f.state.transactionCalls).toBe(0)
					expect(f.data).toEqual(before)
				end
			end
		end
	)

	it(
		"rejects forged, missing, malformed and unsafe request fields without a transaction",
		function()
			for _, equipping in { false, true } do
				local make = if equipping then equip else unequip
				local payloads: { any } = { false, "loadout", setmetatable(make(0, "meta"), {}) }
				local fields = if equipping
					then { "requestId", "expectedRevision", "instanceId", "expectedDefinitionId" }
					else { "requestId", "expectedRevision", "slot", "expectedInstanceId" }
				for _, field in fields do
					local request = make(0, "missing")
					request[field] = nil
					table.insert(payloads, request)
				end
				local ids = if equipping
					then { "requestId", "instanceId", "expectedDefinitionId", "expectedFinishId" }
					else { "requestId", "expectedInstanceId" }
				for _, field in ids do
					for _, value in { "", string.rep("x", 129), false, 25, {} } do
						local request = make(0, "bad-id")
						request[field] = value
						table.insert(payloads, request)
					end
				end
				for _, value in { -1, 0.5, 2 ^ 53, math.huge, 0 / 0, "0", false } do
					local request = make(0, "revision")
					request.expectedRevision = value
					table.insert(payloads, request)
				end
				local forged = make(0, "forged")
				forged.playerId = 1002
				table.insert(payloads, forged)
				if not equipping then
					for _, slot in { "primaryWeapon", "sword", "", 1, false } do
						local request = make(0, "slot")
						request.slot = slot
						table.insert(payloads, request)
					end
				end
				for _, request in payloads do
					local f = fixture()
					local before = copy(f.data)
					local result = if equipping
						then f.api.Equip(f.player, request)
						else f.api.Unequip(f.player, request)
					expect(result.code).toBe("InvalidRequest")
					expect(f.state.transactionCalls).toBe(0)
					expect(f.data).toEqual(before)
				end
			end
		end
	)

	it("fails closed for malformed common saved state without repairing unrelated data", function()
		local cases: { { code: string, mutate: (any) -> () } } = {
			{
				code = "UnsupportedVersion",
				mutate = function(data)
					data.version = PlayerData.schemaVersion + 1
				end,
			},
			{
				code = "InvalidInventoryState",
				mutate = function(data)
					data.equipment = false
				end,
			},
			{
				code = "InvalidLoadoutState",
				mutate = function(data)
					data.combatLoadout = nil
				end,
			},
			{
				code = "InvalidLoadoutState",
				mutate = function(data)
					data.combatLoadout = false
				end,
			},
		}
		for _, slot in { "primaryWeaponInstanceId", "shieldInstanceId" } do
			for _, value in { "", string.rep("x", 129), 1, false, {} } do
				table.insert(cases, {
					code = "InvalidLoadoutState",
					mutate = function(data: any)
						data.combatLoadout[slot] = value
					end,
				})
			end
		end
		for _, equipping in { false, true } do
			for _, case in cases do
				local f = fixture()
				case.mutate(f.data)
				local before = gameplay(f.data)
				local result = if equipping
					then f.api.Equip(f.player, equip(0, "bad-state"))
					else f.api.Unequip(f.player, unequip(0, "bad-state"))
				expect(result.code).toBe(case.code)
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	end)

	it(
		"rejects malformed selected equipment and incompatible primary metadata on Shield equip",
		function()
			local cases: { { code: string, shield: boolean, mutate: (any) -> () } } = {
				{
					code = "InvalidInventoryState",
					shield = false,
					mutate = function(data)
						data.equipment.selected = false
					end,
				},
				{
					code = "InvalidInventoryState",
					shield = false,
					mutate = function(data)
						data.equipment.selected.definitionId = ""
					end,
				},
				{
					code = "InvalidInventoryState",
					shield = false,
					mutate = function(data)
						data.equipment.selected.finishId = false
					end,
				},
				{
					code = "InvalidLoadoutState",
					shield = true,
					mutate = function(data)
						data.equipment.starter_wooden_sword = false
					end,
				},
				{
					code = "InvalidLoadoutState",
					shield = true,
					mutate = function(data)
						data.combatLoadout.primaryWeaponInstanceId = "shield"
					end,
				},
			}
			for _, case in cases do
				local f = fixture()
				case.mutate(f.data)
				local before = gameplay(f.data)
				local request = if case.shield
					then shieldSelection(0, "bad-primary")
					else equip(0, "bad-owned")
				expect(f.api.Equip(f.player, request).code).toBe(case.code)
				expect(gameplay(f.data)).toEqual(before)
			end
		end
	)

	it(
		"rolls back either slot mutation and its receipt when the session ends after the callback",
		function()
			for _, equipping in { false, true } do
				local f = fixture()
				f.state.loseSessionAfterCallback = true
				local before = copy(f.data)
				local result = if equipping
					then f.api.Equip(f.player, equip(0, "session-loss"))
					else f.api.Unequip(f.player, unequip(0, "session-loss"))
				expect(result.code).toBe("DataUnavailable")
				expect(f.state.callbackCalls).toBe(1)
				expect(f.data).toEqual(before)
			end
		end
	)

	it(
		"replays original outcomes after later slot changes without toggling or restoring either item",
		function()
			local f = fixture()
			local first = equip(0, "first")
			local equipped = f.api.Equip(f.player, first)
			local second = unequip(1, "second")
			second.expectedInstanceId = "selected"
			local unequipped = f.api.Unequip(f.player, second)
			expect(equipped.ok).toBe(true)
			expect(unequipped.ok).toBe(true)
			expect(f.api.Equip(f.player, equip(2, "again")).ok).toBe(true)
			local after = copy(f.data)
			expect(f.api.Equip(f.player, first)).toEqual({
				ok = true,
				revision = 1,
				values = equipped.values,
				replayed = true,
			})
			expect(f.api.Unequip(f.player, second)).toEqual({
				ok = true,
				revision = 2,
				values = unequipped.values,
				replayed = true,
			})
			expect(f.state.callbackCalls).toBe(3)
			expect(f.data).toEqual(after)
		end
	)

	it(
		"binds the operation and complete selection identity in retained request receipts",
		function()
			local f = fixture()
			expect(f.api.Equip(f.player, equip(0, "binding")).ok).toBe(true)
			local changes: { [string]: string } = {
				instanceId = "shield",
				expectedDefinitionId = "elemental_shield",
				expectedFinishId = "water",
			}
			for field, value in changes do
				local request = equip(0, "binding")
				request[field] = value
				expect(f.api.Equip(f.player, request).code).toBe("RequestConflict")
			end
			local noFinish = equip(0, "binding")
			noFinish.expectedFinishId = nil
			expect(f.api.Equip(f.player, noFinish).code).toBe("RequestConflict")
			expect(f.api.Unequip(f.player, unequip(0, "binding")).code).toBe("RequestConflict")
			local second = unequip(1, "clear")
			second.expectedInstanceId = "selected"
			expect(f.api.Unequip(f.player, second).ok).toBe(true)
			local after = copy(f.data)
			second.slot = "Shield"
			expect(f.api.Unequip(f.player, second).code).toBe("RequestConflict")
			second.slot = "PrimaryWeapon"
			second.expectedInstanceId = "starter_wooden_sword"
			expect(f.api.Unequip(f.player, second).code).toBe("RequestConflict")
			expect(f.state.callbackCalls).toBe(2)
			expect(f.data).toEqual(after)
		end
	)

	it(
		"retains successful and rejected decisions through reconnect and rejects stale replacement selections",
		function()
			local f = fixture()
			local request = equip(0, "persisted")
			local result = f.api.Equip(f.player, request)
			expect(result.ok).toBe(true)
			local rejected = unequip(1, "wrong-slot")
			expect(f.api.Unequip(f.player, rejected).code).toBe("SlotChanged")
			local restored = fixture(copy(f.data))
			restored.data.equipment.selected.finishId = "dark"
			local before = gameplay(restored.data)
			expect(restored.api.Equip(restored.player, request)).toEqual({
				ok = true,
				revision = 1,
				values = result.values,
				replayed = true,
			})
			expect(restored.api.Unequip(restored.player, rejected)).toEqual({
				ok = false,
				code = "SlotChanged",
				revision = 2,
				replayed = true,
			})
			expect(restored.api.Equip(restored.player, equip(0, "stale-revision")).code).toBe(
				"StaleRevision"
			)
			expect(restored.api.Equip(restored.player, equip(2, "stale-finish")).code).toBe(
				"EquipmentChanged"
			)
			expect(restored.state.callbackCalls).toBe(1)
			expect(gameplay(restored.data)).toEqual(before)
		end
	)
end)
