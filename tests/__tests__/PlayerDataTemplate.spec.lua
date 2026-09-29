--!strict
-- ServerStorage/Tests/__tests__/PlayerDataTemplate.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local PlayerDataTemplate = require(game:GetService("ServerStorage").Databases.PlayerDataTemplate)
local Configuration = require(game:GetService("ReplicatedStorage").Shared.Configurations.PlayerData)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("PlayerDataTemplate", function()
	it("starts the configured fresh schema with Gold and no legacy Runies field", function()
		expect(PlayerDataTemplate.version).toBe(Configuration.schemaVersion)
		expect(PlayerDataTemplate.currency.gold).toBe(Configuration.startingGold)
		for key in pairs(PlayerDataTemplate.currency) do
			expect(key).never.toBe("runies")
		end
	end)

	it("leaves one-time Equipment and loadout grants out of recurring reconciliation", function()
		expect(PlayerDataTemplate.equipment).toEqual({})
		expect(PlayerDataTemplate.combatLoadout).toEqual({})
	end)

	it("defers the per-profile production clock until the load boundary", function()
		expect(Configuration.schemaVersion).toBe(7)
		expect(PlayerDataTemplate.productionClock).toBeNil()
		expect(PlayerDataTemplate.base.shrines).toEqual({})
		expect(PlayerDataTemplate.profile.userId).toBe(0)
		expect(PlayerDataTemplate.profile.createdAt).toBe(0)
		expect(PlayerDataTemplate.profile.lastLoginAt).toBe(0)
	end)
end)
