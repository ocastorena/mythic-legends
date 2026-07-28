-- Keeps a small, bounded history of server-observed character root transforms for
-- latency-compensated melee validation. It deliberately stores no gameplay state.

local PositionHistory = {}
PositionHistory.__index = PositionHistory

export type Sample = {
	time: number,
	cframe: CFrame,
}

function PositionHistory.new(maxAgeSeconds: number, sampleIntervalSeconds: number)
	return setmetatable({
		maxAgeSeconds = math.max(0.1, maxAgeSeconds),
		sampleIntervalSeconds = math.max(1 / 60, sampleIntervalSeconds),
		lastSampleAt = 0,
		samplesByUserId = {},
	}, PositionHistory)
end

function PositionHistory:Record(players: { Player }, now: number)
	if now - self.lastSampleAt < self.sampleIntervalSeconds then
		return
	end
	self.lastSampleAt = now

	local oldestAllowed = now - self.maxAgeSeconds
	for _, player in ipairs(players) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			local samples = self.samplesByUserId[player.UserId]
			if not samples then
				samples = {}
				self.samplesByUserId[player.UserId] = samples
			end

			table.insert(samples, {
				time = now,
				cframe = root.CFrame,
			})
			while samples[1] and samples[1].time < oldestAllowed do
				table.remove(samples, 1)
			end
		end
	end
end

function PositionHistory:GetClosest(userId: number, requestedTime: number, toleranceSeconds: number): Sample?
	local samples = self.samplesByUserId[userId]
	if not samples then
		return nil
	end

	local closest = nil
	local closestDifference = math.huge
	for index = #samples, 1, -1 do
		local sample = samples[index]
		local difference = math.abs(sample.time - requestedTime)
		if difference < closestDifference then
			closest = sample
			closestDifference = difference
		end
		if sample.time < requestedTime and difference > closestDifference then
			break
		end
	end

	return if closest and closestDifference <= toleranceSeconds then closest else nil
end

function PositionHistory:Clear(userId: number)
	self.samplesByUserId[userId] = nil
end

return PositionHistory
