--!strict
-- ServerStorage/Tests/__tests__/ShrineAssignments.spec

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local FreezeUtil = require(ReplicatedStorage.Shared.FreezeUtil)
local ShrineAssignments = require(ServerScriptService.Services.BaseService.ShrineAssignments)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local ELEMENTS = { "fire", "water", "earth", "air", "light", "dark" }

local function copy<T>(value: T): T
	return (HttpService:JSONDecode(HttpService:JSONEncode(value)) :: unknown) :: T
end

local function metadata(): ShrineAssignments.Metadata
	local definitions: ShrineAssignments.Metadata = { forms = {}, shrines = {} }
	for _, elementId in ELEMENTS do
		local displayElement = string.upper(string.sub(elementId, 1, 1)) .. string.sub(elementId, 2)
		definitions.forms[`test_{elementId}_form`] = {
			element = displayElement,
			baseYieldPerHour = 3_600,
		}
		definitions.shrines[`test_{elementId}_shrine`] = {
			element = displayElement,
			materialId = `test_{elementId}_material`,
			levels = {
				[1] = { capacity = 10, workerSlots = 1 },
				[2] = { capacity = 20, workerSlots = 2 },
				[3] = { capacity = 30, workerSlots = 3 },
			},
		}
	end
	return definitions
end

local function state(): ShrineAssignments.State
	local result: ShrineAssignments.State = {
		lastAccruedAt = 0,
		nextBatchAt = 1,
		shrines = {},
		workers = {},
	}
	for _, elementId in ELEMENTS do
		result.shrines[`shrine_{elementId}`] = {
			shrineId = `test_{elementId}_shrine`,
			level = 1,
			workerIdsBySlot = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}
		result.workers[`worker_{elementId}`] = {
			formId = `test_{elementId}_form`,
			level = 1,
			xp = 0,
			pendingXp = 0,
		}
	end
	result.workers.worker_fire_two = {
		formId = "test_fire_form",
		level = 1,
		xp = 0,
		pendingXp = 0,
	}
	return result
end

local function assign(
	input: ShrineAssignments.State,
	now: number,
	request: ShrineAssignments.AssignRequest,
	definitions: ShrineAssignments.Metadata?
): ShrineAssignments.State
	local result, assignmentError =
		ShrineAssignments.Assign(input, now, request, definitions or metadata())
	assert(result, `[ShrineAssignments.spec] Expected Assign success: {tostring(assignmentError)}`)
	expect(assignmentError).toBeNil()
	return result
end

local function remove(
	input: ShrineAssignments.State,
	now: number,
	request: ShrineAssignments.RemoveRequest,
	definitions: ShrineAssignments.Metadata?
): ShrineAssignments.State
	local result, assignmentError =
		ShrineAssignments.Remove(input, now, request, definitions or metadata())
	assert(result, `[ShrineAssignments.spec] Expected Remove success: {tostring(assignmentError)}`)
	expect(assignmentError).toBeNil()
	return result
end

local function expectAssignRejected(
	input: ShrineAssignments.State,
	now: number,
	request: any,
	expectedCode: string,
	definitions: ShrineAssignments.Metadata?
)
	local before = copy(input)
	local result, assignmentError =
		ShrineAssignments.Assign(input, now, request, definitions or metadata())
	expect(result).toBeNil()
	expect(assignmentError).toBe(expectedCode)
	expect(input).toEqual(before)
end

local function expectRemoveRejected(
	input: ShrineAssignments.State,
	now: number,
	request: any,
	expectedCode: string,
	definitions: ShrineAssignments.Metadata?
)
	local before = copy(input)
	local result, assignmentError =
		ShrineAssignments.Remove(input, now, request, definitions or metadata())
	expect(result).toBeNil()
	expect(assignmentError).toBe(expectedCode)
	expect(input).toEqual(before)
end

