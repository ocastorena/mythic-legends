--!strict
-- ServerStorage/Tests/__tests__/ContestState.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ContestState =
	require(game:GetService("ServerScriptService").Services.ClaimService.ContestState)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function newContest(expireAt: number?): ContestState.State
	return ContestState.New(0, expireAt or 240, 5, 5)
end

describe("ContestState capture progress", function()
	it(
		"keeps independent player meters and orders winners by their calculated completion times",
		function()
			local state = newContest()
			ContestState.SetOccupants(state, 0, { [20] = true })
			ContestState.SetOccupants(state, 2, { [20] = true, [10] = true })
			local candidates = ContestState.Advance(state, 25)
			expect(#candidates).toBe(2)
			expect(candidates[1].userId).toBe(20)
			expect(candidates[1].completionAt).toBe(20)
			expect(candidates[2].userId).toBe(10)
			expect(candidates[2].completionAt).toBe(22)
			expect(state.phase).toBe("ACTIVE")
			expect(state.winnerUserId).toBeNil()
		end
	)

	it("preserves a previous ring's decaying work while progressing in a different ring", function()
		local first = newContest()
		local second = newContest()
		ContestState.SetOccupants(first, 0, { [1] = true })
		ContestState.SetOccupants(first, 10, {})
		ContestState.SetOccupants(second, 10, { [1] = true })
		ContestState.Advance(first, 13)
		ContestState.Advance(second, 13)
		expect(first.meters[1].progress).toBe(35)
		expect(first.meters[1].inside).toBe(false)
		expect(second.meters[1].progress).toBe(15)
		ContestState.SetOccupants(first, 13, { [1] = true })
		expect(first.meters[1].progress).toBe(35)
		local candidates = ContestState.Advance(first, 26)
		expect(candidates[1].completionAt).toBe(26)
	end)

	it(
		"starts decay on departure, clamps at zero, and starts a fresh empty meter after decay",
		function()
			local state = newContest()
			ContestState.SetOccupants(state, 0, { [1] = true })
			ContestState.SetOccupants(state, 4, {})
			expect(state.meters[1].progress).toBe(20)
			ContestState.Advance(state, 6)
			expect(state.meters[1].progress).toBe(10)
			ContestState.Advance(state, 12)
			expect(state.meters[1]).toBeNil()
			ContestState.SetOccupants(state, 20, { [1] = true })
			expect(state.meters[1].progress).toBe(0)
		end
	)

	it("gives a re-entry new tie priority while retaining the remaining meter", function()
		local state = newContest()
		ContestState.SetOccupants(state, 0, { [20] = true })
		local originalVisit = state.meters[20].visitOrder
		ContestState.SetOccupants(state, 2, { [20] = true, [10] = true })
		ContestState.SetOccupants(state, 3, { [10] = true })
		ContestState.SetOccupants(state, 4, { [20] = true, [10] = true })
		expect(state.meters[20].progress).toBe(10)
		expect(state.meters[10].progress).toBe(10)
		expect(state.meters[20].visitOrder).never.toBe(originalVisit)
		local candidates = ContestState.Advance(state, 22)
		expect(candidates[1].completionAt).toBe(22)
		expect(candidates[2].completionAt).toBe(22)
		expect(candidates[1].userId).toBe(10)
		expect(candidates[2].userId).toBe(20)
	end)

	it(
		"uses completion time before visit order when a returning player has more progress",
		function()
			local state = newContest()
			ContestState.SetOccupants(state, 0, { [20] = true })
			ContestState.SetOccupants(state, 8, { [10] = true })
			ContestState.SetOccupants(state, 10, { [10] = true, [20] = true })
			local candidates = ContestState.Advance(state, 30)
			expect(candidates[1].userId).toBe(20)
			expect(candidates[1].completionAt).toBe(24)
			expect(candidates[2].userId).toBe(10)
			expect(candidates[2].completionAt).toBe(28)
		end
	)

	it("assigns stable unique visits to entries observed in the same update", function()
		local state = newContest()
		ContestState.SetOccupants(state, 0, { [30] = true, [10] = true, [20] = true })
		expect(state.meters[10].visitOrder).toBe(1)
		expect(state.meters[20].visitOrder).toBe(2)
		expect(state.meters[30].visitOrder).toBe(3)
		local candidates = ContestState.Advance(state, 20)
		expect(candidates[1].userId).toBe(10)
		expect(candidates[2].userId).toBe(20)
		expect(candidates[3].userId).toBe(30)
	end)

	it(
		"retains all configured capture durations at the exact deadline across small updates",
		function()
			for _, duration in { 20, 35, 60 } do
				local state = ContestState.New(0, duration, 100 / duration, 100 / duration)
				ContestState.SetOccupants(state, 0, { [1] = true })
				for tick = 1, duration * 10 - 1 do
					expect(#ContestState.Advance(state, tick / 10)).toBe(0)
					ContestState.Finalize(state)
				end
				local candidates = ContestState.SetOccupants(state, duration, {})
				expect(#candidates).toBe(1)
				expect(candidates[1].completionAt).toBe(duration)
				expect(ContestState.AcceptWinner(state, 1)).toBe(true)
			end
		end
	)

	it("keeps the deadline and progress stable when time goes backwards", function()
		local state = newContest()
		ContestState.SetOccupants(state, 0, { [1] = true })
		ContestState.Advance(state, 10)
		ContestState.Advance(state, 5)
		expect(state.lastUpdatedAt).toBe(10)
		expect(state.meters[1].progress).toBe(50)
		ContestState.SetOccupants(state, 10, {})
		ContestState.SetOccupants(state, 11, { [1] = true })
		expect(state.expireAt).toBe(240)
		expect(state.meters[1].progress).toBe(45)
	end)
end)

describe("ContestState expiry and overtime", function()
	it(
		"defers empty expiry until finalization and never permits later arrivals to revive it",
		function()
			local state = newContest()
			local candidates = ContestState.SetOccupants(state, 241, { [1] = true })
			expect(#candidates).toBe(0)
			expect(state.pendingEndAt).toBe(240)
			expect(state.phase).toBe("ACTIVE")
			expect(state.meters[1]).toBeNil()
			ContestState.SetOccupants(state, 242, { [2] = true })
			expect(state.meters[2]).toBeNil()
			ContestState.Finalize(state)
			expect(state.phase).toBe("ENDED")
			expect(state.endedAt).toBe(240)
			expect(#ContestState.SetOccupants(state, 300, { [1] = true })).toBe(0)
			expect(ContestState.AcceptWinner(state, 1)).toBe(false)
		end
	)

	it("lets an exactly-at-deadline arrival keep the ring occupied", function()
		local state = newContest()
		ContestState.SetOccupants(state, 240, { [1] = true })
		expect(state.phase).toBe("OVERTIME")
		expect(state.pendingEndAt).toBeNil()
		expect(state.meters[1].progress).toBe(0)
	end)

	it("allows a boundary completion before finalizing an empty-ring end", function()
		local state = newContest(20)
		ContestState.SetOccupants(state, 0, { [1] = true })
		local candidates = ContestState.SetOccupants(state, 20, {})
		expect(#candidates).toBe(1)
		expect(candidates[1].completionAt).toBe(20)
		expect(state.pendingEndAt).toBe(20)
		expect(ContestState.AcceptWinner(state, 1)).toBe(true)
		ContestState.Finalize(state)
		expect(state.phase).toBe("ENDED")
		expect(state.winnerUserId).toBe(1)
		expect(state.endedAt).toBe(20)
		expect(ContestState.AcceptWinner(state, 1)).toBe(false)
		local remainingMeter = next(state.meters)
		expect(remainingMeter).toBeNil()
	end)

	it("keeps overtime open with a full-inventory occupant and permits later entrants", function()
		local state = newContest(10)
		ContestState.SetOccupants(state, 0, { [1] = false })
		ContestState.Advance(state, 10)
		ContestState.Finalize(state)
		expect(state.phase).toBe("OVERTIME")
		expect(state.meters[1]).toBeNil()
		ContestState.SetOccupants(state, 500, { [1] = false, [2] = true })
		local candidates = ContestState.Advance(state, 520)
		expect(#candidates).toBe(1)
		expect(candidates[1].userId).toBe(2)
		expect(candidates[1].completionAt).toBe(520)
		expect(state.expireAt).toBe(10)
	end)

	it("settles a completion at the last overtime departure before ending", function()
		local state = newContest(5)
		ContestState.SetOccupants(state, 0, { [1] = true })
		ContestState.Advance(state, 5)
		expect(state.phase).toBe("OVERTIME")
		local candidates = ContestState.SetOccupants(state, 20, {})
		expect(candidates[1].completionAt).toBe(20)
		expect(state.pendingEndAt).toBe(20)
		expect(ContestState.AcceptWinner(state, 1)).toBe(true)
		expect(state.winnerUserId).toBe(1)
	end)

	it("ends empty overtime without waiting for remaining outside progress to decay", function()
		local state = newContest(5)
		ContestState.SetOccupants(state, 0, { [1] = true })
		ContestState.Advance(state, 5)
		expect(#ContestState.SetOccupants(state, 8, {})).toBe(0)
		expect(state.meters[1].progress).toBe(40)
		expect(state.pendingEndAt).toBe(8)
		ContestState.Finalize(state)
		expect(state.phase).toBe("ENDED")
		expect(state.endedAt).toBe(8)
		local remainingMeter = next(state.meters)
		expect(remainingMeter).toBeNil()
		expect(#ContestState.SetOccupants(state, 9, { [1] = true })).toBe(0)
	end)
end)

describe("ContestState eligibility and removal", function()
	it("clears full-inventory progress immediately while retaining overtime occupancy", function()
		local state = newContest(10)
		ContestState.SetOccupants(state, 0, { [1] = true })
		ContestState.SetOccupants(state, 10, { [1] = false })
		expect(state.meters[1]).toBeNil()
		expect(state.occupants[1]).toBe(false)
		expect(state.phase).toBe("OVERTIME")
		ContestState.SetOccupants(state, 15, { [1] = true })
		expect(state.meters[1].progress).toBe(0)
		expect(ContestState.Advance(state, 35)[1].completionAt).toBe(35)
	end)

	it(
		"does not offer a completion for a player who became ineligible in the current sample",
		function()
			local state = newContest()
			ContestState.SetOccupants(state, 0, { [1] = true, [2] = true })
			local candidates = ContestState.SetOccupants(state, 20, { [1] = false, [2] = true })
			expect(#candidates).toBe(1)
			expect(candidates[1].userId).toBe(2)
			expect(ContestState.AcceptWinner(state, 1)).toBe(false)
		end
	)

	it(
		"can reject the first candidate at award recheck and accept the next exactly once",
		function()
			local state = newContest()
			ContestState.SetOccupants(state, 0, { [1] = true, [2] = true })
			local candidates = ContestState.Advance(state, 20)
			expect(candidates[1].userId).toBe(1)
			expect(ContestState.AcceptWinner(state, 2)).toBe(false)
			ContestState.RejectCandidate(state, 1)
			expect(state.occupants[1]).toBe(false)
			expect(state.meters[1]).toBeNil()
			expect(ContestState.AcceptWinner(state, 1)).toBe(false)
			expect(ContestState.AcceptWinner(state, candidates[2].userId)).toBe(true)
			expect(ContestState.AcceptWinner(state, candidates[2].userId)).toBe(false)
			expect(state.winnerUserId).toBe(2)
		end
	)

	it(
		"keeps a rejected candidate present but unable to progress until eligibility is restored",
		function()
			local state = newContest(10)
			ContestState.SetOccupants(state, 0, { [1] = true })
			ContestState.Advance(state, 20)
			ContestState.RejectCandidate(state, 1)
			ContestState.Finalize(state)
			expect(#ContestState.Advance(state, 40)).toBe(0)
			expect(state.phase).toBe("OVERTIME")
			expect(state.meters[1]).toBeNil()
			ContestState.SetOccupants(state, 40, { [1] = true })
			expect(ContestState.Advance(state, 60)[1].completionAt).toBe(60)
		end
	)

	it(
		"clears reset or disconnected players before settlement while other players can finish",
		function()
			local state = newContest(10)
			ContestState.SetOccupants(state, 0, { [1] = true, [2] = true })
			local candidates = ContestState.RemovePlayer(state, 20, 1)
			expect(#candidates).toBe(1)
			expect(candidates[1].userId).toBe(2)
			expect(state.meters[1]).toBeNil()
			expect(state.occupants[1]).toBeNil()
			expect(ContestState.AcceptWinner(state, 1)).toBe(false)
			expect(ContestState.AcceptWinner(state, 2)).toBe(true)
		end
	)

	it("ends a sole occupant's overtime on reset without granting its completed meter", function()
		local state = newContest(10)
		ContestState.SetOccupants(state, 0, { [1] = true })
		expect(#ContestState.RemovePlayer(state, 20, 1)).toBe(0)
		expect(state.pendingEndAt).toBe(20)
		ContestState.Finalize(state)
		expect(state.endedAt).toBe(20)
		expect(state.winnerUserId).toBeNil()
	end)

	it("does not retain or mutate the caller's occupancy snapshot", function()
		local occupants = { [1] = true }
		local state = newContest()
		ContestState.SetOccupants(state, 0, occupants)
		occupants[1] = false
		expect(state.occupants[1]).toBe(true)
		ContestState.RejectCandidate(state, 1)
		expect(occupants[1]).toBe(false)
	end)
end)

describe("ContestState.Contains", function()
	it(
		"includes standing and normal jumps within horizontal bounds without a ground test",
		function()
			expect(ContestState.Contains(13, 103, 24, 10, 100, 20, 5, 8)).toBe(true)
			expect(ContestState.Contains(13, 108, 24, 10, 100, 20, 5, 8)).toBe(true)
			expect(ContestState.Contains(10, 92, 20, 10, 100, 20, 5, 8)).toBe(true)
		end
	)

	it("rejects crossing either bound and nonfinite positions", function()
		expect(ContestState.Contains(15.01, 103, 20, 10, 100, 20, 5, 8)).toBe(false)
		expect(ContestState.Contains(10, 108.01, 20, 10, 100, 20, 5, 8)).toBe(false)
		expect(ContestState.Contains(10, 91.99, 20, 10, 100, 20, 5, 8)).toBe(false)
		expect(ContestState.Contains(math.huge, 100, 20, 10, 100, 20, 5, 8)).toBe(false)
	end)

	it(
		"preserves one uninterrupted visit through eligible jumps but ends it at the edge",
		function()
			local state = newContest()
			ContestState.SetOccupants(state, 0, { [1] = true })
			local originalVisit = state.meters[1].visitOrder
			local airborne = ContestState.Contains(0, 8, 0, 0, 0, 0, 5, 8)
			ContestState.SetOccupants(state, 5, if airborne then { [1] = true } else {})
			expect(state.meters[1].progress).toBe(25)
			expect(state.meters[1].visitOrder).toBe(originalVisit)
			local beyondEdge = ContestState.Contains(5.01, 8, 0, 0, 0, 0, 5, 8)
			ContestState.SetOccupants(state, 5, if beyondEdge then { [1] = true } else {})
			ContestState.Advance(state, 6)
			expect(state.meters[1].progress).toBe(20)
			ContestState.SetOccupants(state, 6, { [1] = true })
			expect(state.meters[1].visitOrder).never.toBe(originalVisit)
		end
	)
end)
