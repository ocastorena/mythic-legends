-- ServerScriptService/ServerModules/Infrastructure/RateLimiter

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({
	capacity = 0,
	refillPerSecond = 0,
	buckets = {} :: { [number]: { tokens: number, updatedAt: number } },
}, RateLimiter))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	assert(capacity > 0, "[RateLimiter] capacity must be positive")
	assert(refillPerSecond > 0, "[RateLimiter] refillPerSecond must be positive")
	return setmetatable({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		buckets = {},
	}, RateLimiter)
end

function RateLimiter.Allow(self: RateLimiter, player: Player, cost: number?): boolean
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

function RateLimiter.Forget(self: RateLimiter, player: Player)
	self.buckets[player.UserId] = nil
end

function RateLimiter.Clear(self: RateLimiter)
	table.clear(self.buckets)
end

return RateLimiter
