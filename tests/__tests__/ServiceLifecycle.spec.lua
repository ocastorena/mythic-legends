--!strict
-- ServerStorage/Tests/__tests__/ServiceLifecycle.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local ServiceLifecycle =
	require(game:GetService("ServerScriptService").Infrastructure.ServiceLifecycle)
local describe, expect, it = JestGlobals.describe, JestGlobals.expect, JestGlobals.it

describe("ServiceLifecycle", function()
	it("starts once, releases owned resources once, and rejects a terminal restart", function()
		local lifecycle = ServiceLifecycle.new("FixtureService")
		local cleanupCount = 0
		local instance = Instance.new("Folder")
		local parent = Instance.new("Folder")
		instance.Parent = parent
		lifecycle.trove:Add(instance)
		lifecycle.trove:Add(function()
			cleanupCount += 1
		end)
		expect(lifecycle:Start()).toBe(true)
		expect(lifecycle:Start()).toBe(false)
		expect(lifecycle:IsRunning()).toBe(true)
		expect(lifecycle:Stop()).toBe(true)
		expect(lifecycle:Stop()).toBe(false)
		expect(lifecycle:IsRunning()).toBe(false)
		expect(cleanupCount).toBe(1)
		expect(instance.Parent).toBeNil()
		expect(function()
			lifecycle:Start()
		end).toThrow()
		parent:Destroy()
	end)

	it(
		"disconnects listeners and cancels deferred work before it can revive stopped state",
		function()
			local lifecycle = ServiceLifecycle.new("FixtureService")
			local signal = Instance.new("BindableEvent")
			local didRun = false
			lifecycle:Start()
			local connection = signal.Event:Connect(function()
				didRun = true
			end)
			lifecycle.trove:Add(connection)
			lifecycle.trove:Add(task.defer(function()
				didRun = true
			end))
			lifecycle:Stop()
			signal:Fire()
			task.wait()
			expect(connection.Connected).toBe(false)
			expect(didRun).toBe(false)
			signal:Destroy()
		end
	)

	it("cleans an initialized lifetime even if startup never ran", function()
		local lifecycle = ServiceLifecycle.new("FixtureService")
		local cleaned = false
		lifecycle.trove:Add(function()
			cleaned = true
		end)
		expect(lifecycle:Stop()).toBe(true)
		expect(cleaned).toBe(true)
		expect(function()
			lifecycle:Start()
		end).toThrow()
	end)
end)
