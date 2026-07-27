-- ServerScriptService/Infrastructure/LogUtil
-- Tagged, level-filtered logging. Replaces bare print() so that verbose output can be
-- turned down in production without hunting individual call sites.

local LogUtil = {}

local LEVELS = {
	debug = 10,
	info = 20,
	warn = 30,
	error = 40,
}

-- Raise this to silence lower levels. Debug output (payload dumps, cache contents) is
-- off by default so player documents never reach production logs.
local minLevel = LEVELS.info

function LogUtil.SetMinLevel(levelName: string)
	local level = LEVELS[levelName]
	if not level then
		warn(`[LogUtil] Unknown level '{levelName}'`)
		return
	end
	minLevel = level
end

-- Returns a logger bound to one tag, e.g. LogUtil.For("SpawnService").info("Started")
function LogUtil.For(tag: string)
	local prefix = `[{tag}]`

	local function emit(level: number, sink, ...)
		if level < minLevel then
			return
		end
		sink(prefix, ...)
	end

	return {
		debug = function(...)
			emit(LEVELS.debug, print, ...)
		end,
		info = function(...)
			emit(LEVELS.info, print, ...)
		end,
		warn = function(...)
			emit(LEVELS.warn, warn, ...)
		end,
		error = function(...)
			emit(LEVELS.error, warn, ...)
		end,
	}
end

return LogUtil
