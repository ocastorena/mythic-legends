--!strict
-- ServerScriptService/Services/ProductionService/ProductionMath

local ProductionMath = {}

-- Production rates are configured as whole or fractional Materials per minute. Clamp the
-- elapsed interval so a future timestamp caused by clock drift or repaired save data can
-- never turn a collection into a negative inventory mutation.
function ProductionMath.StoredAmount(now: number, lastCollectionAt: number, rate: number, capacity: number): number
	local elapsedSeconds = math.max(0, now - lastCollectionAt)
	local produced = math.max(0, rate) * elapsedSeconds / 60
	return math.floor(math.min(produced, math.max(0, capacity)))
end

return table.freeze(ProductionMath)
