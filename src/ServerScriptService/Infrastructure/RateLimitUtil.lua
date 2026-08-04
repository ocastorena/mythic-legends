-- ServerScriptService/Infrastructure/RateLimitUtil

local RateLimitUtil = {}
RateLimitUtil.__index = RateLimitUtil

export type RateLimitUtil = typeof(setmetatable({
	capacity = 0,
	refillPerSecond = 0,
	buckets = {} :: { [number]: { tokens: number, updatedAt: number } },
}, RateLimitUtil))

function RateLimitUtil.new(capacity: number, refillPerSecond: number): RateLimitUtil
	assert(capacity > 0, "[RateLimitUtil] capacity must be positive")
	assert(refillPerSecond > 0, "[RateLimitUtil] refillPerSecond must be positive")
	return setmetatable({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		buckets = {},
	}, RateLimitUtil)
end

function RateLimitUtil.Allow(self: RateLimitUtil, player: Player, cost: number?): boolean
	local now = os.clock()
	local userId = player.UserId
	local bucket = self.buckets[userId]
	if not bucket then
		bucket = { tokens = self.capacity, updatedAt = now }
		self.buckets[userId] = bucket
	else
		local elapsed = math.max(0, now - bucket.updatedAt)
		bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refillPerSecond)
		bucket.updatedAt = now
	end

	local required = cost or 1
	if bucket.tokens < required then
		return false
	end
	bucket.tokens -= required
	return true
end

function RateLimitUtil.Forget(self: RateLimitUtil, player: Player)
	self.buckets[player.UserId] = nil
end

function RateLimitUtil.Clear(self: RateLimitUtil)
	table.clear(self.buckets)
end

return RateLimitUtil
