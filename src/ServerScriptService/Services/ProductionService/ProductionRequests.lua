--!strict
-- ServerScriptService/Services/ProductionService/ProductionRequests
-- Admit the unchanged collection envelope; transaction-owned access checks follow receipt lookup.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local ProductionRequests = {}

export type Dependencies = {
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	collectShrine: (Player, unknown) -> Types.TransactionResult,
}
export type Requests = {
	CollectShrine: (Player, unknown) -> Types.TransactionResult,
}

function ProductionRequests.new(dependencies: Dependencies): Requests
	local requests = {} :: Requests
	function requests.CollectShrine(player: Player, input: unknown): Types.TransactionResult
		if not dependencies.isAvailable(player) then
			return { ok = false, code = "DataUnavailable", revision = 0 }
		end
		if not dependencies.allowRequest(player) then
			return { ok = false, code = "RateLimited", revision = 0 }
		end
		return dependencies.collectShrine(player, input)
	end
	return requests
end

return ProductionRequests
