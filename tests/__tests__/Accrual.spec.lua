--!strict
-- ServerStorage/Tests/__tests__/Accrual.spec

local HttpService = game:GetService("HttpService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Accrual = require(game:GetService("ServerScriptService").Services.ProductionService.Accrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local function definition(materialId: string, rate: number, capacity: number): Types.MythlingDef
	return {
		displayName = "Fixture",
		rarity = "Common",
		sizeClass = "Small",
		zoneRadius = 10,
		fillRate = 1,
		drainRate = 1,
		description = "Fixture",
		variants = { regular = { model = "Fixture", thumbnail = "" } },
		production = { materialId = materialId, materialsPerMinute = rate, baseCapacity = capacity },
	}
end
local definitions: Accrual.Definitions = {
	dragon = definition("crystal", 1, 3),
	satyr = definition("shadow_dust", 2, 4),
}

local function copy(value: Types.PlayerDoc): Types.PlayerDoc
	-- This boundary intentionally exercises the same JSON serialization as a persisted save.
	return HttpService:JSONDecode(HttpService:JSONEncode(value))
end

local function fixture(saved: Types.PlayerDoc?)
	-- Accrual forwards Player only as an opaque identity to these injected callbacks.
	-- Adapt a test-only token at that boundary; no Roblox Player or live state is needed.
	local player = (table.freeze({}) :: unknown) :: Player
	local data: Types.PlayerDoc = saved
		or {
			version = 3,
			profile = { userId = 0, createdAt = 0, lastLoginAt = 0 },
			currency = { gold = 0 },
			consumables = {},
			equipment = {},
			combatLoadout = {},
			base = { stands = { ["0"] = { production = { lastAccruedAt = 100, materials = {} } } } },
			mythlings = {
				worker = { typeId = "dragon", variantId = "regular", claimedAt = 100, standId = 0 },
			},
			materials = {},
		}
	local context = {
		player = player,
		now = 100,
		loaded = true,
		snapshots = {} :: { Types.PlayerDoc },
		data = data,
	}
	local dataService: Accrual.DataSource = {
		GetLoadedData = function(_player: Player): Types.PlayerDoc?
			return if context.loaded then context.data else nil
		end,
		MarkDirty = function(_player: Player): boolean
			table.insert(context.snapshots, copy(context.data))
			return context.loaded
		end,
	}
	context.api = Accrual.new(dataService, definitions, function(_player: Player, standId: number)
		return standId == 0 or standId == 1
	end, function()
		return context.now
	end)
	return context
end
describe("Accrual", function()
	it(
		"keeps output collectible at the original stand after its worker is removed and deleted",
		function()
			local f = fixture()
			f.now = 190
			expect((f.api.Settle(f.player, 0))).toBe(true)
			f.data.mythlings.worker.standId = nil
			f.data.mythlings.worker = nil

			f.now = 790
			local status = f.api.Get(f.player, 0)
			assert(status, "[Accrual.spec] Expected production status")
			expect(status.active).toBe(false)
			expect(status.production).toBe(1)
			expect(status.materials.crystal.progress).toBeCloseTo(0.5)
			local collected, code, result = f.api.Collect(f.player, 0)
			expect(collected).toBe(true)
			expect(code).toBeNil()
			expect(result).toEqual({ collected = 1, remaining = 0, materials = { crystal = 1 } })
			expect(f.data.materials.crystal.total).toBe(1)
			local ledger = assert(
				f.data.base.stands["0"].production,
				"[Accrual.spec] Expected production ledger"
			)
			expect(ledger.lastAccruedAt).toBe(790)
			expect(ledger.materials.crystal).toEqual({ stored = 0, progress = 0.5 })
			f.now = 1_390
			expect(
				assert(f.api.Get(f.player, 0), "[Accrual.spec] Expected production status").production
			).toBe(0)
		end
	)

	it("leaves unfinished work behind when a worker moves to another stand", function()
		local f = fixture()
		f.now = 130
		expect((f.api.Settle(f.player, 0))).toBe(true)
		f.data.mythlings.worker.standId = nil
		expect((f.api.Settle(f.player, 1))).toBe(true)
		f.data.mythlings.worker.standId = 1

		f.now = 160
		local original = f.api.Get(f.player, 0)
		assert(original, "[Accrual.spec] Expected original stand")
		local destination = f.api.Get(f.player, 1)
		assert(destination, "[Accrual.spec] Expected destination stand")
		expect(original.active).toBe(false)
		expect(original.materials.crystal).toEqual({ stored = 0, progress = 0.5 })
		expect(destination.active).toBe(true)
		expect(destination.materials.crystal).toEqual({ stored = 0, progress = 0.5 })
		expect((f.data.mythlings.worker :: unknown) :: { [string]: unknown }).never.toHaveProperty(
			"progress"
		)
	end)

	it("resumes retained fractions without crediting time the stand had no worker", function()
		local f = fixture()
		f.now = 130
		expect((f.api.Settle(f.player, 0))).toBe(true)
		f.data.mythlings.worker.standId = nil
		f.now = 730
		expect((f.api.Settle(f.player, 0))).toBe(true)
		f.data.mythlings.worker.standId = 0
		f.now = 760
		local status = f.api.Get(f.player, 0)
		assert(status, "[Accrual.spec] Expected production status")
		expect(status.production).toBe(1)
		expect(status.progress).toBeCloseTo(0)
		expect((f.api.Collect(f.player, 0))).toBe(true)
		expect(f.data.materials.crystal.total).toBe(1)
	end)

	it("preserves original Material identity across different worker replacements", function()
		local f = fixture()
		f.now = 130
		expect((f.api.Settle(f.player, 0))).toBe(true)
		f.data.mythlings.worker.standId = nil
		f.data.mythlings.second =
			{ typeId = "satyr", variantId = "regular", claimedAt = 100, standId = 0 }
		f.now = 190
		expect((f.api.Settle(f.player, 0))).toBe(true)
		expect(
			assert(f.data.base.stands["0"].production, "[Accrual.spec] Expected production ledger").materials.crystal.progress
		).toBeCloseTo(0.5)
		f.data.mythlings.second.standId = nil
		f.data.mythlings.worker.standId = 0
		f.now = 220
		local collected, _, result = f.api.Collect(f.player, 0)
		expect(collected).toBe(true)
		expect(assert(result, "[Accrual.spec] Expected collection result").materials).toEqual({
			crystal = 1,
			shadow_dust = 2,
		})
		expect(f.data.materials).toEqual({ crystal = { total = 1 }, shadow_dust = { total = 2 } })
	end)

	it("continues serialized offline work once after reconnecting", function()
		local online = fixture()
		online.now = 190
		expect((online.api.Settle(online.player, 0))).toBe(true)
		local saved = HttpService:JSONDecode(HttpService:JSONEncode(online.data))
		local rejoined = fixture(saved)
		rejoined.now = 220
		local uninterrupted = fixture()
		uninterrupted.now = 220
		expect(rejoined.api.Get(rejoined.player, 0)).toEqual(
			uninterrupted.api.Get(uninterrupted.player, 0)
		)
		expect((rejoined.api.Collect(rejoined.player, 0))).toBe(true)
		expect(rejoined.data.materials.crystal.total).toBe(2)

		local savedAgain = HttpService:JSONDecode(HttpService:JSONEncode(rejoined.data))
		local rejoinedAgain = fixture(savedAgain)
		rejoinedAgain.now = 220
		local collected, code = rejoinedAgain.api.Collect(rejoinedAgain.player, 0)
		expect(collected).toBe(false)
		expect(code).toBe("NothingToCollect")
		expect(rejoinedAgain.data.materials.crystal.total).toBe(2)
	end)

	it(
		"publishes collection only after both inventory and storage are committed and never grants twice",
		function()
			local f = fixture()
			f.now = 190
			expect((f.api.Collect(f.player, 0))).toBe(true)
			expect(#f.snapshots).toBe(1)
			expect(f.snapshots[1].materials.crystal.total).toBe(1)
			expect(
				assert(
					f.snapshots[1].base.stands["0"].production,
					"[Accrual.spec] Expected production ledger"
				).materials.crystal.stored
			).toBe(0)
			expect(
				assert(
					f.snapshots[1].base.stands["0"].production,
					"[Accrual.spec] Expected production ledger"
				).materials.crystal.progress
			).toBeCloseTo(0.5)
			local beforeRepeat = copy(f.data)
			local collected, code = f.api.Collect(f.player, 0)
			expect(collected).toBe(false)
			expect(code).toBe("NothingToCollect")
			expect(f.data).toEqual(beforeRepeat)
			expect(#f.snapshots).toBe(1)

			f.now = 220
			expect((f.api.Collect(f.player, 0))).toBe(true)
			expect(f.data.materials.crystal.total).toBe(2)
		end
	)

	it("does not turn full-storage time into catch-up production after collection", function()
		local f = fixture()
		f.now = 700
		local collected, _, result = f.api.Collect(f.player, 0)
		expect(collected).toBe(true)
		expect(assert(result, "[Accrual.spec] Expected collection result").collected).toBe(3)
		expect(
			assert(f.data.base.stands["0"].production, "[Accrual.spec] Expected production ledger").lastAccruedAt
		).toBe(700)
		f.now = 730
		local status = f.api.Get(f.player, 0)
		assert(status, "[Accrual.spec] Expected production status")
		expect(status.production).toBe(0)
		expect(status.progress).toBeCloseTo(0.5)
		f.now = 760
		expect((f.api.Collect(f.player, 0))).toBe(true)
		expect(f.data.materials.crystal.total).toBe(4)
	end)

	it("returns independent status previews without changing saved state or publishing", function()
		local f = fixture()
		f.now = 190
		local before = copy(f.data)
		local status = f.api.Get(f.player, 0)
		assert(status, "[Accrual.spec] Expected production status")
		expect(status.production).toBe(1)
		status.materials.crystal.stored = 999
		expect(f.data).toEqual(before)
		expect(
			assert(f.api.Get(f.player, 0), "[Accrual.spec] Expected production status").production
		).toBe(1)
		expect(#f.snapshots).toBe(0)
	end)

	it(
		"rejects an unavailable stand or inactive profile without state changes or grants",
		function()
			local f = fixture()
			f.now = 190
			local before = copy(f.data)
			expect(f.api.Get(f.player, 99)).toBeNil()
			local settled, settleCode = f.api.Settle(f.player, 99)
			local collected, collectCode = f.api.Collect(f.player, 99)
			expect(settled).toBe(false)
			expect(settleCode).toBe("StandUnavailable")
			expect(collected).toBe(false)
			expect(collectCode).toBe("StandUnavailable")

			f.loaded = false
			expect(f.api.Get(f.player, 0)).toBeNil()
			settled, settleCode = f.api.Settle(f.player, 0)
			collected, collectCode = f.api.Collect(f.player, 0)
			expect(settled).toBe(false)
			expect(settleCode).toBe("DataUnavailable")
			expect(collected).toBe(false)
			expect(collectCode).toBe("DataUnavailable")
			expect(f.data).toEqual(before)
			expect(#f.snapshots).toBe(0)
		end
	)

	it("rejects unknown definitions and duplicate assignment without inventing output", function()
		local f = fixture()
		f.now = 190
		f.data.mythlings.second =
			{ typeId = "satyr", variantId = "regular", claimedAt = 100, standId = 0 }
		local before = copy(f.data)
		local collected, code = f.api.Collect(f.player, 0)
		expect(collected).toBe(false)
		expect(code).toBe("ConflictingAssignment")
		expect(f.data).toEqual(before)

		f.data.mythlings.second = nil
		f.data.mythlings.worker.typeId = "unknown"
		before = copy(f.data)
		collected, code = f.api.Collect(f.player, 0)
		expect(collected).toBe(false)
		expect(code).toBe("InvalidDefinition")
		expect(f.data).toEqual(before)
		expect(#f.snapshots).toBe(0)
	end)
end)
