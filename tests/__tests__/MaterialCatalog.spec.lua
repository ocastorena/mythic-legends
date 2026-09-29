--!strict
-- ServerStorage/Tests/__tests__/MaterialCatalog.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local Inventory = require(ReplicatedStorage.Shared.Configurations.Inventory)
local Materials = require(ReplicatedStorage.Shared.Configurations.Materials)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local MaterialCatalogUtil = require(ServerScriptService.Shared.MaterialCatalogUtil)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "Fire", "Water", "Earth", "Air", "Light", "Dark" }
local INVALID_POSITIVE_INTEGERS: { { label: string, value: unknown } } = {
	{ label = "missing", value = nil },
	{ label = "zero", value = 0 },
	{ label = "negative", value = -1 },
	{ label = "fractional", value = 1.5 },
	{ label = "infinite", value = math.huge },
	{ label = "negative infinite", value = -math.huge },
	{ label = "NaN", value = 0 / 0 },
	{ label = "unsafe integer", value = 9_007_199_254_740_992 },
	{ label = "numeric string", value = "10" },
	{ label = "boolean", value = true },
	{ label = "table", value = {} },
}

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

-- These detached fixtures are deliberately dynamic so each test can inject malformed metadata.
local function catalogues(): ({ [any]: any }, { [any]: any })
	return copy(Materials), copy(Shrines)
end

local function expectValid(materials: unknown, shrines: unknown, stackLimit: unknown)
	local valid, diagnostic = MaterialCatalogUtil.Validate(materials, shrines, stackLimit)
	expect(valid).toBe(true)
	expect(diagnostic).toBeNil()
end

local function expectInvalid(materials: unknown, shrines: unknown, stackLimit: unknown)
	-- An invalid catalogue must also be safe to validate without rewriting its contents.
	FreezeUtil.DeepFreeze(materials)
	FreezeUtil.DeepFreeze(shrines)
	local valid, diagnostic = MaterialCatalogUtil.Validate(materials, shrines, stackLimit)
	expect(valid).toBe(false)
	expect(type(diagnostic)).toBe("string")
	expect(diagnostic == "").toBe(false)
end

describe("Material catalogue", function()
	it(
		"defines exactly one normal launch Material and matching Shrine for all six elements",
		function()
			local launchCount = 0
			local shrineCount = 0
			for _, definition in Materials do
				if definition.launchEnabled then
					launchCount += 1
				end
			end
			for _ in Shrines do
				shrineCount += 1
			end
			expect(launchCount).toBe(6)
			expect(shrineCount).toBe(6)
			expect(Inventory.materialStackLimit).toBe(1_000)
			for _, element in ELEMENTS do
				local elementId = string.lower(element)
				local materialId = `{elementId}_material`
				local definition = Materials[materialId]
				expect(definition.launchEnabled).toBe(true)
				expect(definition.category).toBe("material")
				expect(definition.element).toBe(element)
				expect(definition.stackLimit).toBe(Inventory.materialStackLimit)
				expect(definition.buyGold).toBe(10)
				expect(definition.sellGold).toBe(2)
				expect(Shrines[`{elementId}_shrine`].element).toBe(element)
				expect(Shrines[`{elementId}_shrine`].materialId).toBe(materialId)
			end
			expectValid(Materials, Shrines, Inventory.materialStackLimit)
		end
	)

	it("uses explicitly provisional display names without borrowing prototype icons", function()
		for _, element in ELEMENTS do
			local definition = Materials[`{string.lower(element)}_material`]
			expect(definition.displayName).toBe(`{element} Material`)
			expect(definition.thumbnail).toBe("")
		end
	end)

	it("freezes the real catalogue and every output definition", function()
		expect(table.isfrozen(Materials)).toBe(true)
		expect(table.isfrozen(Shrines)).toBe(true)
		for _, definition in Materials do
			expect(table.isfrozen(definition)).toBe(true)
		end
		for _, definition in Shrines do
			expect(table.isfrozen(definition)).toBe(true)
			expect(table.isfrozen(definition.levels)).toBe(true)
		end
	end)

	it(
		"retains disabled prototype definitions and their existing Mythling output identities",
		function()
			local legacy: {
				[string]: {
					displayName: string,
					guiColor: string,
					thumbnail: string,
					formId: string,
				},
			} =
				{
					essence = {
						displayName = "Essence",
						guiColor = "39C0FF",
						thumbnail = "rbxassetid://102449498933091",
						formId = "axolotl",
					},
					crystal = {
						displayName = "Crystal",
						guiColor = "9B6BFF",
						thumbnail = "rbxassetid://97907732163601",
						formId = "dragon",
					},
					shadow_dust = {
						displayName = "Shadow Dust",
						guiColor = "7A7F94",
						thumbnail = "rbxassetid://103923910263404",
						formId = "satyr",
					},
				}
			for materialId, prior in legacy do
				local definition = Materials[materialId]
				expect(definition.launchEnabled).toBe(false)
				expect(definition.displayName).toBe(prior.displayName)
				expect(definition.guiColor).toBe(prior.guiColor)
				expect(definition.thumbnail).toBe(prior.thumbnail)
				expect(definition.category).toBe("material")
				expect(definition.element).toBeNil()
				expect(definition.buyGold).toBeNil()
				expect(definition.sellGold).toBeNil()
				expect(definition.stackLimit).toBeNil()
				local production = Mythlings[prior.formId].production
				assert(production, "[MaterialCatalog.spec] Expected retained prototype production")
				expect(production.materialId).toBe(materialId)
			end
		end
	)
end)

