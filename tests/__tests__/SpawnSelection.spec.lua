--!strict
-- ServerStorage/Tests/__tests__/SpawnSelection.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local MythlingForms = require(ReplicatedStorage.Shared.Configurations.MythlingForms)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local MythlingSpawns = require(ReplicatedStorage.Shared.Configurations.MythlingSpawns)
local SpawnSelection = require(ServerScriptService.Services.MythlingSpawnService.SpawnSelection)

local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local function build(forms: unknown, weights: unknown): SpawnSelection.Pool
	local pool, problem = SpawnSelection.Build(forms, weights)
	expect(problem).toBeNil()
	return (assert(pool, "[SpawnSelection.spec] Expected valid pool"))
end

local function choose(pool: SpawnSelection.Pool, rarityRoll: number, formRoll: number): string
	return (
		assert(
			SpawnSelection.Choose(pool, rarityRoll, formRoll),
			"[SpawnSelection.spec] Expected form"
		)
	)
end

describe("SpawnSelection", function()
	it(
		"uses only explicit rarity and deterministically sorts rarity names and form identities",
		function()
			local pool = build({
				zeta = { rarity = "Rare", evolutionStage = 1, id = "different" },
				beta = { rarity = "Common", evolutionStage = 3 },
				gamma = { rarity = "Epic" },
				alpha = { rarity = "Common", model = false },
			}, { Rare = 20, Epic = 5, Common = 75 })
			expect(pool).toEqual({
				totalWeight = 100,
				buckets = {
					{
						rarity = "Common",
						weight = 75,
						cumulativeWeight = 75,
						forms = { "alpha", "beta" },
					},
					{ rarity = "Epic", weight = 5, cumulativeWeight = 80, forms = { "gamma" } },
					{ rarity = "Rare", weight = 20, cumulativeWeight = 100, forms = { "zeta" } },
				},
			})
			local reordered = build({
				alpha = { rarity = "Common" },
				gamma = { rarity = "Epic" },
				beta = { rarity = "Common" },
				zeta = { rarity = "Rare" },
			}, { Common = 75, Epic = 5, Rare = 20 })
			expect(reordered).toEqual(pool)
		end
	)

	it("uses half-open rarity and equal-form intervals with an inclusive final endpoint", function()
		local pool = build({
			a = { rarity = "Common" },
			b = { rarity = "Common" },
			c = { rarity = "Epic" },
			d = { rarity = "Rare" },
			e = { rarity = "Rare" },
		}, { Common = 75, Epic = 5, Rare = 20 })
		expect(choose(pool, 0, 0)).toBe("a")
		expect(choose(pool, 0.75 - 1e-12, 0.5 - 1e-12)).toBe("a")
		expect(choose(pool, 0.75 - 1e-12, 0.5)).toBe("b")
		expect(choose(pool, 0.75, 0)).toBe("c")
		expect(choose(pool, 0.8 - 1e-12, 1)).toBe("c")
		expect(choose(pool, 0.8, 0)).toBe("d")
		expect(choose(pool, 1, 0.5)).toBe("e")
		expect(choose(pool, 1, 1)).toBe("e")
		local single = build({ only = { rarity = "Future" } }, { Future = 0.25 })
		expect(choose(single, 0, 0)).toBe("only")
		expect(choose(single, 1, 1)).toBe("only")
	end)

	it(
		"matches launch proportions and all six forms per rarity on a normalized 600-roll grid",
		function()
			expect(MythlingSpawns.rarityWeights).toEqual({ Common = 75, Rare = 20, Epic = 5 })
			local pool = build(MythlingForms, MythlingSpawns.rarityWeights)
			local rarities: { [string]: number } = {}
			local forms: { [string]: number } = {}
			for index = 0, 599 do
				local id = choose(pool, (index + 0.5) / 600, (index % 6 + 0.5) / 6)
				local rarity = MythlingForms[id].rarity
				rarities[rarity] = (rarities[rarity] or 0) + 1
				forms[id] = (forms[id] or 0) + 1
			end
			expect(rarities).toEqual({ Common = 450, Rare = 120, Epic = 30 })
			local expectedPerForm: { [string]: number } = { Common = 75, Rare = 20, Epic = 5 }
			local count = 0
			for id, definition in MythlingForms do
				count += 1
				expect(forms[id]).toBe(expectedPerForm[definition.rarity])
			end
			expect(count).toBe(18)
			for _, bucket in pool.buckets do
				expect(#bucket.forms).toBe(6)
				for index, id in bucket.forms do
					local previous = bucket.cumulativeWeight - bucket.weight
					local rarityRoll = (previous + bucket.weight / 2) / pool.totalWeight
					expect(choose(pool, rarityRoll, (index - 1) / 6)).toBe(id)
				end
			end
		end
	)

	it(
		"preserves equivalent scaled weights without requiring percentages or integer weights",
		function()
			local normal = build(MythlingForms, { Common = 75, Rare = 20, Epic = 5 })
			local small = build(MythlingForms, { Common = 7.5, Rare = 2, Epic = 0.5 })
			local large = build(MythlingForms, { Common = 750, Rare = 200, Epic = 50 })
			for index = 0, 600 do
				local rarityRoll, formRoll = index / 600, index % 7 / 6
				local id = choose(normal, rarityRoll, formRoll)
				expect(choose(small, rarityRoll, formRoll)).toBe(id)
				expect(choose(large, rarityRoll, formRoll)).toBe(id)
			end
		end
	)

	it(
		"retains the separate prototype effective weights without admitting prototypes to launch",
		function()
			expect(MythlingSpawns.prototypeRarityWeights).toEqual({
				Common = 100,
				Rare = 50,
				Legendary = 15,
			})
			local pool = build(Mythlings, MythlingSpawns.prototypeRarityWeights)
			local counts: { [string]: number } = {}
			for index = 0, 164 do
				local id = choose(pool, (index + 0.5) / 165, 0.5)
				local rarity = Mythlings[id].rarity
				counts[rarity] = (counts[rarity] or 0) + 1
			end
			expect(counts).toEqual({ Common = 100, Rare = 50, Legendary = 15 })
			expect((SpawnSelection.Build(Mythlings, MythlingSpawns.rarityWeights))).toBeNil()
			expect((SpawnSelection.Build(MythlingForms, MythlingSpawns.prototypeRarityWeights))).toBeNil()
		end
	)

	it("does not impose per-population quotas or mutate its selection state", function()
		local pool = build(MythlingForms, MythlingSpawns.rarityWeights)
		local first = choose(pool, 0.1, 0.1)
		for _ = 1, 24 do
			expect(choose(pool, 0.1, 0.1)).toBe(first)
		end
		expect(pool.totalWeight).toBe(100)
		expect(#pool.buckets).toBe(3)
	end)

	it(
		"returns recursively frozen detached pools without freezing or retaining input records",
		function()
			local forms = { a = { rarity = "Common", assets = { model = "prototype" } } }
			local weights = { Common = 1 }
			local pool = build(forms, weights)
			expect(table.isfrozen(pool)).toBe(true)
			expect(table.isfrozen(pool.buckets)).toBe(true)
			expect(table.isfrozen(pool.buckets[1])).toBe(true)
			expect(table.isfrozen(pool.buckets[1].forms)).toBe(true)
			expect(table.isfrozen(forms)).toBe(false)
			expect(table.isfrozen(forms.a)).toBe(false)
			expect(table.isfrozen(forms.a.assets)).toBe(false)
			expect(table.isfrozen(weights)).toBe(false)
			forms.a.rarity = "Other"
			forms.a.assets.model = "changed"
			weights.Common = 9
			expect(pool.totalWeight).toBe(1)
			expect(pool.buckets[1].rarity).toBe("Common")
			expect(choose(pool, 1, 1)).toBe("a")
			FreezeUtil.DeepFreeze(forms)
			local frozenWeights = { Other = 2 }
			FreezeUtil.DeepFreeze(frozenWeights)
			expect(build(forms, frozenWeights).buckets[1].rarity).toBe("Other")
		end
	)

	it("rejects malformed maps, IDs, records, or explicit rarity metadata", function()
		local invalid: { unknown } = {
			false,
			7,
			"forms",
			{},
			setmetatable({ a = { rarity = "Common" } }, {}),
			{ [1] = { rarity = "Common" } },
			{ [""] = { rarity = "Common" } },
			{ [string.rep("a", 129)] = { rarity = "Common" } },
			{ a = false },
			{ a = "Common" },
			{ a = {} },
			{ a = setmetatable({ rarity = "Common" }, {}) },
			{ a = { rarity = false } },
			{ a = { rarity = "" } },
			{ a = { rarity = string.rep("r", 129) } },
		}
		for _, forms in invalid do
			local pool, problem = SpawnSelection.Build(forms, { Common = 1 })
			expect(pool).toBeNil()
			expect(problem).toBe("InvalidSpawnConfiguration")
		end
		local pool, problem = SpawnSelection.Build(nil, { Common = 1 })
		expect(pool).toBeNil()
		expect(problem).toBe("InvalidSpawnConfiguration")
	end)

	it("requires exactly one positive finite weight for every nonempty form rarity", function()
		local forms = { a = { rarity = "Common" }, b = { rarity = "Rare" } }
		local invalid: { unknown } = {
			false,
			7,
			"weights",
			{},
			{ Common = 1 },
			{ Rare = 1 },
			{ Common = 1, Rare = 1, Epic = 1 },
			{ Common = 1, Rare = 1, Epic = 0 },
			{ Common = 1, Rare = 1, [1] = 1 },
			setmetatable({ Common = 1, Rare = 1 }, {}),
		}
		for _, weight in { 0, -1, 0 / 0, math.huge, -math.huge, false, "1", {} } do
			table.insert(invalid, { Common = 1, Rare = weight })
		end
		for _, weights in invalid do
			local pool, problem = SpawnSelection.Build(forms, weights)
			expect(pool).toBeNil()
			expect(problem).toBe("InvalidSpawnConfiguration")
		end
		local pool, problem = SpawnSelection.Build(forms, nil)
		expect(pool).toBeNil()
		expect(problem).toBe("InvalidSpawnConfiguration")
	end)

	it(
		"rejects unsafe totals and positive groups erased by cumulative floating-point precision",
		function()
			local forms = { a = { rarity = "A" }, b = { rarity = "B" } }
			for _, weights in
				{
					{ A = 2 ^ 53 - 1, B = 1 },
					{ A = 1e308, B = 1e308 },
					{ A = 2 ^ 52, B = 0.1 },
					{ A = 1, B = 1e-20 },
				}
			do
				local pool, problem = SpawnSelection.Build(forms, weights)
				expect(pool).toBeNil()
				expect(problem).toBe("InvalidSpawnConfiguration")
			end
			expect(build({ only = { rarity = "Common" } }, { Common = 2 ^ 53 - 1 }).totalWeight).toBe(
				2 ^ 53 - 1
			)
		end
	)

	it("rejects nonnumeric, nonfinite, and out-of-range rolls without coercion", function()
		local pool = build({ a = { rarity = "Common" } }, { Common = 1 })
		local unchecked =
			SpawnSelection.Choose :: (SpawnSelection.Pool, unknown, unknown) -> string?
		for _, roll in { -0.001, 1.001, 0 / 0, math.huge, -math.huge, false, "0.5", {} } do
			expect(unchecked(pool, roll, 0.5)).toBeNil()
			expect(unchecked(pool, 0.5, roll)).toBeNil()
		end
		expect(unchecked(pool, nil, 0.5)).toBeNil()
		expect(unchecked(pool, 0.5, nil)).toBeNil()
		expect(choose(pool, -0, -0)).toBe("a")
	end)
end)
