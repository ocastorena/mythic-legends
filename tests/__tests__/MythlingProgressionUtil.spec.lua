--!strict
-- ServerStorage/Tests/__tests__/MythlingProgressionUtil.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local MythlingProgression = require(ReplicatedStorage.Shared.Configurations.MythlingProgression)
local Production = require(ReplicatedStorage.Shared.Configurations.Production)
local MythlingProgressionUtil = require(ServerScriptService.Shared.MythlingProgressionUtil)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local CONFIG: MythlingProgressionUtil.Config = MythlingProgression

describe("Mythling progression configuration", function()
	it("provides the shared launch production and progression tuning", function()
		expect(Production.batchIntervalSeconds).toBe(1)
		expect(Production.baseXpPerSecond).toBe(1)
		expect(CONFIG.levelCap).toBe(100)
		expect(CONFIG.xpPerLevel).toBe(120)
		expect(CONFIG.yieldGainPerLevel).toBe(0.01)
		expect(table.isfrozen(Production)).toBe(true)
		expect(table.isfrozen(MythlingProgression)).toBe(true)
	end)
end)

describe("MythlingProgressionUtil.GetYield", function()
	it("applies the level bonus linearly without compounding", function()
		expect(MythlingProgressionUtil.GetYield(12, 1, CONFIG)).toBe(12)
		expect(MythlingProgressionUtil.GetYield(12, 2, CONFIG)).toBeCloseTo(12.12)
		expect(MythlingProgressionUtil.GetYield(12, 50, CONFIG)).toBeCloseTo(17.88)
		expect(MythlingProgressionUtil.GetYield(12, 100, CONFIG)).toBeCloseTo(23.88)
	end)

	it("retains a Mythling's progression while a new form supplies the new base Yield", function()
		local level = 40
		local xp = 17.25
		local rareYield = MythlingProgressionUtil.GetYield(18, level, CONFIG)
		local evolvedYield = MythlingProgressionUtil.GetYield(32, level, CONFIG)

		expect(rareYield).toBeCloseTo(25.02)
		expect(evolvedYield).toBeCloseTo(44.48)
		expect(level).toBe(40)
		expect(xp).toBe(17.25)
	end)

	it("is deterministic and applies no random, rarity, Luck, or Trait modifier", function()
		local expected = MythlingProgressionUtil.GetYield(32, 50, CONFIG)
		for _ = 1, 20 do
			expect(MythlingProgressionUtil.GetYield(32, 50, CONFIG)).toBe(expected)
		end
	end)
end)

describe("MythlingProgressionUtil XP", function()
	it("does not manufacture levels on tiny configurable curves without earned XP", function()
		local tiny = { levelCap = 100, xpPerLevel = 1e-12, yieldGainPerLevel = 0 }
		local level, xp = MythlingProgressionUtil.AddXp(1, 0, 0, tiny)
		expect(level).toBe(1)
		expect(xp).toBe(0)
	end)

	it("uses 120 times the current level for the next-level requirement", function()
		expect(MythlingProgressionUtil.GetNextLevelXp(1, CONFIG)).toBe(120)
		expect(MythlingProgressionUtil.GetNextLevelXp(5, CONFIG)).toBe(600)
		expect(MythlingProgressionUtil.GetNextLevelXp(39, CONFIG)).toBe(4_680)
		expect(MythlingProgressionUtil.GetNextLevelXp(100, CONFIG)).toBe(12_000)
	end)

	it("reaches the level 6, 40, and 100 milestones at their exact cumulative XP", function()
		for _, milestone in
			{
				{ earnedXp = 1_800, level = 6 },
				{ earnedXp = 93_600, level = 40 },
				{ earnedXp = 594_000, level = 100 },
			}
		do
			local level, xp = MythlingProgressionUtil.AddXp(1, 0, milestone.earnedXp, CONFIG)
			expect(level).toBe(milestone.level)
			expect(xp).toBe(0)
		end
	end)

	it("retains sub-unit XP precision across a level boundary", function()
		local level, xp = MythlingProgressionUtil.AddXp(5, 599.75, 0.5, CONFIG)
		expect(level).toBe(6)
		expect(xp).toBeCloseTo(0.25)

		level, xp = MythlingProgressionUtil.AddXp(level, xp, 0.125, CONFIG)
		expect(level).toBe(6)
		expect(xp).toBeCloseTo(0.375)
	end)

	it("snaps only machine-scale error at an exact fractional threshold", function()
		local level, xp = 1, 119
		for _ = 1, 10 do
			level, xp = MythlingProgressionUtil.AddXp(level, xp, 0.1, CONFIG)
		end
		expect(level).toBe(2)
		expect(xp).toBeCloseTo(0)
	end)

	it("retains every already-earned contribution when reaching or starting at the cap", function()
		local level, xp = MythlingProgressionUtil.AddXp(99, 11_879.75, 0.5, CONFIG)
		expect(level).toBe(100)
		expect(xp).toBeCloseTo(0.25)

		level, xp = MythlingProgressionUtil.AddXp(level, xp, 0.125, CONFIG)
		expect(level).toBe(100)
		expect(xp).toBeCloseTo(0.375)
	end)

	it("fails fast for invalid numeric state instead of manufacturing progression", function()
		for _, invalid in { -1, math.huge, 0 / 0 } do
			expect(function()
				MythlingProgressionUtil.GetYield(invalid, 1, CONFIG)
			end).toThrow()
			expect(function()
				MythlingProgressionUtil.AddXp(1, invalid, 0, CONFIG)
			end).toThrow()
			expect(function()
				MythlingProgressionUtil.AddXp(1, 0, invalid, CONFIG)
			end).toThrow()
		end
		for _, invalidLevel in { 0, 1.5, 101 } do
			expect(function()
				MythlingProgressionUtil.GetNextLevelXp(invalidLevel, CONFIG)
			end).toThrow()
		end
	end)

	it("rejects malformed progression configurations", function()
		for _, invalidConfig in
			{
				{ levelCap = 0, xpPerLevel = 120, yieldGainPerLevel = 0.01 },
				{ levelCap = 1.5, xpPerLevel = 120, yieldGainPerLevel = 0.01 },
				{ levelCap = 100, xpPerLevel = 0, yieldGainPerLevel = 0.01 },
				{ levelCap = 100, xpPerLevel = 120, yieldGainPerLevel = -0.01 },
				{ levelCap = 100, xpPerLevel = math.huge, yieldGainPerLevel = 0.01 },
			}
		do
			expect(function()
				MythlingProgressionUtil.GetNextLevelXp(
					1,
					invalidConfig :: MythlingProgressionUtil.Config
				)
			end).toThrow()
		end
	end)
end)
