--!strict
-- ServerStorage/Tests/__tests__/InventoryEquipmentSale.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Trove = require(ReplicatedStorage.Packages.Trove)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local playerUtilModule = ServerScriptService.Infrastructure.PlayerUtil
local cleanup: { () -> () } = {}
type Service = ServerTypes.InventoryApi & {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
}

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(playerUtilModule)
end)

describe("InventoryService SellEquipment facade", function()
	it(
		"requires a running service and genuine Player while owning observer cleanup exactly once",
		function()
			local reads, transactions, observers, retired = 0, 0, 0, 0
			jest.mock(playerUtilModule, function()
				return {
					-- Observe lifetime ownership without dispatching or manufacturing engine Players.
					OnPlayer = function(_callback: unknown, owner: Trove.Trove)
						observers += 1
						owner:Add(function()
							retired += 1
						end)
					end,
				}
			end)
			local service: Service? = nil
			jest.isolateModules(function()
				local loadService = require :: (ModuleScript) -> Service
				service = loadService(ServerScriptService.Services.InventoryService)
			end)
			local api = assert(service, "[InventoryEquipmentSale.spec] Expected isolated service")
			local remote = Instance.new("RemoteFunction")
			local nonPlayer = Instance.new("Folder")
			table.insert(cleanup, function()
				remote:Destroy()
				nonPlayer:Destroy()
			end)
			local initialized = false
			table.insert(cleanup, function()
				if initialized then
					api.Stop()
				end
			end)
			local request: Types.SellEquipmentRequest = {
				requestId = "0:sell",
				expectedRevision = 0,
				instanceId = "owned_sword",
				expectedDefinitionId = "elemental_sword",
				expectedFinishId = "fire",
				expectedGold = 25,
			}
			local function expectUnavailable()
				for _, value in { { UserId = 1001, Parent = Players }, nonPlayer, false } do
					expect(api.SellEquipment((value :: unknown) :: Player, request)).toEqual({
						ok = false,
						code = "DataUnavailable",
						revision = 0,
					})
				end
				expect(reads).toBe(0)
				expect(transactions).toBe(0)
			end
			local source = {
				GetLoadedData = function(_player: Player): Types.PlayerDoc?
					reads += 1
					return nil
				end,
				Transact = function(): Types.TransactionResult
					transactions += 1
					return { ok = false, code = "DataUnavailable", revision = 0 }
				end,
				Update = function(): Types.TransactionResult
					transactions += 1
					return { ok = false, code = "DataUnavailable", revision = 0 }
				end,
			}
			expectUnavailable()
			api.Init(({
				Services = { DataService = source, BaseService = {} },
				Remotes = { Inventory = { DeleteMythling = remote } },
			} :: unknown) :: ServerTypes.Context)
			initialized = true
			expectUnavailable()
			expect(observers).toBe(0)
			api.Start()
			api.Start()
			expect(observers).toBe(1)
			expectUnavailable()
			api.Stop()
			api.Stop()
			expect(retired).toBe(1)
			expectUnavailable()
			expect(function()
				api.Start()
			end).toThrow()
		end
	)
end)
