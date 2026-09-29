--!strict
-- ServerStorage/Tests/__tests__/ShopService.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local cleanup: { () -> () } = {}

type Service = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	GetShop: (Player) -> Types.ShopViewResult,
	BuyOffer: (Player, Types.BuyShopOfferRequest) -> Types.TransactionResult,
}

local function fixture()
	local state = { reads = 0, transactions = 0 }
	local source = {
		GetLoadedData = function(_player: Player): Types.PlayerDoc?
			state.reads += 1
			return nil
		end,
		Transact = function(): Types.TransactionResult
			state.transactions += 1
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end,
	}
	local service: Service? = nil
	jest.isolateModules(function()
		local loadService = require :: (ModuleScript) -> Service
		service = loadService(ServerScriptService.Services.ShopService)
	end)
	local api = assert(service, "[ShopService.spec] Expected isolated service")
	table.insert(cleanup, api.Stop)
	return {
		api = api,
		state = state,
		context = ({ Services = { DataService = source } } :: unknown) :: ServerTypes.Context,
	}
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
end)

describe("ShopService", function()
	it(
		"has an idempotent start/stop lifecycle without reading profiles or scheduling restocks",
		function()
			local f = fixture()
			f.api.Init(f.context)
			f.api.Start()
			f.api.Start()
			f.api.Stop()
			f.api.Stop()
			expect(f.state).toEqual({ reads = 0, transactions = 0 })
			expect(function()
				f.api.Start()
			end).toThrow()
		end
	)

	it("rejects stopped, fake, and non-Player callers before profile access", function()
		local f = fixture()
		local folder = Instance.new("Folder")
		table.insert(cleanup, function()
			folder:Destroy()
		end)
		local fakePlayer = { UserId = 1001, Parent = Players }
		local function unavailable()
			for _, raw in { fakePlayer, folder, false } do
				local player = (raw :: unknown) :: Player
				expect(f.api.GetShop(player)).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
				expect(f.api.BuyOffer(player, ({} :: unknown) :: Types.BuyShopOfferRequest)).toEqual({
					ok = false,
					code = "DataUnavailable",
					revision = 0,
				})
			end
			expect(f.state).toEqual({ reads = 0, transactions = 0 })
		end
		unavailable()
		f.api.Init(f.context)
		unavailable()
		f.api.Start()
		unavailable()
		f.api.Stop()
		unavailable()
	end)
end)
