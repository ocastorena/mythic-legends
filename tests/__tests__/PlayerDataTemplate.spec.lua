--!strict
-- ServerStorage/Tests/__tests__/PlayerDataTemplate.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local PlayerDataTemplate = require(game:GetService("ServerStorage").Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("PlayerDataTemplate", function()
	it("starts the v3 schema with Gold and no legacy Runies field", function()
		expect(PlayerDataTemplate.version).toBe(3)
		expect(PlayerDataTemplate.currency.gold).toBe(0)
		for key in pairs(PlayerDataTemplate.currency) do
			expect(key).never.toBe("runies")
		end
	end)

	it("keeps starter equipment references internally consistent", function()
		local loadout = PlayerDataTemplate.combatLoadout
		local ownedIds: { string } = {}
		for instanceId in pairs(PlayerDataTemplate.equipment) do
			table.insert(ownedIds, instanceId)
		end
		expect(ownedIds).toContain(loadout.primaryWeaponInstanceId)
		expect(ownedIds).toContain(loadout.shieldInstanceId)
	end)
end)
