--!strict
-- ServerStorage/Tests/__tests__/SpawnLifetime.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local MythlingSpawns = require(ReplicatedStorage.Shared.Configurations.MythlingSpawns)
local SpawnLifetimeUtil =
	require(ServerScriptService.Services.MythlingSpawnService.SpawnLifetimeUtil)

local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

-- Dynamic detached copies allow malformed configuration tests without mutating live tuning.
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = copy(child)
	end
	return result
end

local function expectInvalidConfiguration(tuning: any)
	local lifetime, problem = SpawnLifetimeUtil.Resolve("mythling_0001", "Common", 5, tuning)
	expect(lifetime).toBeNil()
	expect(problem).toBe("InvalidLifetimeConfiguration")
	local valid, validationProblem =
		SpawnLifetimeUtil.Validate(MythlingForms, tuning, "captureProgressPerSecond")
	expect(valid).toBe(false)
	expect(validationProblem).toBe(problem)
end

describe("Spawn lifetime policy", function()
	it("derives safe future deadlines without retaining or changing any timer state", function()
		expect(SpawnLifetimeUtil.GetDeadline(0, 240)).toBe(240)
		expect(SpawnLifetimeUtil.GetDeadline(100.25, 20.5)).toBe(120.75)
		expect(SpawnLifetimeUtil.GetDeadline(0, 2 ^ 53 - 1)).toBe(2 ^ 53 - 1)
		expect(SpawnLifetimeUtil.GetDeadline(2 ^ 53 - 2, 1)).toBe(2 ^ 53 - 1)
		local recorded = SpawnLifetimeUtil.GetDeadline(100, 240)
		expect(SpawnLifetimeUtil.GetDeadline(100, 300)).toBe(400)
		expect(SpawnLifetimeUtil.GetDeadline(200, 240)).toBe(440)
		expect(recorded).toBe(340)
		expect(SpawnLifetimeUtil.GetDeadline(100, 240)).toBe(recorded)
	end)

	it(
		"rejects invalid deadline inputs, unsafe sums, and lifetimes lost to clock precision",
		function()
			local invalidTimes: { unknown } =
				{ -1, 0 / 0, math.huge, -math.huge, 2 ^ 53, "100", false, {} }
			for _, raw in invalidTimes do
				expect(SpawnLifetimeUtil.GetDeadline(raw :: number, 240)).toBeNil()
			end
			local invalidLifetimes: { unknown } =
				{ 0, -1, 0 / 0, math.huge, -math.huge, 2 ^ 53, "240", false, {} }
			for _, raw in invalidLifetimes do
				expect(SpawnLifetimeUtil.GetDeadline(100, raw :: number)).toBeNil()
			end
			expect(SpawnLifetimeUtil.GetDeadline((nil :: unknown) :: number, 240)).toBeNil()
			expect(SpawnLifetimeUtil.GetDeadline(100, (nil :: unknown) :: number)).toBeNil()
			expect(SpawnLifetimeUtil.GetDeadline(2 ^ 53 - 1, 1)).toBeNil()
			expect(SpawnLifetimeUtil.GetDeadline(100, 2 ^ 53 - 1)).toBeNil()
			expect(SpawnLifetimeUtil.GetDeadline(1_000_000_000, 1e-12)).toBeNil()
			expect(SpawnLifetimeUtil.GetDeadline(2 ^ 53 - 1, 0.1)).toBeNil()
		end
	)

	it("gives all eighteen launch forms 240 seconds with no initial named overrides", function()
		local durations: { [string]: number } = { Common = 20, Rare = 35, Epic = 60 }
		local count = 0
		for id, definition in MythlingForms do
			count += 1
			expect(MythlingSpawns.formExpireSeconds[id]).toBeNil()
			expect(MythlingSpawns.expireSeconds[definition.rarity]).toBe(240)
			expect(100 / definition.captureProgressPerSecond).toBeCloseTo(
				durations[definition.rarity]
			)
			local lifetime, problem = SpawnLifetimeUtil.Resolve(
				id,
				definition.rarity,
				definition.captureProgressPerSecond,
				MythlingSpawns
			)
			expect(lifetime).toBe(240)
			expect(problem).toBeNil()
		end
		expect(count).toBe(18)
		local valid, problem =
			SpawnLifetimeUtil.Validate(MythlingForms, MythlingSpawns, "captureProgressPerSecond")
		expect(valid).toBe(true)
		expect(problem).toBeNil()
	end)

	it(
		"uses the explicit canonical or prototype rate field without inferring rarity durations",
		function()
			expect((SpawnLifetimeUtil.Validate(Mythlings, MythlingSpawns, "fillRate"))).toBe(true)
			local canonicalWrong, canonicalProblem =
				SpawnLifetimeUtil.Validate(MythlingForms, MythlingSpawns, "fillRate")
			expect(canonicalWrong).toBe(false)
			expect(canonicalProblem).toBe("InvalidCaptureRate")
			local prototypeWrong, prototypeProblem =
				SpawnLifetimeUtil.Validate(Mythlings, MythlingSpawns, "captureProgressPerSecond")
			expect(prototypeWrong).toBe(false)
			expect(prototypeProblem).toBe("InvalidCaptureRate")
			local custom =
				{ test = { rarity = "Common", fillRate = 0.1, captureProgressPerSecond = 10 } }
			expect((SpawnLifetimeUtil.Validate(custom, MythlingSpawns, "captureProgressPerSecond"))).toBe(
				true
			)
			local invalid, problem = SpawnLifetimeUtil.Validate(custom, MythlingSpawns, "fillRate")
			expect(invalid).toBe(false)
			expect(problem).toBe("InsufficientLifetime")
			expect((SpawnLifetimeUtil.Validate(custom, MythlingSpawns, "arbitraryField"))).toBe(
				false
			)
		end
	)

	it("prefers a named override and retains independently configured rarity defaults", function()
		local tuning = copy(MythlingSpawns)
		tuning.expireSeconds.Common = 300
		tuning.formExpireSeconds.mythling_0001 = 90.5
		tuning.formExpireSeconds.axolotl = 120
		-- One shared override map can contain other catalogue IDs or future content.
		tuning.formExpireSeconds.future_form = 600
		expect((SpawnLifetimeUtil.Resolve("mythling_0001", "Common", 5, tuning))).toBe(90.5)
		expect((SpawnLifetimeUtil.Resolve("mythling_0004", "Common", 5, tuning))).toBe(300)
		expect((SpawnLifetimeUtil.Resolve("axolotl", "Legendary", 10, tuning))).toBe(120)
		expect((SpawnLifetimeUtil.Validate(MythlingForms, tuning, "captureProgressPerSecond"))).toBe(
			true
		)
		expect((SpawnLifetimeUtil.Validate(Mythlings, tuning, "fillRate"))).toBe(true)
	end)

	it(
		"requires the rarity default even with a valid override or a legacy global fallback",
		function()
			for _, overridden in { false, true } do
				local tuning = copy(MythlingSpawns)
				tuning.expireSeconds.Common = nil
				tuning.defaultExpireSeconds = 10_000
				if overridden then
					tuning.formExpireSeconds.mythling_0001 = 240
				end
				expectInvalidConfiguration(tuning)
			end
		end
	)

	it("rejects malformed tuning roots and non-plain lifetime maps", function()
		local invalidRoots: { unknown } =
			{ false, 1, "tuning", setmetatable(copy(MythlingSpawns), {}) }
		for _, raw in invalidRoots do
			expectInvalidConfiguration(raw)
		end
		for _, field in { "expireSeconds", "formExpireSeconds" } do
			local invalidMaps: { { value: unknown } } = {
				{ value = nil },
				{ value = false },
				{ value = 1 },
				{ value = "map" },
				{ value = setmetatable({}, {}) },
			}
			for _, case in invalidMaps do
				local tuning = copy(MythlingSpawns)
				tuning[field] = case.value
				expectInvalidConfiguration(tuning)
			end
		end
	end)

	it(
		"rejects invalid values anywhere in either lifetime map instead of silently falling back",
		function()
			local invalidValues: { unknown } =
				{ 0, -1, 0 / 0, math.huge, -math.huge, 2 ^ 53, "240", false, {} }
			for _, field in { "expireSeconds", "formExpireSeconds" } do
				for _, value in invalidValues do
					local tuning = copy(MythlingSpawns)
					tuning[field].unused_future_entry = value
					expectInvalidConfiguration(tuning)
				end
			end
			for _, value in invalidValues do
				local tuning = copy(MythlingSpawns)
				tuning.formExpireSeconds.mythling_0001 = value
				expectInvalidConfiguration(tuning)
			end
		end
	)

	it("validates all lifetime keys as bounded nonempty metadata identities", function()
		local invalidKeys: { unknown } = { "", string.rep("a", 129), 1, false }
		for _, field in { "expireSeconds", "formExpireSeconds" } do
			for _, key in invalidKeys do
				local tuning = copy(MythlingSpawns)
				tuning[field][key] = 240
				expectInvalidConfiguration(tuning)
			end
		end
	end)

	it("requires a finite safe capture rate and safe derived capture duration", function()
		local invalidRates: { unknown } = { 0, -1, 0 / 0, math.huge, 2 ^ 53, 1e-20, "5", false, {} }
		for _, raw in invalidRates do
			local lifetime, problem =
				SpawnLifetimeUtil.Resolve("mythling_0001", "Common", raw :: number, MythlingSpawns)
			expect(lifetime).toBeNil()
			expect(problem).toBe("InvalidCaptureRate")
		end
		local lifetime, problem = SpawnLifetimeUtil.Resolve(
			"mythling_0001",
			"Common",
			(nil :: unknown) :: number,
			MythlingSpawns
		)
		expect(lifetime).toBeNil()
		expect(problem).toBe("InvalidCaptureRate")
	end)

	it(
		"requires positive arrival slack for defaults and overrides without inventing a travel budget",
		function()
			for _, overridden in { false, true } do
				for _, lifetime in { 19, 20, 20.01 } do
					local tuning = copy(MythlingSpawns)
					if overridden then
						tuning.formExpireSeconds.mythling_0001 = lifetime
					else
						tuning.expireSeconds.Common = lifetime
					end
					local resolved, problem =
						SpawnLifetimeUtil.Resolve("mythling_0001", "Common", 5, tuning)
					if lifetime > 20 then
						expect(resolved).toBe(lifetime)
						expect(problem).toBeNil()
					else
						expect(resolved).toBeNil()
						expect(problem).toBe("InsufficientLifetime")
					end
				end
			end
		end
	)

	it(
		"fails closed on malformed catalogue identities, definitions, or missing rate fields",
		function()
			local invalid: { { forms: unknown, code: string } } = {
				{ forms = false, code = "InvalidFormDefinition" },
				{ forms = {}, code = "InvalidFormDefinition" },
				{ forms = setmetatable({}, {}), code = "InvalidFormDefinition" },
				{ forms = { [1] = { rarity = "Common", fillRate = 5 } }, code = "InvalidFormId" },
				{ forms = { bad = false }, code = "InvalidFormDefinition" },
				{
					forms = { bad = setmetatable({ rarity = "Common", fillRate = 5 }, {}) },
					code = "InvalidFormDefinition",
				},
				{
					forms = { bad = { rarity = false, fillRate = 5 } },
					code = "InvalidFormDefinition",
				},
				{ forms = { bad = { rarity = "Common" } }, code = "InvalidCaptureRate" },
			}
			for _, case in invalid do
				local valid, problem =
					SpawnLifetimeUtil.Validate(case.forms, MythlingSpawns, "fillRate")
				expect(valid).toBe(false)
				expect(problem).toBe(case.code)
			end
		end
	)

	it("leaves borrowed input tables mutable or frozen exactly as supplied", function()
		local tuning = copy(MythlingSpawns)
		local forms = copy(MythlingForms)
		local beforeTuning, beforeForms = copy(tuning), copy(forms)
		expect((SpawnLifetimeUtil.Validate(forms, tuning, "captureProgressPerSecond"))).toBe(true)
		expect(tuning).toEqual(beforeTuning)
		expect(forms).toEqual(beforeForms)
		expect(table.isfrozen(tuning)).toBe(false)
		expect(table.isfrozen(tuning.expireSeconds)).toBe(false)
		expect(table.isfrozen(forms.mythling_0001)).toBe(false)
		FreezeUtil.DeepFreeze(tuning)
		FreezeUtil.DeepFreeze(forms)
		expect((SpawnLifetimeUtil.Validate(forms, tuning, "captureProgressPerSecond"))).toBe(true)
		expect((SpawnLifetimeUtil.Resolve("mythling_0001", "Common", 5, tuning))).toBe(240)
		expect(tuning).toEqual(beforeTuning)
		expect(forms).toEqual(beforeForms)
	end)
end)
