--!strict
-- ServerStorage/Tests/__tests__/MythlingCatalog.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local MythlingProgression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local MythlingSpawns = require(ReplicatedStorage.Shared.Configurations.MythlingSpawns)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local Shrines = require(ReplicatedStorage.Shared.Configurations.Shrines)
local MythlingCatalogUtil = require(ServerScriptService.Shared.MythlingCatalogUtil)
local MythlingProgressionUtil = require(ServerScriptService.Shared.MythlingProgressionUtil)
local ShrineAccrual = require(ServerScriptService.Shared.ShrineAccrual)
local MythlingEvolution = require(ServerScriptService.Services.InventoryService.MythlingEvolution)
local MythlingSales = require(ServerScriptService.Services.InventoryService.MythlingSales)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "Fire", "Water", "Earth", "Air", "Light", "Dark" }
local RARITIES = { "Common", "Rare", "Epic" }
local YIELDS = { 12, 18, 32 }
local PRICES = { 25, 100, 300 }
local CAPTURE_SECONDS = { 20, 35, 60 }
local EVOLUTION_LEVELS = { 6, 40 }
local INVALID_POSITIVE: { { label: string, value: unknown } } = {
	{ label = "missing", value = nil },
	{ label = "zero", value = 0 },
	{ label = "negative", value = -1 },
	{ label = "NaN", value = 0 / 0 },
	{ label = "infinite", value = math.huge },
	{ label = "negative infinite", value = -math.huge },
	{ label = "unsafe", value = 9_007_199_254_740_992 },
	{ label = "string", value = "1" },
	{ label = "boolean", value = true },
	{ label = "table", value = {} },
}

local function id(elementIndex: number, stage: number): string
	return string.format("mythling_%04d", (elementIndex - 1) * 3 + stage)
end

-- Detached dynamic copies support deliberate malformed-metadata tests without editing live config.
local function catalog(): { [any]: any }
	return HttpService:JSONDecode(HttpService:JSONEncode(MythlingForms))
end

local function expectValid(forms: unknown, levelCap: unknown)
	local ok, diagnostic = MythlingCatalogUtil.ValidateLaunch(forms, levelCap)
	expect(ok).toBe(true)
	expect(diagnostic).toBeNil()
end

local function expectInvalid(forms: unknown, levelCap: unknown)
	FreezeUtil.DeepFreeze(forms)
	local ok, diagnostic = MythlingCatalogUtil.ValidateLaunch(forms, levelCap)
	expect(ok).toBe(false)
	expect(type(diagnostic)).toBe("string")
	expect(diagnostic == "").toBe(false)
end

local function unassignedWorker(formId: string, level: number): ShrineAccrual.State
	return {
		lastAccruedAt = 0,
		nextBatchAt = Production.batchIntervalSeconds,
		shrines = {},
		workers = { owned = { formId = formId, level = level, xp = 17, pendingXp = 0.5 } },
	}
end

