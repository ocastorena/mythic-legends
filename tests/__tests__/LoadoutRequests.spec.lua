--!strict
-- ServerStorage/Tests/__tests__/LoadoutRequests.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local LoadoutRequests =
	require(game:GetService("ServerScriptService").Services.CombatService.LoadoutRequests)
local PlayerDataTemplate = require(game:GetService("ServerStorage").Databases.PlayerDataTemplate)

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
		resolveLoadout = function(_player)
			state.resolutions += 1
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
		now = function()
			return state.now
		end,
	})
	return { player = player, state = state, api = api }
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
		expect(f.state.resolutions).toBe(1)
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
end)