describe("MaterialCatalogUtil.Validate", function()
	it(
		"accepts and preserves a mutable valid catalogue without freezing or rewriting it",
		function()
			local materials, shrines = catalogues()
			local materialsBefore = copy(materials)
			local shrinesBefore = copy(shrines)
			expectValid(materials, shrines, Inventory.materialStackLimit)
			expect(materials).toEqual(materialsBefore)
			expect(shrines).toEqual(shrinesBefore)
			expect(table.isfrozen(materials)).toBe(false)
			expect(table.isfrozen(materials.fire_material)).toBe(false)
			expect(table.isfrozen(shrines)).toBe(false)
			expect(table.isfrozen(shrines.fire_shrine)).toBe(false)
		end
	)

	it(
		"accepts legal future tuning without hard-coding initial prices or the stack size",
		function()
			local materials, shrines = catalogues()
			for _, definition in materials do
				if definition.launchEnabled then
					definition.buyGold = 17
					definition.sellGold = 3
					definition.stackLimit = 500
				end
			end
			expectValid(materials, shrines, 500)
		end
	)

	it("resolves valid metadata IDs without deriving them from element names", function()
		local materials, shrines = catalogues()
		materials.ember2_ore = materials.fire_material
		materials.fire_material = nil
		shrines.fire_shrine.materialId = "ember2_ore"
		shrines.ember2_shrine = shrines.fire_shrine
		shrines.fire_shrine = nil
		expectValid(materials, shrines, Inventory.materialStackLimit)
	end)

	it("ignores disabled prototype business fields without activating or rewriting them", function()
		local materials, shrines = catalogues()
		materials.essence.element = "Unreleased"
		materials.essence.category = "legacy"
		materials.essence.buyGold = -1
		materials.essence.sellGold = 100
		materials.essence.stackLimit = 0
		FreezeUtil.DeepFreeze(materials)
		FreezeUtil.DeepFreeze(shrines)
		expectValid(materials, shrines, Inventory.materialStackLimit)
		expect(materials.essence.launchEnabled).toBe(false)
		expect(materials.essence.buyGold).toBe(-1)
	end)

	for _, root in { "materials", "shrines" } do
		for _, malformed in
			{
				{ label = "missing", value = nil },
				{ label = "boolean", value = true },
				{ label = "number", value = 6 },
				{ label = "string", value = "catalogue" },
			}
		do
			it(`rejects a {malformed.label} {root} catalogue`, function()
				local materials, shrines = catalogues()
				if root == "materials" then
					expectInvalid(malformed.value, shrines, Inventory.materialStackLimit)
				else
					expectInvalid(materials, malformed.value, Inventory.materialStackLimit)
				end
			end)
		end
	end

	for _, element in ELEMENTS do
		local elementId = string.lower(element)
		it(`rejects the missing {element} launch Material or Shrine`, function()
			local materials, shrines = catalogues()
			materials[`{elementId}_material`] = nil
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
			materials, shrines = catalogues()
			shrines[`{elementId}_shrine`] = nil
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end)
	end

	it("rejects duplicate elements, even with otherwise valid metadata", function()
		local materials, shrines = catalogues()
		materials.second_fire_material = copy(materials.fire_material)
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
		materials, shrines = catalogues()
		shrines.second_fire_shrine = copy(shrines.fire_shrine)
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
	end)

	for _, invalidElement in { "Void", "fire", "", 1, false } do
		it(`rejects noncanonical element {tostring(invalidElement)} in either catalogue`, function()
			local materials, shrines = catalogues()
			materials.fire_material.element = invalidElement
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
			materials, shrines = catalogues()
			shrines.fire_shrine.element = invalidElement
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end)
	end

	it("rejects missing element fields in either catalogue", function()
		local materials, shrines = catalogues()
		materials.fire_material.element = nil
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
		materials, shrines = catalogues()
		shrines.fire_shrine.element = nil
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
	end)

	local invalidIds: { unknown } = {
		"Fire_material",
		"fire-material",
		"fire material",
		"",
		"_fire",
		"fire_",
		"fire__material",
		"2fire",
		string.rep("a", 129),
		1,
	}
	for _, rawInvalidId in invalidIds do
		local invalidId = rawInvalidId :: string | number
		it(`rejects malformed stable ID {tostring(invalidId)} in either catalogue`, function()
			local materials, shrines = catalogues()
			materials[invalidId] = materials.fire_material
			materials.fire_material = nil
			shrines.fire_shrine.materialId = invalidId
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
			materials, shrines = catalogues()
			shrines[invalidId] = shrines.fire_shrine
			shrines.fire_shrine = nil
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end)
	end

	it("rejects metatables on catalogues and metadata records", function()
		for _, location in { "materials", "shrines", "material", "shrine" } do
			local materials, shrines = catalogues()
			if location == "materials" then
				setmetatable(materials, {})
			elseif location == "shrines" then
				setmetatable(shrines, {})
			elseif location == "material" then
				setmetatable(materials.fire_material, {})
			else
				setmetatable(shrines.fire_shrine, {})
			end
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end
	end)

	for _, malformed in { false, 1, "definition" } do
		it(`rejects non-table entries of type {type(malformed)}`, function()
			local materials, shrines = catalogues()
			materials.fire_material = malformed
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
			materials, shrines = catalogues()
			shrines.fire_shrine = malformed
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end)
	end

	for _, materialId in { "fire_material", "essence" } do
		for _, flag in
			{
				{ label = "missing", value = nil },
				{ label = "string", value = "true" },
				{ label = "numeric", value = 1 },
			}
		do
			it(`requires an explicit boolean launch flag on {materialId} ({flag.label})`, function()
				local materials, shrines = catalogues()
				materials[materialId].launchEnabled = flag.value
				expectInvalid(materials, shrines, Inventory.materialStackLimit)
			end)
		end
	end

	it("rejects a disabled launch Material or an enabled incomplete legacy definition", function()
		local materials, shrines = catalogues()
		materials.fire_material.launchEnabled = false
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
		materials, shrines = catalogues()
		materials.essence.launchEnabled = true
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
	end)

	it("rejects missing or incorrect launch categories", function()
		local materials, shrines = catalogues()
		materials.fire_material.category = nil
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
		materials, shrines = catalogues()
		materials.fire_material.category = "equipment"
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
	end)

	for _, field in { "buyGold", "sellGold", "stackLimit" } do
		for _, invalid in INVALID_POSITIVE_INTEGERS do
			it(`rejects {invalid.label} launch {field}`, function()
				local materials, shrines = catalogues()
				materials.fire_material[field] = invalid.value
				expectInvalid(materials, shrines, Inventory.materialStackLimit)
			end)
		end
	end

	for _, invalid in INVALID_POSITIVE_INTEGERS do
		it(`rejects a {invalid.label} shared Inventory stack limit`, function()
			expectInvalid(Materials, Shrines, invalid.value)
		end)
	end

	it("rejects break-even and profitable Material resale prices", function()
		for _, sellGold in { 10, 11 } do
			local materials, shrines = catalogues()
			materials.fire_material.sellGold = sellGold
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end
	end)

	it("rejects a valid positive stack limit that disagrees with Inventory", function()
		local materials, shrines = catalogues()
		materials.fire_material.stackLimit = 999
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
	end)

	for _, output in { "unknown_material", "essence", "water_material", "", true, 1, {} } do
		it(`rejects invalid Shrine output {tostring(output)}`, function()
			local materials, shrines = catalogues()
			shrines.fire_shrine.materialId = output
			expectInvalid(materials, shrines, Inventory.materialStackLimit)
		end)
	end

	it("rejects a missing Shrine output ID", function()
		local materials, shrines = catalogues()
		shrines.fire_shrine.materialId = nil
		expectInvalid(materials, shrines, Inventory.materialStackLimit)
	end)
end)
