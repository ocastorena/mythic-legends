--!strict
-- ServerStorage/Tests/TestRunner
-- Manual Studio entry point: require(game.ServerStorage.Tests.TestRunner).Run()

local Jest = require(script.Parent.DevPackages.Jest)

local TestRunner = {}

export type TestSummary = {
	numTotalTestSuites: number,
	numPassedTestSuites: number,
	numFailedTestSuites: number,
	numTotalTests: number,
	numPassedTests: number,
	numFailedTests: number,
	numPendingTests: number,
}

function TestRunner.Run(): TestSummary
	local status, result = Jest.runCLI(script.Parent, {
		ci = false,
		verbose = true,
	}, { script.Parent }):awaitStatus()

	if status == "Rejected" then
		error(string.format("Jest Roblox failed to run: %s", tostring(result)), 2)
	end

	-- Jest's promise boundary is dynamic; expose the runner's stable summary contract.
	local results: TestSummary = result.results
	if results.numFailedTestSuites > 0 or results.numFailedTests > 0 then
		error(
			string.format(
				"Jest Roblox failed: %d suite(s), %d test(s)",
				results.numFailedTestSuites,
				results.numFailedTests
			),
			2
		)
	end

	return results
end

return table.freeze(TestRunner)
