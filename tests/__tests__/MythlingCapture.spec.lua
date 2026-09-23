--!strict
-- ServerStorage/Tests/__tests__/MythlingCapture.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Domain.Types)
local Mythlings = require(ServerScriptService.Services.InventoryService.Mythlings)
local Capacity = require(ServerScriptService.Services.InventoryService.Capacity)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function fixture(count: number, upgradeLevel: number?)
	-- The module uses Player only as a UserId token for these injected callbacks.
	local player = (table.freeze({ UserId = 6142 }) :: unknown) :: Player
	local owned: ServerTypes.Mythlings = {}
	for index = 1, count do
		owned[`existing_{index}`] = {
			typeId = "retained_form",
			variantId = "regular",
			claimedAt = 100,
			level = 40,
			xp = 275,
			standId = if index <= 18 then math.ceil(index / 3) else nil,
		}
	end
	local data: Types.PlayerDoc = {
		version = 3,
		profile = { userId = player.UserId, createdAt = 0, lastLoginAt = 0 },
		currency = { gold = 0 },
		consumables = {},
		equipment = {},
		combatLoadout = {},
		base = { stands = {} },
		mythlings = owned,
		materials = {},
		inventoryUpgrades = if upgradeLevel then { mythlings = upgradeLevel } else nil,
	}
	local state = {
		player = player,
		data = data,
		isLoaded = true,
		canMarkDirty = true,
		dirtyCalls = 0,
		saveCalls = 0,
	}
	local dataService: ServerTypes.DataApi = {
		Load = function(_player)
			return state.isLoaded
		end,
		Release = function(_player) end,
		GetData = function(_player)
			return state.data
		end,
		GetLoadedData = function(_player)
			return if state.isLoaded then state.data else nil
		end,
		MarkDirty = function(_player)
			state.dirtyCalls += 1
			return state.canMarkDirty
		end,
		SaveNow = function(_player)
			state.saveCalls += 1
			return true
		end,
	}
	-- Init reads only DataService; no live service, profile, or remote is involved.
	local context = ({ Services = { DataService = dataService } } :: unknown) :: ServerTypes.Context
	local sessions: ServerTypes.InventorySessions = { [player.UserId] = { mythlings = owned } }
	Mythlings.Init(context, sessions)
	return state
end

local function snapshot(owned: ServerTypes.Mythlings): ServerTypes.Mythlings
	local copy: ServerTypes.Mythlings = {}
	for id, entry in owned do
		copy[id] = table.clone(entry)
	end
	return copy
end

local function capture(player: Player): string?
	return Mythlings.SaveWon(player, { typeId = "caught_form", variantId = "regular" })
end

