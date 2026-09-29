--!strict
-- ServerScriptService/Shared/MythlingProgressionUtil
-- Pure shared progression arithmetic; catalogue resolution and saved-state validation stay upstream.

local MythlingProgressionUtil = {}

export type Config = {
	levelCap: number,
	xpPerLevel: number,
	yieldGainPerLevel: number,
}

local function finiteNonnegative(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validateConfig(config: Config)
	assert(
		type(config) == "table"
			and finiteNonnegative(config.xpPerLevel)
			and config.xpPerLevel > 0
			and finiteNonnegative(config.yieldGainPerLevel)
			and finiteNonnegative(config.levelCap)
			and config.levelCap >= 1
			and config.levelCap % 1 == 0,
		"[MythlingProgressionUtil] Invalid progression configuration"
	)
end

local function validateLevel(level: number, config: Config)
	assert(
		finiteNonnegative(level) and level >= 1 and level <= config.levelCap and level % 1 == 0,
		"[MythlingProgressionUtil] Invalid Mythling level"
	)
end

function MythlingProgressionUtil.GetYield(
	baseYieldPerHour: number,
	level: number,
	config: Config
): number
	validateConfig(config)
	validateLevel(level, config)
	assert(finiteNonnegative(baseYieldPerHour), "[MythlingProgressionUtil] Invalid base Yield")
	return baseYieldPerHour * (1 + config.yieldGainPerLevel * (level - 1))
end

function MythlingProgressionUtil.GetNextLevelXp(level: number, config: Config): number
	validateConfig(config)
	validateLevel(level, config)
	return config.xpPerLevel * level
end

function MythlingProgressionUtil.AddXp(
	level: number,
	xp: number,
	earnedXp: number,
	config: Config
): (number, number)
	validateConfig(config)
	validateLevel(level, config)
	assert(finiteNonnegative(xp), "[MythlingProgressionUtil] Invalid current XP")
	assert(finiteNonnegative(earnedXp), "[MythlingProgressionUtil] Invalid earned XP")

	local remainingXp = xp + earnedXp
	assert(remainingXp < math.huge, "[MythlingProgressionUtil] XP overflow")
	while level < config.levelCap do
		local requiredXp = MythlingProgressionUtil.GetNextLevelXp(level, config)
		-- Make split fractional settlements equivalent to one combined award without
		-- rounding meaningful sub-unit XP away.
		local tolerance = math.min(1e-9, 1e-12 * math.max(remainingXp, requiredXp))
		if math.abs(remainingXp - requiredXp) <= tolerance then
			remainingXp = requiredXp
		end
		if remainingXp < requiredXp then
			break
		end
		remainingXp -= requiredXp
		level += 1
	end
	-- earnedXp is credit accumulated by the caller before this resolution. Retain any
	-- remainder at the cap; the accrual reducer decides whether capped work earns new XP.
	return level, remainingXp
end

return table.freeze(MythlingProgressionUtil)