describe("Launch Mythling form catalogue", function()
	it(
		"defines six complete permanent-ID chains with the approved form-owned initial tuning",
		function()
			local count = 0
			for _ in MythlingForms do
				count += 1
			end
			expect(count).toBe(18)
			for elementIndex, element in ELEMENTS do
				for stage = 1, 3 do
					local definition = MythlingForms[id(elementIndex, stage)]
					expect(definition.element).toBe(element)
					expect(definition.evolutionStage).toBe(stage)
					expect(definition.rarity).toBe(RARITIES[stage])
					expect(definition.baseYieldPerHour).toBe(YIELDS[stage])
					expect(definition.sale.gold).toBe(PRICES[stage])
					expect(definition.captureProgressPerSecond).toBe(100 / CAPTURE_SECONDS[stage])
					expect(definition.captureDecayPerSecond).toBe(
						definition.captureProgressPerSecond
					)
					if stage < 3 then
						expect(definition.evolution).toEqual({
							targetFormId = id(elementIndex, stage + 1),
							requiredLevel = EVOLUTION_LEVELS[stage],
						})
					else
						expect(definition.evolution).toBeNil()
					end
				end
			end
			expectValid(MythlingForms, MythlingProgression.levelCap)
		end
	)

	it(
		"deep-freezes every form, sale, and evolution while leaving creative choices unset",
		function()
			expect(table.isfrozen(MythlingForms)).toBe(true)
			for _, definition in MythlingForms do
				expect(table.isfrozen(definition)).toBe(true)
				expect(table.isfrozen(definition.sale)).toBe(true)
				if definition.evolution then
					expect(table.isfrozen(definition.evolution)).toBe(true)
				end
				local raw = definition :: any
				expect(raw.displayName).toBeNil()
				expect(raw.thumbnail).toBeNil()
				expect(raw.model).toBeNil()
				expect(raw.variants).toBeNil()
				expect(raw.luck).toBeNil()
				expect(raw.traits).toBeNil()
			end
		end
	)

	it(
		"retains separate prototype identities and their original presentation/output mappings",
		function()
			expect(MythlingForms).never.toBe(Mythlings)
			local legacy: { [string]: { name: string, materialId: string, model: string } } = {
				axolotl = { name = "Stream Axolotl", materialId = "essence", model = "Axolotl" },
				dragon = { name = "Ember Fang", materialId = "crystal", model = "EmberFang" },
				satyr = { name = "Shadow Satyr", materialId = "shadow_dust", model = "Satyr" },
			}
			local count = 0
			for prototypeId, definition in Mythlings do
				count += 1
				local expected = legacy[prototypeId]
				expect(expected).never.toBeNil()
				expect(definition.displayName).toBe(expected.name)
				local production =
					assert(definition.production, "[MythlingCatalog.spec] Expected legacy output")
				expect(production.materialId).toBe(expected.materialId)
				expect(definition.variants.regular.model).toBe(expected.model)
				expect(MythlingForms[prototypeId]).toBeNil()
			end
			expect(count).toBe(3)
			for formId in MythlingForms do
				expect(Mythlings[formId]).toBeNil()
			end
		end
	)

	it("retains four-minute rarity lifetimes with no named-form overrides", function()
		for _, rarity in RARITIES do
			expect(MythlingSpawns.expireSeconds[rarity]).toBe(240)
		end
		expect(MythlingSpawns.formExpireSeconds).toEqual({})
	end)

	it("derives linear level Yield from each form without a rarity multiplier", function()
		for _, definition in MythlingForms do
			for _, level in { 1, 50, 100 } do
				expect(
					MythlingProgressionUtil.GetYield(
						definition.baseYieldPerHour,
						level,
						MythlingProgression
					)
				).toBeCloseTo(definition.baseYieldPerHour * (1 + (level - 1) * 0.01))
			end
		end
	end)

	it("feeds all 18 real forms into the existing pure Shrine work calculation", function()
		local metadata: ShrineAccrual.Metadata = { forms = {}, shrines = {} }
		local state: ShrineAccrual.State = {
			lastAccruedAt = 0,
			nextBatchAt = Production.batchIntervalSeconds,
			shrines = {},
			workers = {},
		}
		for shrineId, definition in Shrines do
			metadata.shrines[shrineId] = {
				element = definition.element,
				materialId = definition.materialId,
				levels = definition.levels,
			}
		end
		for formId, definition in MythlingForms do
			metadata.forms[formId] = {
				element = definition.element,
				baseYieldPerHour = definition.baseYieldPerHour,
			}
			state.workers[formId] = { formId = formId, level = 1, xp = 0, pendingXp = 0 }
			state.shrines[formId] = {
				shrineId = `{string.lower(definition.element)}_shrine`,
				level = 1,
				workerIdsBySlot = { ["1"] = formId },
				stored = 0,
				progress = 0,
				newWork = 0,
			}
		end
		local result, problem = ShrineAccrual.Accrue(state, 1, metadata)
		assert(result, `[MythlingCatalog.spec] Real form accrual failed: {tostring(problem)}`)
		expect(problem).toBeNil()
		for formId, definition in MythlingForms do
			expect(result.shrines[formId].progress).toBeCloseTo(definition.baseYieldPerHour / 3_600)
			expect(result.shrines[formId].stored).toBe(0)
			expect(result.workers[formId].xp).toBe(1)
			expect(state.workers[formId].xp).toBe(0)
		end
	end)

	it(
		"supports consecutive eligible evolution along every real chain without resetting progression",
		function()
			local metadata: MythlingEvolution.Metadata = { forms = {}, shrines = {} }
			for formId, definition in MythlingForms do
				metadata.forms[formId] = {
					element = definition.element,
					baseYieldPerHour = definition.baseYieldPerHour,
					evolution = definition.evolution,
				}
			end
			for elementIndex in ELEMENTS do
				local original = unassignedWorker(id(elementIndex, 1), 40)
				local state = original
				for stage = 1, 2 do
					local evolved, problem = MythlingEvolution.Evolve(state, 0, {
						workerId = "owned",
						expectedFormId = id(elementIndex, stage),
						expectedTargetFormId = id(elementIndex, stage + 1),
					}, metadata)
					assert(
						evolved,
						`[MythlingCatalog.spec] Real evolution failed: {tostring(problem)}`
					)
					expect(problem).toBeNil()
					expect(evolved.workers.owned).toEqual({
						formId = id(elementIndex, stage + 1),
						level = 40,
						xp = 17,
						pendingXp = 0.5,
					})
					state = evolved
				end
				local terminal, problem = MythlingEvolution.Evolve(state, 0, {
					workerId = "owned",
					expectedFormId = id(elementIndex, 3),
					expectedTargetFormId = id(elementIndex, 1),
				}, metadata)
				expect(terminal).toBeNil()
				expect(problem).toBe("NoEvolution")
				expect(original.workers.owned.formId).toBe(id(elementIndex, 1))
			end
		end
	)

	it("uses every real form's fixed sale price at low, developed, and capped XP levels", function()
		local metadata: MythlingSales.Metadata = { forms = {}, shrines = {} }
		for formId, definition in MythlingForms do
			metadata.forms[formId] = {
				element = definition.element,
				baseYieldPerHour = definition.baseYieldPerHour,
				sale = definition.sale,
			}
		end
		for formId, definition in MythlingForms do
			for _, level in { 1, 50, 100 } do
				local state = unassignedWorker(formId, level)
				local result, problem = MythlingSales.Sell(state, 100, 0, {
					workerId = "owned",
					expectedFormId = formId,
					expectedGoldValue = definition.sale.gold,
				}, metadata)
				assert(result, `[MythlingCatalog.spec] Real form sale failed: {tostring(problem)}`)
				expect(problem).toBeNil()
				expect(result.goldGranted).toBe(definition.sale.gold)
				expect(result.gold).toBe(100 + definition.sale.gold)
				expect(result.production.workers.owned).toBeNil()
				expect(state.workers.owned.formId).toBe(formId)
			end
		end
	end)
end)

