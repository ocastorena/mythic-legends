--!strict
-- ServerStorage/Tests/__tests__/SubscriptionList.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local SubscriptionList =
	require(game:GetService("StarterPlayer").StarterPlayerScripts.UI.State.SubscriptionList)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local function newChannel(): SubscriptionList.Channel<string>
	return (SubscriptionList.new :: (string) -> SubscriptionList.Channel<string>)(
		"SubscriptionList"
	)
end

describe("SubscriptionList", function()
	it("owns duplicate registrations independently and unsubscribes idempotently", function()
		local channel = newChannel()
		local values: { string } = {}
		local function listener(value: string)
			table.insert(values, value)
		end
		local first = channel.Subscribe(listener)
		local second = channel.Subscribe(listener)
		expect(#values).toBe(0)
		channel.Publish("both")
		first()
		first()
		channel.Publish("second")
		second()
		channel.Publish("neither")
		expect(values).toEqual({ "both", "both", "second" })
	end)

	it("skips a listener removed before its turn in the same publication", function()
		local channel = newChannel()
		local values: { string } = {}
		local unsubscribeSecond: () -> () = function() end
		channel.Subscribe(function(value)
			table.insert(values, value)
			unsubscribeSecond()
		end)
		unsubscribeSecond = channel.Subscribe(function()
			table.insert(values, "removed listener")
		end)
		channel.Publish("first")
		expect(values).toEqual({ "first" })
	end)

	it("delivers subscriptions added during publication beginning with the next event", function()
		local channel = newChannel()
		local values: { string } = {}
		local didAdd = false
		channel.Subscribe(function()
			if didAdd then
				return
			end
			didAdd = true
			channel.Subscribe(function(value)
				table.insert(values, value)
			end)
		end)
		channel.Publish("before registration")
		channel.Publish("after registration")
		expect(values).toEqual({ "after registration" })
	end)

	it("isolates a failing callback from later listeners", function()
		local channel = newChannel()
		local received: string? = nil
		channel.Subscribe(function()
			error("intentional listener failure")
		end)
		channel.Subscribe(function(value)
			received = value
		end)
		channel.Publish("still delivered")
		expect(received).toBe("still delivered")
	end)
end)