describe("Mythling capture inventory", function()
	it(
		"counts assigned workers toward the starting 24 slots and rejects a full inventory",
		function()
			local f = fixture(24)
			local before = snapshot(f.data.mythlings)
			local assigned = 0
			for _, entry in f.data.mythlings do
				if entry.standId then
					assigned += 1
				end
			end
			expect(assigned).toBe(18)
			expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 24, limit = 24 })
			expect(capture(f.player)).toBeNil()
			expect(f.data.mythlings).toEqual(before)
			expect(f.dirtyCalls).toBe(0)
			expect(f.saveCalls).toBe(0)
		end
	)

	it(
		"derives 36 and 48 slots from purchased upgrades without changing existing ownership",
		function()
			local f = fixture(24)
			local before = snapshot(f.data.mythlings)
			expect(Capacity.GetMythlingLimit(nil)).toBe(24)
			expect(Capacity.GetMythlingLimit(1)).toBe(36)
			expect(Capacity.GetMythlingLimit(2)).toBe(48)

			f.data.inventoryUpgrades = { mythlings = 1 }
			expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 24, limit = 36 })
			f.data.inventoryUpgrades = { mythlings = 2 }
			expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 24, limit = 48 })
			expect(f.data.mythlings).toEqual(before)
			expect(capture(f.player)).never.toBeNil()
			expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 25, limit = 48 })
		end
	)

	it("retains every existing record when a saved inventory exceeds its current limit", function()
		local f = fixture(49, 2)
		local before = snapshot(f.data.mythlings)
		expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 49, limit = 48 })
		expect(capture(f.player)).toBeNil()
		expect(f.data.mythlings).toEqual(before)
		expect(f.dirtyCalls).toBe(0)
		expect(f.saveCalls).toBe(0)
	end)

	it("grants the caught form at level 1 and zero XP without rewriting legacy records", function()
		local f = fixture(1)
		local legacy = table.freeze({
			typeId = "legacy_form",
			variantId = "legacy_variant",
			claimedAt = 50,
			lastCollectionAt = 90,
			luck = 17,
			traitId = "lucky",
		})
		-- Old saves retain opaque Luck/Trait fields outside the new-grant record shape.
		f.data.mythlings.legacy = (legacy :: unknown) :: Types.MythlingEntry
		local before = snapshot(f.data.mythlings)
		for _, typeId in { "common_form", "rare_form", "epic_form" } do
			local id =
				Mythlings.SaveWon(f.player, { typeId = typeId, variantId = "caught_variant" })
			assert(id, "[MythlingCapture.spec] Expected a successful grant")
			local granted = f.data.mythlings[id]
			expect(granted.typeId).toBe(typeId)
			expect(granted.variantId).toBe("caught_variant")
			expect(granted.level).toBe(1)
			expect(granted.xp).toBe(0)
			expect(granted).never.toHaveProperty("luck")
			expect(granted).never.toHaveProperty("traitId")
		end
		for id, entry in before do
			expect(f.data.mythlings[id]).toEqual(entry)
		end
		expect(f.data.mythlings.legacy).toBe(legacy)
		expect(f.data.mythlings.legacy.level).toBeNil()
		expect(f.data.mythlings.legacy.xp).toBeNil()
		expect(f.dirtyCalls).toBe(3)
		expect(f.saveCalls).toBe(3)
	end)

	it("rejects a missing loaded profile without changing the retained session", function()
		local f = fixture(3)
		local before = snapshot(f.data.mythlings)
		f.isLoaded = false
		expect(Mythlings.GetCapacity(f.player)).toBeNil()
		expect(capture(f.player)).toBeNil()
		expect(f.data.mythlings).toEqual(before)
		expect(f.dirtyCalls).toBe(0)
		expect(f.saveCalls).toBe(0)
	end)

	it(
		"rejects a stale session whose owned table no longer belongs to the loaded profile",
		function()
			local f = fixture(3)
			local staleOwned = f.data.mythlings
			local before = snapshot(staleOwned)
			f.data.mythlings = {}
			expect(Mythlings.GetCapacity(f.player)).toBeNil()
			expect(capture(f.player)).toBeNil()
			expect(staleOwned).toEqual(before)
			expect(f.data.mythlings).toEqual({})
			expect(f.dirtyCalls).toBe(0)
			expect(f.saveCalls).toBe(0)
		end
	)

	it("rolls back only the new grant if marking the profile dirty fails", function()
		local f = fixture(23)
		local before = snapshot(f.data.mythlings)
		f.canMarkDirty = false
		expect(capture(f.player)).toBeNil()
		expect(f.data.mythlings).toEqual(before)
		expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 23, limit = 24 })
		expect(f.dirtyCalls).toBe(1)
		expect(f.saveCalls).toBe(0)
	end)

	it("grants exactly one of two sequential attempts for the final slot", function()
		local f = fixture(23)
		local first = capture(f.player)
		local second = capture(f.player)
		assert(first, "[MythlingCapture.spec] Expected the final available slot")
		expect(second).toBeNil()
		expect(f.data.mythlings[first].typeId).toBe("caught_form")
		expect(Mythlings.GetCapacity(f.player)).toEqual({ used = 24, limit = 24 })
		expect(f.dirtyCalls).toBe(1)
		expect(f.saveCalls).toBe(1)
	end)
end)
