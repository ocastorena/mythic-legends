--!strict
-- ServerStorage/Tests/__tests__/Migrations.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Migrations = require(game:GetService("ServerScriptService").Services.DataService.Migrations)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local definitions = {
	dragon = {
		production = { materialId = "crystal", materialsPerMinute = 0.7, baseCapacity = 300 },
	},
	satyr = {
		production = { materialId = "shadow_dust", materialsPerMinute = 0.85, baseCapacity = 340 },
	},
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

local function profile(): any
	return {
		version = 2,
		currency = { gold = 135 },
		materials = { crystal = { total = 17 } },
		equipment = { sword = { definitionId = "wooden_sword" } },
		consumables = { legacy = { total = 2 } },
		base = { unlockedSlots = 4, stands = { [0] = { customName = "Saved stand" } } },
		mythlings = {
			worker = {
				typeId = "dragon",
				variantId = "regular",
				standId = 0,
				lastCollectionAt = 100,
				level = 7,
				xp = 12.5,
				luck = 14,
				traitId = "legacy_trait",
			},
			unassigned = { typeId = "unknown_legacy_form", claimedAt = 10 },
		},
	}
end

describe("Migrations.Apply", function()
	it("moves whole output and unfinished work to the original stand exactly once", function()
		local data = profile()
		local migrated, code = Migrations.Apply(data, definitions, 220)
		expect(migrated).toBe(true)
		expect(code).toBeNil()
		expect(data.version).toBe(3)
		expect(data.base.stands[0]).toBeNil()
		local ledger = data.base.stands["0"].production
		expect(ledger.lastAccruedAt).toBe(220)
		expect(ledger.materials.crystal.stored).toBe(1)
		expect(ledger.materials.crystal.progress).toBeCloseTo(0.4)
		expect(data.mythlings.worker.lastCollectionAt).toBeNil()

		local afterFirstMigration = copy(data)
		expect((Migrations.Apply(data, definitions, 520))).toBe(true)
		expect(data).toEqual(afterFirstMigration)
	end)

	it(
		"preserves unrelated earned progression, legacy fields, inventory, and stand data",
		function()
			local data = profile()
			local original = copy(data)
			expect((Migrations.Apply(data, definitions, 220))).toBe(true)
			expect(data.currency).toEqual(original.currency)
			expect(data.materials).toEqual(original.materials)
			expect(data.equipment).toEqual(original.equipment)
			expect(data.consumables).toEqual(original.consumables)
			expect(data.base.unlockedSlots).toBe(4)
			expect(data.base.stands["0"].customName).toBe("Saved stand")
			original.mythlings.worker.lastCollectionAt = nil
			expect(data.mythlings).toEqual(original.mythlings)
		end
	)

	it("keeps each stand's original Material and caps only newly computed legacy output", function()
		local data = profile()
		data.mythlings.second = { typeId = "satyr", standId = 1, lastCollectionAt = 100 }
		expect((Migrations.Apply(data, definitions, 1_000_000))).toBe(true)
		local crystal = data.base.stands["0"].production.materials.crystal
		local dust = data.base.stands["1"].production.materials.shadow_dust
		expect(crystal.stored).toBe(300)
		expect(crystal.progress).toBe(0)
		expect(dust.stored).toBe(340)
		expect(dust.progress).toBe(0)
		expect(data.materials.crystal.total).toBe(17)
	end)

	it(
		"starts an assigned worker without a timestamp at migration time without backfill",
		function()
			local data = profile()
			data.mythlings.worker.lastCollectionAt = nil
			expect((Migrations.Apply(data, definitions, 220))).toBe(true)
			local ledger = data.base.stands["0"].production
			expect(ledger.lastAccruedAt).toBe(220)
			local bucket = ledger.materials.crystal
			expect(if bucket then bucket.stored else 0).toBe(0)
			expect(if bucket then bucket.progress else 0).toBe(0)
		end
	)

	it(
		"preserves a future legacy cursor without granting negative or repeated elapsed time",
		function()
			local data = profile()
			data.mythlings.worker.lastCollectionAt = 500
			expect((Migrations.Apply(data, definitions, 220))).toBe(true)
			local ledger = data.base.stands["0"].production
			expect(ledger.lastAccruedAt).toBe(500)
			local bucket = ledger.materials.crystal
			expect(if bucket then bucket.stored else 0).toBe(0)
			expect(if bucket then bucket.progress else 0).toBe(0)
		end
	)

	it("migrates unversioned empty profiles and leaves current profiles untouched", function()
		local data: any = { currency = { gold = 41 } }
		expect((Migrations.Apply(data, definitions, 220))).toBe(true)
		expect(data).toEqual({ version = 3, currency = { gold = 41 }, base = { stands = {} } })
		local before = copy(data)
		expect((Migrations.Apply(data, nil, 500))).toBe(true)
		expect(data).toEqual(before)
	end)

	local invalidCases = {
		{
			name = "unknown assigned metadata",
			code = "UnknownLegacyProductionDefinition",
			change = function(data: any)
				data.mythlings.second = { typeId = "missing", standId = 1, lastCollectionAt = 100 }
			end,
		},
		{
			name = "duplicate stand assignments",
			code = "DuplicateStandAssignment",
			change = function(data: any)
				data.mythlings.second = { typeId = "satyr", standId = 0, lastCollectionAt = 100 }
			end,
		},
		{
			name = "existing ambiguous production",
			code = "AmbiguousLegacyProduction",
			change = function(data: any)
				data.base.stands[0].production = { lastAccruedAt = 100, materials = {} }
			end,
		},
		{
			name = "orphan production timestamp",
			code = "OrphanLegacyProduction",
			change = function(data: any)
				data.mythlings.unassigned.lastCollectionAt = 100
			end,
		},
		{
			name = "conflicting numeric and string stand keys",
			code = "ConflictingStandKeys",
			change = function(data: any)
				data.base.stands["0"] = { customName = "Different stand" }
			end,
		},
		{
			name = "invalid legacy timestamp",
			code = "InvalidLegacyProductionTime",
			change = function(data: any)
				data.mythlings.worker.lastCollectionAt = "not a time"
			end,
		},
		{
			name = "future profile version",
			code = "UnsupportedProfileVersion",
			change = function(data: any)
				data.version = 4
			end,
		},
	}

	for _, invalid in ipairs(invalidCases) do
		it(`rejects {invalid.name} without partially changing the document`, function()
			local data = profile()
			invalid.change(data)
			local before = copy(data)
			local migrated, code = Migrations.Apply(data, definitions, 220)
			expect(migrated).toBe(false)
			expect(code).toBe(invalid.code)
			expect(data).toEqual(before)
		end)
	end
end)
