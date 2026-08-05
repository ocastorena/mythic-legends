--!strict
-- ServerStorage/Tests/__tests__/PlayerDataTemplate.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local PlayerDataTemplate = require(game:GetService("ServerStorage").Databases.PlayerDataTemplate)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

describe("PlayerDataTemplate", function()
	it("starts the v2 schema with Gold and no legacy Runies field", function()
		expect(PlayerDataTemplate.version).toBe(2)
		expect(PlayerDataTemplate.currency.gold).toBe(0)
		expect(PlayerDataTemplate.currency.runies).toBeNil()
	end)

	it("keeps starter equipment references internally consistent", function()
		local loadout = PlayerDataTemplate.combatLoadout
		expect(PlayerDataTemplate.equipment[loadout.primaryWeaponInstanceId]).never.toBeNil()
		expect(PlayerDataTemplate.equipment[loadout.shieldInstanceId]).never.toBeNil()
	end)
end)
