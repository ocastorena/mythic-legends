--!strict
-- ServerStorage/Tests/__tests__/ShrineWorkerService.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Mythlings = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local Types = require(ReplicatedStorage.Shared.Types)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local afterEach = JestGlobals.afterEach

local cleanup: { () -> () } = {}

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
end)

describe("BaseService Shrine command gates", function()
	it("rejects stopped services and non-Player callers without touching profiles", function()
		local root = Instance.new("Folder")
		root.Name = "ShrineWorkerServiceFixture"
		root.Parent = script.Parent
		table.insert(cleanup, function()
			root:Destroy()
		end)
		local module = ServerScriptService.Services.BaseService:Clone()
		module.Parent = root
		-- Localized dynamic require isolates the singleton lifecycle and private children.
		local loadService = require :: (ModuleScript) -> any
		local service = loadService(module)
		local reads, transactions = 0, 0
		local fakePlayer = { UserId = 1001, Parent = Players }
		local assign: Types.AssignShrineWorkerRequest = {
			requestId = "0:assign",
			expectedRevision = 0,
			shrineInstanceId = "owned_shrine",
			slotId = 1,
			workerId = "owned_worker",
		}
		local remove: Types.RemoveShrineWorkerRequest = {
			requestId = "0:remove",
			expectedRevision = 0,
			shrineInstanceId = "owned_shrine",
			slotId = 1,
			expectedWorkerId = "owned_worker",
		}
		local upgrade: Types.UpgradeShrineRequest = {
			requestId = "0:upgrade",
			expectedRevision = 0,
			shrineInstanceId = "owned_shrine",
			expectedLevel = 1,
			expectedMaterialId = "fire_material",
			expectedGoldCost = 1_000,
			expectedMaterialQuantity = 400,
		}
		local dismantle: Types.DismantleShrineRequest = {
			requestId = "0:dismantle",
			expectedRevision = 0,
			shrineInstanceId = "owned_shrine",
			expectedLevel = 1,
		}
		local function expectUnavailable(player: unknown)
			local unavailable = { ok = false, code = "DataUnavailable", revision = 0 }
			expect(service.AssignShrineWorker(player, assign)).toEqual(unavailable)
			expect(service.RemoveShrineWorker(player, remove)).toEqual(unavailable)
			expect(service.UpgradeShrine(player, upgrade)).toEqual(unavailable)
			expect(service.DismantleShrine(player, dismantle)).toEqual(unavailable)
			expect(reads).toBe(0)
			expect(transactions).toBe(0)
		end
		expectUnavailable(fakePlayer)

		local template = Instance.new("Model")
		template.Name = "BaseLevel1"
		template.Parent = root
		local arena = Instance.new("Part")
		arena.Parent = root
		local place = Instance.new("RemoteFunction")
		place.Parent = root
		local removeRemote = Instance.new("RemoteFunction")
		removeRemote.Parent = root
		service.Init({
			Instances = {
				Arena = arena,
				BaseIslands = root,
				Bases = root,
				MythlingAssets = root,
				BaseAssets = root,
			},
			Configurations = { Mythlings = Mythlings },
			Remotes = { Base = { PlaceMythling = place, RemoveMythling = removeRemote } },
			Services = {
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
				},
				InventoryService = {},
				ProductionService = {},
			},
		})
		table.insert(cleanup, function()
			service.Stop()
		end)
		expectUnavailable(fakePlayer)
		service.Start()
		-- The CLI runner cannot create engine Players. Real player membership/dispatch needs
		-- playtesting; a table whose Parent points at Players must not impersonate one here.
		expectUnavailable(fakePlayer)
		expectUnavailable(nil)
		expectUnavailable(root)
		service.Stop()
		expectUnavailable(fakePlayer)
	end)
end)
