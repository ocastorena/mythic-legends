--!strict
-- ServerStorage/Tests/__tests__/ShopService.spec

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ShopRequests = require(ServerScriptService.Services.ShopService.ShopRequests)
local RemoteUtil = require(ServerScriptService.Infrastructure.RemoteUtil)

local describe, expect, it, afterEach, jest =
	JestGlobals.describe,
	JestGlobals.expect,
	JestGlobals.it,
	JestGlobals.afterEach,
	JestGlobals.jest
local cleanup: { () -> () } = {}
local requestsModule = ServerScriptService.Services.ShopService.ShopRequests
local remoteUtilModule = ServerScriptService.Infrastructure.RemoteUtil

type Service = {
	Init: (ServerTypes.Context) -> (),
	Start: () -> (),
	Stop: () -> (),
	GetShop: (Player) -> Types.ShopViewResult,
	BuyOffer: (Player, Types.BuyShopOfferRequest) -> Types.TransactionResult,
}

local function fixture()
	local state = { reads = 0, transactions = 0 }
	local observed = {
		requests = nil :: ShopRequests.Requests?,
		factories = 0,
		cleared = {} :: { RemoteFunction },
	}
	local getRemote, buyRemote = Instance.new("RemoteFunction"), Instance.new("RemoteFunction")
	getRemote.Name, buyRemote.Name = "GetShop", "BuyOffer"
	table.insert(cleanup, function()
		getRemote:Destroy()
		buyRemote:Destroy()
	end)
	-- Callback properties are write-only on engine remotes. Capture the real factory's callbacks,
	-- while the service still installs them on actual disposable RemoteFunctions.
	jest.mock(requestsModule, function()
		return {
			new = function(dependencies: ShopRequests.Dependencies): ShopRequests.Requests
				observed.factories += 1
				local requests = ShopRequests.new(dependencies)
				observed.requests = requests
				return requests
			end,
		}
	end)
	jest.mock(remoteUtilModule, function()
		return {
			ClearServerHandler = function(remote: RemoteFunction)
				table.insert(observed.cleared, remote)
				RemoteUtil.ClearServerHandler(remote)
			end,
		}
	end)
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
		observed = observed,
		getRemote = getRemote,
		buyRemote = buyRemote,
		context = ({
			Services = { DataService = source },
			Remotes = { Shop = { GetShop = getRemote, BuyOffer = buyRemote } },
		} :: unknown) :: ServerTypes.Context,
	}
end

afterEach(function()
	for index = #cleanup, 1, -1 do
		cleanup[index]()
	end
	table.clear(cleanup)
	jest.unmock(requestsModule)
	jest.unmock(remoteUtilModule)
end)

describe("ShopService", function()
	it(
		"installs disposable endpoint handlers and clears them once through its terminal lifecycle",
		function()
			local f = fixture()
			expect(f.observed.requests).toBeNil()
			f.api.Init(f.context)
			expect(f.observed.factories).toBe(1)
			expect(f.observed.cleared).toEqual({})
			f.api.Start()
			f.api.Start()
			expect(f.observed.factories).toBe(1)
			f.api.Stop()
			f.api.Stop()
			expect(f.observed.cleared).toEqual({ f.getRemote, f.buyRemote })
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
		local retained: ShopRequests.Requests? = nil
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
				local callbacks = retained
				if callbacks then
					expect(callbacks.Get(player)).toEqual({
						ok = false,
						code = "DataUnavailable",
						revision = 0,
					})
					expect(callbacks.Buy(player, {})).toEqual({
						transaction = { ok = false, code = "DataUnavailable", revision = 0 },
					})
				end
			end
			expect(f.state).toEqual({ reads = 0, transactions = 0 })
		end
		unavailable()
		f.api.Init(f.context)
		retained = assert(f.observed.requests, "[ShopService.spec] Expected captured handlers")
		unavailable()
		f.api.Start()
		unavailable()
		f.api.Stop()
		unavailable()
		expect(f.observed.cleared).toEqual({ f.getRemote, f.buyRemote })
	end)
end)
