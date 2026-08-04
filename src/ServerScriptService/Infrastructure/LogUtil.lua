-- ServerScriptService/Infrastructure/LogUtil
-- Tagged failure-only logging for project-owned server code.

local LogUtil = {}

-- Returns a logger bound to one tag. Use warn for recoverable anomalies and error for
-- serious failures that have already been safely contained. Neither method throws.
function LogUtil.For(tag: string)
	return {
		warn = function(...)
			warn(`[{tag}][Warn]`, ...)
		end,
		error = function(...)
			warn(`[{tag}][Error]`, ...)
		end,
	}
end

return LogUtil
