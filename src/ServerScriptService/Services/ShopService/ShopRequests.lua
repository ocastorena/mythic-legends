--!strict
-- ServerScriptService/Services/ShopService/ShopRequests
-- Admit untrusted Shop requests before profile access and keep refreshed quotes outside receipts.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local ShopRequests = {}

export type Dependencies = {
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	getShop: (Player) -> Types.ShopViewResult,
	buyOffer: (Player, unknown) -> Types.TransactionResult,
}
export type Requests = {
	Get: (Player) -> Types.ShopViewResult,
	Buy: (Player, unknown) -> Types.BuyShopOfferResult,
}

function ShopRequests.new(dependencies: Dependencies): Requests
	local requests = {} :: Requests

	local function admit(player: Player): string?
		if not dependencies.isAvailable(player) then
			return "DataUnavailable"
		end
		if not dependencies.allowRequest(player) then
			return "RateLimited"
		end
		return nil
	end

	function requests.Get(player: Player): Types.ShopViewResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.getShop(player)
	end

	function requests.Buy(player: Player, input: unknown): Types.BuyShopOfferResult
		local rejection = admit(player)
		if rejection then
			return { transaction = { ok = false, code = rejection, revision = 0 } }
		end
		-- The command owns closed-envelope validation and replay before current-offer checks.
		local transaction = dependencies.buyOffer(player, input)
		local result: Types.BuyShopOfferResult = { transaction = transaction }
		if
			not transaction.ok
			and (transaction.code == "OfferExpired" or transaction.code == "OfferChanged")
		then
			result.shop = dependencies.getShop(player)
		end
		return result
	end

	return requests
end

return ShopRequests
