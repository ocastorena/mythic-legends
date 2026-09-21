--!strict
-- ServerStorage/Tests/__tests__/Accrual.spec

local HttpService = game:GetService("HttpService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Accrual = require(game:GetService("ServerScriptService").Services.ProductionService.Accrual)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local definitions = {
	dragon = { production = { materialId = "crystal", baseRate = 1, baseCapacity = 3 } },
	satyr = { production = { materialId = "shadow_dust", baseRate = 2, baseCapacity = 4 } },
}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in pairs(value) do
		result[key] = copy(child)
	end
	return result
end

local function fixture(saved: any?): any
	local context: any = {
		player = {},
		now = 100,
		loaded = true,
		snapshots = {},
		data = saved or {
			base = {
				stands = {
					["0"] = { production = { lastAccruedAt = 100, materials = {} } },
				},
			},
			mythlings = { worker = { typeId = "dragon", standId = 0 } },
			materials = {},
		},
	}
	local dataService = {
		GetLoadedSection = function(_player: Player, section: string): any
			return if context.loaded then context.data[section] else nil
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
	it("keeps output collectible at the original stand after its worker is removed and deleted", function()
		local f = fixture()
		f.now = 190
		expect(f.api.Settle(f.player, 0)).toBe(true)
		f.data.mythlings.worker.standId = nil
		f.data.mythlings.worker = nil

		f.now = 790
		local status = f.api.Get(f.player, 0)
		expect(status.active).toBe(false)
		expect(status.production).toBe(1)
		expect(status.materials.crystal.progress).toBeCloseTo(0.5)
		local collected, code, result = f.api.Collect(f.player, 0)
		expect(collected).toBe(true)
		expect(code).toBeNil()
		expect(result).toEqual({ collected = 1, remaining = 0, materials = { crystal = 1 } })
		expect(f.data.materials.crystal.total).toBe(1)
		local ledger = f.data.base.stands["0"].production
		expect(ledger.lastAccruedAt).toBe(790)
		expect(ledger.materials.crystal).toEqual({ stored = 0, progress = 0.5 })
		f.now = 1_390
		expect(f.api.Get(f.player, 0).production).toBe(0)
	end)

	it("leaves unfinished work behind when a worker moves to another stand", function()
		local f = fixture()
		f.now = 130
		expect(f.api.Settle(f.player, 0)).toBe(true)
		f.data.mythlings.worker.standId = nil
		expect(f.api.Settle(f.player, 1)).toBe(true)
		f.data.mythlings.worker.standId = 1

		f.now = 160
		local original = f.api.Get(f.player, 0)
		local destination = f.api.Get(f.player, 1)
		expect(original.active).toBe(false)
		expect(original.materials.crystal).toEqual({ stored = 0, progress = 0.5 })
		expect(destination.active).toBe(true)
		expect(destination.materials.crystal).toEqual({ stored = 0, progress = 0.5 })
		expect(f.data.mythlings.worker.progress).toBeNil()
	end)

	it("resumes retained fractions without crediting time the stand had no worker", function()
		local f = fixture()
		f.now = 130
		expect(f.api.Settle(f.player, 0)).toBe(true)
		f.data.mythlings.worker.standId = nil
		f.now = 730
		expect(f.api.Settle(f.player, 0)).toBe(true)
		f.data.mythlings.worker.standId = 0
		f.now = 760
		local status = f.api.Get(f.player, 0)
		expect(status.production).toBe(1)
		expect(status.progress).toBeCloseTo(0)
		expect(f.api.Collect(f.player, 0)).toBe(true)
		expect(f.data.materials.crystal.total).toBe(1)
	end)

	it("preserves original Material identity across different worker replacements", function()
		local f = fixture()
		f.now = 130
		expect(f.api.Settle(f.player, 0)).toBe(true)
		f.data.mythlings.worker.standId = nil
		f.data.mythlings.second = { typeId = "satyr", standId = 0 }
		f.now = 190
		expect(f.api.Settle(f.player, 0)).toBe(true)
		expect(f.data.base.stands["0"].production.materials.crystal.progress).toBeCloseTo(0.5)
		f.data.mythlings.second.standId = nil
		f.data.mythlings.worker.standId = 0
		f.now = 220
		local collected, _, result = f.api.Collect(f.player, 0)
		expect(collected).toBe(true)
		expect(result.materials).toEqual({ crystal = 1, shadow_dust = 2 })
		expect(f.data.materials).toEqual({ crystal = { total = 1 }, shadow_dust = { total = 2 } })
	end)

	it("continues serialized offline work once after reconnecting", function()
		local online = fixture()
		online.now = 190
		expect(online.api.Settle(online.player, 0)).toBe(true)
		local saved = HttpService:JSONDecode(HttpService:JSONEncode(online.data))
		local rejoined = fixture(saved)
		rejoined.now = 220
		local uninterrupted = fixture()
		uninterrupted.now = 220
		expect(rejoined.api.Get(rejoined.player, 0)).toEqual(uninterrupted.api.Get(uninterrupted.player, 0))
		expect(rejoined.api.Collect(rejoined.player, 0)).toBe(true)
		expect(rejoined.data.materials.crystal.total).toBe(2)

		local savedAgain = HttpService:JSONDecode(HttpService:JSONEncode(rejoined.data))
		local rejoinedAgain = fixture(savedAgain)
		rejoinedAgain.now = 220
		local collected, code = rejoinedAgain.api.Collect(rejoinedAgain.player, 0)
		expect(collected).toBe(false)
		expect(code).toBe("NothingToCollect")
		expect(rejoinedAgain.data.materials.crystal.total).toBe(2)
	end)

	it("publishes collection only after both inventory and storage are committed and never grants twice", function()
		local f = fixture()
		f.now = 190
		expect(f.api.Collect(f.player, 0)).toBe(true)
		expect(#f.snapshots).toBe(1)
		expect(f.snapshots[1].materials.crystal.total).toBe(1)
		expect(f.snapshots[1].base.stands["0"].production.materials.crystal.stored).toBe(0)
		expect(f.snapshots[1].base.stands["0"].production.materials.crystal.progress).toBeCloseTo(0.5)
		local beforeRepeat = copy(f.data)
		local collected, code = f.api.Collect(f.player, 0)
		expect(collected).toBe(false)
		expect(code).toBe("NothingToCollect")
		expect(f.data).toEqual(beforeRepeat)
		expect(#f.snapshots).toBe(1)

		f.now = 220
		expect(f.api.Collect(f.player, 0)).toBe(true)
		expect(f.data.materials.crystal.total).toBe(2)
	end)

	it("does not turn full-storage time into catch-up production after collection", function()
		local f = fixture()
		f.now = 700
		local collected, _, result = f.api.Collect(f.player, 0)
		expect(collected).toBe(true)
		expect(result.collected).toBe(3)
		expect(f.data.base.stands["0"].production.lastAccruedAt).toBe(700)
		f.now = 730
		local status = f.api.Get(f.player, 0)
		expect(status.production).toBe(0)
		expect(status.progress).toBeCloseTo(0.5)
		f.now = 760
		expect(f.api.Collect(f.player, 0)).toBe(true)
		expect(f.data.materials.crystal.total).toBe(4)
	end)

	it("returns independent status previews without changing saved state or publishing", function()
		local f = fixture()
		f.now = 190
		local before = copy(f.data)
		local status = f.api.Get(f.player, 0)
		expect(status.production).toBe(1)
		status.materials.crystal.stored = 999
		expect(f.data).toEqual(before)
		expect(f.api.Get(f.player, 0).production).toBe(1)
		expect(#f.snapshots).toBe(0)
	end)

	it("rejects an unavailable stand or inactive profile without state changes or grants", function()
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
	end)

	it("rejects unknown definitions and duplicate assignment without inventing output", function()
		local f = fixture()
		f.now = 190
		f.data.mythlings.second = { typeId = "satyr", standId = 0 }
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
