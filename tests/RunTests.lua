--!strict
-- ServerStorage/Tests/RunTests
-- External entry point for the disposable Studio CLI test place.

local PASS_MARKER = "MYTHIC_LEGENDS_TESTS:PASS"
local FAIL_MARKER = "MYTHIC_LEGENDS_TESTS:FAIL"

type TestSummary = {
	numTotalTestSuites: number,
	numPassedTestSuites: number,
	numFailedTestSuites: number,
	numTotalTests: number,
	numPassedTests: number,
	numFailedTests: number,
	numPendingTests: number,
}

local function traceError(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local succeeded, result = xpcall(function(): TestSummary
	local TestRunner = require(game:GetService("ServerStorage").Tests.TestRunner)
	return TestRunner.Run()
end, traceError)

if not succeeded then
	print(string.format("%s %s", FAIL_MARKER, tostring(result)))
	return
end

local summary = result :: TestSummary
print(
	string.format(
		"%s %d/%d tests passed across %d/%d suites",
		PASS_MARKER,
		summary.numPassedTests,
		summary.numTotalTests,
		summary.numPassedTestSuites,
		summary.numTotalTestSuites
	)
)