describe("MythlingCatalogUtil.ValidateLaunch", function()
	it("validates a mutable catalogue without changing or freezing its records", function()
		local forms = catalog()
		local before = catalog()
		expectValid(forms, MythlingProgression.levelCap)
		expect(forms).toEqual(before)
		expect(table.isfrozen(forms)).toBe(false)
		expect(table.isfrozen(forms.mythling_0001)).toBe(false)
		expect(table.isfrozen(forms.mythling_0001.sale)).toBe(false)
	end)

	it("accepts legal configured tuning without imposing the initial numeric values", function()
		local forms = catalog()
		for _, definition in forms do
			local stage = definition.evolutionStage
			definition.baseYieldPerHour = stage * 20
			definition.sale.gold = stage * 50
			definition.captureProgressPerSecond = 100 / (stage * 30)
			definition.captureDecayPerSecond = definition.captureProgressPerSecond
			if definition.evolution then
				definition.evolution.requiredLevel = stage * 10
			end
		end
		expectValid(forms, 50)
	end)

	it(
		"treats permanent numbers as opaque identities rather than element or stage encodings",
		function()
			local forms = catalog()
			forms.mythling_10000 = forms.mythling_0002
			forms.mythling_0002 = nil
			forms.mythling_0001.evolution.targetFormId = "mythling_10000"
			forms.mythling_0001, forms.mythling_0018 = forms.mythling_0018, forms.mythling_0001
			forms.mythling_0017.evolution.targetFormId = "mythling_0001"
			expectValid(forms, MythlingProgression.levelCap)
		end
	)

	for _, malformed in INVALID_POSITIVE do
		if type(malformed.value) ~= "table" then
			it(`rejects a {malformed.label} catalogue root`, function()
				expectInvalid(malformed.value, MythlingProgression.levelCap)
			end)
		end
	end

	for _, invalid in INVALID_POSITIVE do
		it(`rejects a {invalid.label} level cap`, function()
			expectInvalid(MythlingForms, invalid.value)
		end)
	end
	for _, levelCap in { 1.5, 39, 9_007_199_254_740_992 } do
		it(`rejects an unusable level cap {levelCap}`, function()
			expectInvalid(MythlingForms, levelCap)
		end)
	end

	for elementIndex, element in ELEMENTS do
		for stage = 1, 3 do
			it(`rejects a missing {element} stage {stage}`, function()
				local forms = catalog()
				forms[id(elementIndex, stage)] = nil
				expectInvalid(forms, MythlingProgression.levelCap)
			end)
		end
	end

	it("rejects duplicate element/stage records even under a new valid permanent ID", function()
		local forms = catalog()
		forms.mythling_9999 = table.clone(forms.mythling_0001)
		expectInvalid(forms, MythlingProgression.levelCap)
	end)

	local invalidIds: { unknown } = {
		"",
		"fire_0001",
		"Mythling_0001",
		"mythling_000",
		"mythling_0000",
		"mythling_00001",
		"mythling_1",
		"mythling_-001",
		"mythling_0001a",
		"mythling_1.00",
		1,
	}
	for _, rawId in invalidIds do
		it(`rejects malformed permanent ID {tostring(rawId)}`, function()
			local forms = catalog()
			forms[rawId :: any] = forms.mythling_0001
			forms.mythling_0001 = nil
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end

	for _, field in { "element", "rarity", "evolutionStage" } do
		it(`rejects a missing launch {field}`, function()
			local forms = catalog()
			forms.mythling_0001[field] = nil
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end

	local invalidClassification: { { field: string, value: unknown } } = {
		{ field = "element", value = "Void" },
		{ field = "element", value = "fire" },
		{ field = "rarity", value = "Legendary" },
		{ field = "rarity", value = "Rare" },
		{ field = "evolutionStage", value = 0 },
		{ field = "evolutionStage", value = 4 },
		{ field = "evolutionStage", value = 1.5 },
		{ field = "evolutionStage", value = "1" },
	}
	for index, invalid in invalidClassification do
		it(`rejects invalid classification case {index}`, function()
			local forms = catalog()
			forms.mythling_0001[invalid.field] = invalid.value
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end

	for _, field in { "baseYieldPerHour", "captureProgressPerSecond", "captureDecayPerSecond" } do
		for _, invalid in INVALID_POSITIVE do
			it(`rejects {invalid.label} {field}`, function()
				local forms = catalog()
				forms.mythling_0001[field] = invalid.value
				expectInvalid(forms, MythlingProgression.levelCap)
			end)
		end
	end

	it("rejects non-increasing Yield at either evolution", function()
		for stage = 2, 3 do
			local forms = catalog()
			forms[id(1, stage)].baseYieldPerHour = forms[id(1, stage - 1)].baseYieldPerHour
			expectInvalid(forms, MythlingProgression.levelCap)
		end
	end)

	for _, invalid in INVALID_POSITIVE do
		it(`rejects a {invalid.label} sale price`, function()
			local forms = catalog()
			forms.mythling_0001.sale.gold = invalid.value
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end
	for _, gold in { 1.5, 9_007_199_254_740_992 } do
		it(`rejects non-whole or unsafe sale price {gold}`, function()
			local forms = catalog()
			forms.mythling_0001.sale.gold = gold
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end

	it(
		"requires matching sale prices within each rarity and increasing prices across rarities",
		function()
			local forms = catalog()
			forms.mythling_0001.sale.gold = 26
			expectInvalid(forms, MythlingProgression.levelCap)
			forms = catalog()
			for elementIndex in ELEMENTS do
				forms[id(elementIndex, 2)].sale.gold = 25
			end
			expectInvalid(forms, MythlingProgression.levelCap)
			forms = catalog()
			for elementIndex in ELEMENTS do
				forms[id(elementIndex, 3)].sale.gold = 99
			end
			expectInvalid(forms, MythlingProgression.levelCap)
		end
	)

	it(
		"allows independent per-form capture tuning while requiring matching outside decay",
		function()
			local forms = catalog()
			forms.mythling_0001.captureProgressPerSecond = 101
			forms.mythling_0001.captureDecayPerSecond = 101
			expectValid(forms, MythlingProgression.levelCap)
			forms = catalog()
			forms.mythling_0001.captureDecayPerSecond = 4
			expectInvalid(forms, MythlingProgression.levelCap)
			forms = catalog()
			forms.mythling_0001.captureProgressPerSecond = 4
			forms.mythling_0001.captureDecayPerSecond = 4
			expectValid(forms, MythlingProgression.levelCap)
		end
	)

	for _, invalid in INVALID_POSITIVE do
		it(`rejects a {invalid.label} evolution requirement`, function()
			local forms = catalog()
			forms.mythling_0001.evolution.requiredLevel = invalid.value
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end
	for _, level in { 1.5, 101, 9_007_199_254_740_992 } do
		it(`rejects an invalid whole/capped evolution requirement {level}`, function()
			local forms = catalog()
			forms.mythling_0001.evolution.requiredLevel = level
			expectInvalid(forms, MythlingProgression.levelCap)
		end)
	end

	it("requires the second evolution to have a strictly greater level threshold", function()
		for _, requiredLevel in { 5, 6 } do
			local forms = catalog()
			forms.mythling_0002.evolution.requiredLevel = requiredLevel
			expectInvalid(forms, MythlingProgression.levelCap)
		end
	end)

	local invalidTargets: { unknown } =
		{ "mythling_9999", "mythling_0001", "mythling_0003", "mythling_0005", "dragon", "", true }
	for _, target in invalidTargets do
		it(
			`rejects unknown, cyclic, skipped, or cross-element target {tostring(target)}`,
			function()
				local forms = catalog()
				forms.mythling_0001.evolution.targetFormId = target
				expectInvalid(forms, MythlingProgression.levelCap)
			end
		)
	end

	it("requires every nonterminal link and forbids evolution beyond each final form", function()
		for stage = 1, 2 do
			local forms = catalog()
			forms[id(1, stage)].evolution = nil
			expectInvalid(forms, MythlingProgression.levelCap)
		end
		local forms = catalog()
		forms.mythling_0001.evolution.targetFormId = nil
		expectInvalid(forms, MythlingProgression.levelCap)
		forms = catalog()
		forms.mythling_0003.evolution = { targetFormId = "mythling_0001", requiredLevel = 80 }
		expectInvalid(forms, MythlingProgression.levelCap)
	end)

	it("rejects malformed definition, sale, and evolution records", function()
		local forms = catalog()
		forms.mythling_0001 = true
		expectInvalid(forms, MythlingProgression.levelCap)
		forms = catalog()
		forms.mythling_0001.sale = nil
		expectInvalid(forms, MythlingProgression.levelCap)
		forms = catalog()
		forms.mythling_0001.sale = 25
		expectInvalid(forms, MythlingProgression.levelCap)
		forms = catalog()
		forms.mythling_0001.evolution = "mythling_0002"
		expectInvalid(forms, MythlingProgression.levelCap)
	end)

	it("rejects metatables at the catalogue, form, sale, or evolution boundary", function()
		for _, location in { "catalogue", "form", "sale", "evolution" } do
			local forms = catalog()
			local record = if location == "catalogue"
				then forms
				elseif location == "form" then forms.mythling_0001
				else forms.mythling_0001[location]
			setmetatable(record, {})
			expectInvalid(forms, MythlingProgression.levelCap)
		end
	end)
end)
