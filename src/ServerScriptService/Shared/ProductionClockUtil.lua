--!strict
-- ServerScriptService/Shared/ProductionClockUtil
-- Session hints never replace the authoritative earned-work cursor or restart a batch.

local ProductionClockUtil = {}

local function timestamp(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < 2 ^ 53
end

function ProductionClockUtil.ValidateLifecycle(clock: unknown): boolean
	if type(clock) ~= "table" or getmetatable(clock) ~= nil then
		return false
	end
	local fields = clock :: { [string]: unknown }
	local accrued = fields.lastAccruedAt
	local checkpoint = fields.lastOnlineCheckpointAt
	local offline = fields.offlineSince
	if not timestamp(accrued) then
		return false
	end
	-- Both absent is the supported pre-lifecycle schema-7 state, not lost earnings.
	if checkpoint == nil then
		return offline == nil
	end
	if not timestamp(checkpoint) or (checkpoint :: number) > (accrued :: number) then
		return false
	end
	return offline == nil
		or (
			timestamp(offline)
			and (offline :: number) >= (checkpoint :: number)
			and (offline :: number) <= (accrued :: number)
		)
end

return table.freeze(ProductionClockUtil)
