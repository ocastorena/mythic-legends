--!strict
-- ServerStorage/Tests/__tests__/LocalData.spec

local StarterPlayer = game:GetService("StarterPlayer")
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
type Cache = typeof(require(StarterPlayer.StarterPlayerScripts.State.LocalData))

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local afterEach = JestGlobals.afterEach
local fixtures: { { module: ModuleScript, cache: Cache } } = {}

local function newCache(): Cache
	local module = StarterPlayer.StarterPlayerScripts.State.LocalData:Clone()
	-- Each test requires a fresh clone so the application cache is never initialized or destroyed.
	local loadCache = require :: (ModuleScript) -> Cache
	local cache = loadCache(module)
	table.insert(fixtures, { module = module, cache = cache })
	return cache
end

afterEach(function()
	for _, fixture in fixtures do
		fixture.cache.Destroy()
		fixture.module:Destroy()
	end
	table.clear(fixtures)
end)

describe("LocalData", function()
	it("rejects a revision gap and accepts a newer full snapshot without stale rollback", function()
		local cache = newCache()
		local initialized =
			cache.IngestPayload({ revision = 4, full = true, values = { gold = 100 } })
		expect(initialized).toBe(true)
		local accepted, reason = cache.IngestPayload({ revision = 6, values = { gold = 200 } })
		expect(accepted).toBe(false)
		expect(reason).toBe("RevisionGap")
		expect(cache.GetRevision()).toBe(4)
		expect(cache.Peek("gold")).toBe(100)
		local resynchronized =
			cache.IngestPayload({ revision = 6, full = true, values = { gold = 200 } })
		expect(resynchronized).toBe(true)
		cache.IngestPayload({ revision = 5, full = true, values = { gold = 50 } })
		expect(cache.GetRevision()).toBe(6)
		expect(cache.Peek("gold")).toBe(200)
	end)

	it("copies and recursively freezes sections without freezing the incoming payload", function()
		local cache = newCache()
		local equipment = { sword = { quantity = 1 } }
		cache.IngestPayload({ revision = 1, values = { equipment = equipment } })
		local snapshot = cache.Peek("equipment")
		expect(table.isfrozen(snapshot)).toBe(true)
		expect(table.isfrozen(snapshot.sword)).toBe(true)
		equipment.sword.quantity = 2
		expect(snapshot.sword.quantity).toBe(1)
		expect(function()
			snapshot.sword.quantity = 3
		end).toThrow()
	end)

	it("removes omitted full-snapshot sections and explicit delta removals", function()
		local cache = newCache()
		cache.IngestPayload({ revision = 1, values = { gold = 100, equipment = {} } })
		cache.IngestPayload({ revision = 2, full = true, values = { gold = 120 } })
		expect(cache.Peek("equipment")).toBeNil()
		cache.IngestPayload({ revision = 3, values = {}, removed = { "gold" } })
		expect(cache.Peek("gold")).toBeNil()
	end)

	it("ends its lifetime idempotently and rejects late packets", function()
		local cache = newCache()
		cache.IngestPayload({ revision = 1, values = { gold = 100 } })
		local connection = cache.OnStateChanged:Connect(function() end)
		cache.Destroy()
		cache.Destroy()
		expect(connection.Connected).toBe(false)
		local accepted, reason =
			cache.IngestPayload({ revision = 2, full = true, values = { gold = 999 } })
		expect(accepted).toBe(false)
		expect(reason).toBe("Destroyed")
		expect(cache.GetRevision()).toBe(0)
		expect(cache.Peek("gold")).toBeNil()
	end)
end)
