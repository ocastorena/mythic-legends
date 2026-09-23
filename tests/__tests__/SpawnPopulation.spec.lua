--!strict
-- ServerStorage/Tests/__tests__/SpawnPopulation.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local SpawnPopulation =
	require(game:GetService("ServerScriptService").Services.MythlingSpawnService.SpawnPopulation)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

describe("SpawnPopulation availability", function()
	it("queues all twelve initial contests before opening capture", function()
		local state = SpawnPopulation.New(12, 3)
		local rolls = 0
		SpawnPopulation.QueueDeficits(state, 0, 100, function()
			rolls += 1
			return `form{rolls}`
		end)
		expect(rolls).toBe(12)
		expect(#SpawnPopulation.GetPending(state)).toBe(12)
		expect(SpawnPopulation.OpenIfFilled(state, 0)).toBe(false)
		for index, attempt in SpawnPopulation.GetPending(state) do
			expect(attempt.typeId).toBe(`form{index}`)
			expect(attempt.deadlineAt).toBe(103)
			SpawnPopulation.Complete(state, attempt.id)
			if index < 12 then
				expect(SpawnPopulation.OpenIfFilled(state, index)).toBe(false)
			end
		end
		expect(SpawnPopulation.OpenIfFilled(state, 12)).toBe(true)
		expect(SpawnPopulation.OpenIfFilled(state, 12)).toBe(false)
	end)

	it("retains independent form selections and deadlines across placement retries", function()
		local state = SpawnPopulation.New(12, 3)
		local rolls = 0
		local function choose(): string
			rolls += 1
			return if rolls == 1 then "rare" else "common"
		end
		SpawnPopulation.QueueDeficits(state, 9, 200, choose)
		for _ = 1, 20 do
			SpawnPopulation.QueueDeficits(state, 9, 201, choose)
		end
		local pending = SpawnPopulation.GetPending(state)
		expect(rolls).toBe(3)
		expect(#pending).toBe(3)
		expect(pending[1].typeId).toBe("rare")
		expect(pending[1].deadlineAt).toBe(203)
		SpawnPopulation.Complete(state, pending[2].id)
		SpawnPopulation.QueueDeficits(state, 10, 202, choose)
		expect(#SpawnPopulation.GetPending(state)).toBe(2)
		expect(rolls).toBe(3)
	end)

	it("queues simultaneous claimed or ended slots without serial replacement delays", function()
		local state = SpawnPopulation.New(12, 3)
		expect(SpawnPopulation.OpenIfFilled(state, 12)).toBe(true)
		SpawnPopulation.QueueDeficits(state, 4, 300, function()
			return "common"
		end)
		local pending = SpawnPopulation.GetPending(state)
		expect(#pending).toBe(8)
		for _, attempt in pending do
			expect(attempt.missingSince).toBe(300)
			expect(attempt.deadlineAt).toBe(303)
		end
		expect(state.ready).toBe(true)
	end)

	it("does not replace overtime contests while their slots remain registered", function()
		local state = SpawnPopulation.New(12, 3)
		SpawnPopulation.OpenIfFilled(state, 12)
		local rolls = 0
		SpawnPopulation.QueueDeficits(state, 12, 400, function()
			rolls += 1
			return "common"
		end)
		expect(rolls).toBe(0)
		expect(#SpawnPopulation.GetPending(state)).toBe(0)
	end)

	it("reports missed deadlines once while retaining the pending attempt for recovery", function()
		local state = SpawnPopulation.New(1, 3)
		SpawnPopulation.QueueDeficits(state, 0, 500, function()
			return "rare"
		end)
		local attempt = SpawnPopulation.GetPending(state)[1]
		expect(SpawnPopulation.ReportDeadline(attempt, 502.9)).toBe(false)
		expect(SpawnPopulation.ReportDeadline(attempt, 503)).toBe(true)
		expect(SpawnPopulation.ReportDeadline(attempt, 510)).toBe(false)
		expect(#SpawnPopulation.GetPending(state)).toBe(1)
		expect(attempt.typeId).toBe("rare")
		SpawnPopulation.Complete(state, attempt.id)
		expect(SpawnPopulation.OpenIfFilled(state, 1)).toBe(true)
	end)
end)
