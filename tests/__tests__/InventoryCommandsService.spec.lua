--!strict
-- ServerStorage/Tests/__tests__/InventoryCommandsService.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local cleanup: { () -> () } = {}

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
end)

describe("InventoryService canonical command gates", function()
	it("rejects stopped services and non-Player callers before accessing profiles", function()
		local root = Instance.new("Folder")
		root.Name = "InventoryCommandsServiceFixture"
		root.Parent = script.Parent
		table.insert(cleanup, function()
			root:Destroy()
		end)
		local module = ServerScriptService.Services.InventoryService:Clone()
		module.Parent = root
		-- Localized dynamic require isolates singleton lifecycle and its private children.
		local loadService = require :: (ModuleScript) -> any
		local service = loadService(module)
		local reads, transactions = 0, 0
		local fakePlayer = { UserId = 1001, Parent = Players }
		local evolve: Types.EvolveMythlingRequest = {
			requestId = "0:evolve",
			expectedRevision = 0,
			workerId = "owned_worker",
			expectedFormId = "mythling_0001",
			expectedTargetFormId = "mythling_0002",
		}
		local sell: Types.SellMythlingRequest = {
			requestId = "0:sell",
			expectedRevision = 0,
			workerId = "owned_worker",
			expectedFormId = "mythling_0001",
			expectedGoldValue = 25,
		}
		local function expectUnavailable(player: unknown)
			local material: Types.DiscardMaterialRequest = {
				requestId = "0:material",
				expectedRevision = 0,
				materialId = "fire_material",
				quantity = 1,
				expectedOwnedQuantity = 1,
			}
			expect(service.DiscardMaterial(player, material)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			local sale = table.clone(material) :: any
			sale.expectedUnitGold = 2
			expect(service.SellMaterial(player, sale)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(service.UpgradeCapacity(player, {
				requestId = "0:upgrade",
				expectedRevision = 0,
				category = "materials",
				expectedUpgradeCount = 0,
				expectedGoldCost = 20_000,
				expectedMaterialQuantity = 50,
			})).toEqual({ ok = false, code = "DataUnavailable", revision = 0 })
			expect(service.EvolveMythling(player, evolve)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(service.SellMythling(player, sell)).toEqual({
				ok = false,
				code = "DataUnavailable",
				revision = 0,
			})
			expect(
				service.SaveWonMythling(player, { typeId = "mythling_0001", variantId = "regular" })
			).toBeNil()
			expect(service.GetMythlingCapacity(player)).toBeNil()
			expect(reads).toBe(0)
			expect(transactions).toBe(0)
		end
		expectUnavailable(fakePlayer)
		local delete = Instance.new("RemoteFunction")
		delete.Parent = root
		service.Init({
			Remotes = { Inventory = { DeleteMythling = delete } },
			Services = {
				BaseService = {},
				DataService = {
					Load = function(): boolean
						return false
					end,
					GetLoadedData = function(): Types.PlayerDoc?
						reads += 1
						return nil
					end,
					Transact = function(): Types.TransactionResult
						transactions += 1
						return { ok = false, code = "UnexpectedTransaction", revision = 0 }
					end,
					Update = function(): Types.TransactionResult
						transactions += 1
						return { ok = false, code = "UnexpectedUpdate", revision = 0 }
					end,
				},
			},
		})
		table.insert(cleanup, function()
			service.Stop()
		end)
		expectUnavailable(fakePlayer)
		service.Start()
		-- CLI cannot create engine Players; a forged Parent field must not impersonate one.
		expectUnavailable(fakePlayer)
		expectUnavailable(nil)
		expectUnavailable(root)
		service.Stop()
		expectUnavailable(fakePlayer)
	end)
end)