describe("ShrineAssignments", function()
	it("assigns matching owned workers for all six elements into canonical slot keys", function()
		local result = state()
		for _, elementId in ELEMENTS do
			result = assign(result, 0, {
				workerId = `worker_{elementId}`,
				shrineInstanceId = `shrine_{elementId}`,
				slotId = 1,
			})
		end

		for _, elementId in ELEMENTS do
			local shrine = result.shrines[`shrine_{elementId}`]
			expect(shrine.workerIdsBySlot).toEqual({ ["1"] = `worker_{elementId}` })
		end
		expect(result.lastAccruedAt).toBe(0)
		expect(result.nextBatchAt).toBe(1)
	end)

	it("rejects missing ownership and mismatched elements without changing state", function()
		local input = state()
		expectAssignRejected(input, 0, {
			workerId = "missing_worker",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
		}, "WorkerNotOwned")
		expectAssignRejected(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "missing_shrine",
			slotId = 1,
		}, "ShrineNotOwned")
		expectAssignRejected(input, 0, {
			workerId = "worker_water",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
		}, "ElementMismatch")
	end)

	it("rejects locked, fractional, and noncanonical slots from Shrine metadata", function()
		local input = state()
		expectAssignRejected(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = 2,
		}, "InvalidSlot")
		for _, slotId in { 0, 1.5, -1, math.huge, 0 / 0 } do
			expectAssignRejected(input, 0, {
				workerId = "worker_fire",
				shrineInstanceId = "shrine_fire",
				slotId = slotId,
			}, "InvalidRequest")
		end
		expectAssignRejected(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = "1",
		}, "InvalidRequest")

		input.shrines.shrine_fire.level = 2
		input.shrines.shrine_fire.workerIdsBySlot["2"] = "worker_fire_two"
		local result = assign(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
		})
		expect(result.shrines.shrine_fire.workerIdsBySlot).toEqual({
			["1"] = "worker_fire",
			["2"] = "worker_fire_two",
		})
	end)

	it("never replaces occupied slots or implicitly moves an assigned worker", function()
		local input = state()
		input.shrines.shrine_fire.level = 2
		input.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		expectAssignRejected(input, 0, {
			workerId = "worker_fire_two",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
		}, "SlotOccupied")
		expectAssignRejected(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
		}, "WorkerAlreadyAssigned")
		expectAssignRejected(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = 2,
		}, "WorkerAlreadyAssigned")
	end)

	it("removes only the exact expected worker and preserves stable slot holes", function()
		local input = state()
		input.shrines.shrine_fire.level = 2
		input.shrines.shrine_fire.workerIdsBySlot = {
			["1"] = "worker_fire",
			["2"] = "worker_fire_two",
		}
		-- A stale expectation must fail before settling even though ten seconds are due.
		expectRemoveRejected(input, 10, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire_two",
		}, "AssignmentChanged")

		local result = remove(input, 0, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		})
		expect(result.shrines.shrine_fire.workerIdsBySlot).toEqual({
			["2"] = "worker_fire_two",
		})
		expectRemoveRejected(result, 0, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}, "AssignmentChanged")
		expectRemoveRejected(result, 0, {
			shrineInstanceId = "missing_shrine",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}, "ShrineNotOwned")
		expectRemoveRejected(result, 0, {
			shrineInstanceId = "shrine_water",
			slotId = 2,
			expectedWorkerId = "worker_water",
		}, "InvalidSlot")
	end)

	it("settles the entire profile before assigning without backdating the new worker", function()
		local input = state()
		input.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"

		local result = assign(input, 1, {
			workerId = "worker_water",
			shrineInstanceId = "shrine_water",
			slotId = 1,
		})

		expect(result.shrines.shrine_fire.stored).toBe(1)
		expect(result.workers.worker_fire.xp).toBe(1)
		expect(result.shrines.shrine_water.stored).toBe(0)
		expect(result.shrines.shrine_water.newWork).toBe(0)
		expect(result.workers.worker_water.xp).toBe(0)
		expect(result.workers.worker_water.pendingXp).toBe(0)
		expect(result.shrines.shrine_water.workerIdsBySlot["1"]).toBe("worker_water")
		expect(result.lastAccruedAt).toBe(1)
		expect(result.nextBatchAt).toBe(2)
	end)

	it("requires removal before a move and settles the midpoint exactly once", function()
		local input = state()
		input.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		input.shrines.destination = {
			shrineId = "test_fire_shrine",
			level = 1,
			workerIdsBySlot = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}
		expectAssignRejected(input, 0.5, {
			workerId = "worker_fire",
			shrineInstanceId = "destination",
			slotId = 1,
		}, "WorkerAlreadyAssigned")

		local unassigned = remove(input, 0.5, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		})
		expect(unassigned.shrines.shrine_fire.newWork).toBeCloseTo(0.5)
		expect(unassigned.workers.worker_fire.pendingXp).toBeCloseTo(0.5)
		local moved = assign(unassigned, 0.5, {
			workerId = "worker_fire",
			shrineInstanceId = "destination",
			slotId = 1,
		})
		expect(moved.shrines.shrine_fire.newWork).toBeCloseTo(0.5)
		expect(moved.workers.worker_fire.pendingXp).toBeCloseTo(0.5)

		local resolved = remove(moved, 1, {
			shrineInstanceId = "destination",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		})
		expect(resolved.shrines.shrine_fire.progress).toBeCloseTo(0.5)
		expect(resolved.shrines.destination.progress).toBeCloseTo(0.5)
		expect(resolved.shrines.shrine_fire.newWork).toBe(0)
		expect(resolved.shrines.destination.newWork).toBe(0)
		expect(resolved.workers.worker_fire.xp).toBe(1)
		expect(resolved.workers.worker_fire.pendingXp).toBe(0)
	end)

	it("does not catch up full-source time after removal and reassignment", function()
		local input = state()
		input.shrines.shrine_fire.stored = 10
		input.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		input.shrines.destination = {
			shrineId = "test_fire_shrine",
			level = 1,
			workerIdsBySlot = {},
			stored = 0,
			progress = 0,
			newWork = 0,
		}

		local unassigned = remove(input, 10, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		})
		expect(unassigned.workers.worker_fire.xp).toBe(0)
		local reassigned = assign(unassigned, 10, {
			workerId = "worker_fire",
			shrineInstanceId = "destination",
			slotId = 1,
		})
		local afterOneWorkingSecond = remove(reassigned, 11, {
			shrineInstanceId = "destination",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		})

		expect(afterOneWorkingSecond.shrines.shrine_fire.stored).toBe(10)
		expect(afterOneWorkingSecond.shrines.destination.stored).toBe(1)
		expect(afterOneWorkingSecond.workers.worker_fire.xp).toBe(1)
	end)

	it("rejects backdated changes instead of applying them to an older snapshot", function()
		local input = state()
		input.lastAccruedAt = 10
		input.nextBatchAt = 11
		input.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		expectAssignRejected(input, 9, {
			workerId = "worker_water",
			shrineInstanceId = "shrine_water",
			slotId = 1,
		}, "BackdatedChange")
		expectRemoveRejected(input, 9, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}, "BackdatedChange")
	end)

	it("rejects duplicate saved assignments before any command mutation", function()
		local input = state()
		input.shrines.shrine_fire.workerIdsBySlot["1"] = "worker_fire"
		input.shrines.duplicate = {
			shrineId = "test_fire_shrine",
			level = 1,
			workerIdsBySlot = { ["1"] = "worker_fire" },
			stored = 0,
			progress = 0,
			newWork = 0,
		}
		expectAssignRejected(input, 0, {
			workerId = "worker_water",
			shrineInstanceId = "shrine_water",
			slotId = 1,
		}, "InvalidAssignment")
		expectRemoveRejected(input, 0, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}, "InvalidAssignment")
	end)

	it("rejects malformed requests without changing the input", function()
		local input = state()
		expectAssignRejected(input, 0, nil, "InvalidRequest")
		expectAssignRejected(input, 0, "assign", "InvalidRequest")
		expectAssignRejected(input, 0, {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			extra = true,
		}, "InvalidRequest")
		expectRemoveRejected(input, 0, nil, "InvalidRequest")
		expectRemoveRejected(input, 0, "remove", "InvalidRequest")
		expectRemoveRejected(input, 0, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
			extra = true,
		}, "InvalidRequest")
	end)

	it("repeated commands cannot add output or change assignments twice", function()
		local input = state()
		local request: ShrineAssignments.AssignRequest = {
			workerId = "worker_fire",
			shrineInstanceId = "shrine_fire",
			slotId = 1,
		}
		local assigned = assign(input, 0.5, request)
		expectAssignRejected(assigned, 0.5, request, "WorkerAlreadyAssigned")
		local removed = remove(assigned, 1, {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		})
		expect(removed.shrines.shrine_fire.progress).toBeCloseTo(0.5)
		expect(removed.workers.worker_fire.xp).toBeCloseTo(0.5)
		local removeRequest: ShrineAssignments.RemoveRequest = {
			shrineInstanceId = "shrine_fire",
			slotId = 1,
			expectedWorkerId = "worker_fire",
		}
		expectRemoveRejected(removed, 1, removeRequest, "AssignmentChanged")
	end)

	it(
		"accepts frozen pure state and returns a detached JSON-safe record with no extras",
		function()
			local input = state()
			local definitions = metadata()
			local inputBefore = copy(input)
			local metadataBefore = copy(definitions)
			FreezeUtil.DeepFreeze(input)
			FreezeUtil.DeepFreeze(definitions)

			local result = assign(input, 0, {
				workerId = "worker_fire",
				shrineInstanceId = "shrine_fire",
				slotId = 1,
			}, definitions)

			expect(input).toEqual(inputBefore)
			expect(definitions).toEqual(metadataBefore)
			expect(result).never.toBe(input)
			expect(result.shrines).never.toBe(input.shrines)
			expect(result.workers).never.toBe(input.workers)
			expect(result.shrines.shrine_fire).never.toBe(input.shrines.shrine_fire)
			expect(result.workers.worker_fire).never.toBe(input.workers.worker_fire)
			expect(HttpService:JSONDecode(HttpService:JSONEncode(result))).toEqual(result)

			local dynamicResult = (result :: unknown) :: { [string]: any }
			local dynamicShrine = (result.shrines.shrine_fire :: unknown) :: { [string]: any }
			expect(dynamicResult.stands).toBeNil()
			expect(dynamicResult.craftingStation).toBeNil()
			expect(dynamicShrine.workerIds).toBeNil()
			expect(dynamicShrine.assignedWorkerId).toBeNil()
			expect(dynamicShrine.prototypeStandId).toBeNil()
		end
	)
end)
