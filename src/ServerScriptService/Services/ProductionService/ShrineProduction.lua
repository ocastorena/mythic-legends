--!strict
-- ServerScriptService/Services/ProductionService/ShrineProduction
-- On-demand profile settlement; DataService owns session selection, commit, and publication.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)

local ShrineProduction = {}

export type DataSource = {
	Update: (
		Player,
		string,
		(Types.PlayerDoc) -> Types.TransactionOutcome
	) -> Types.TransactionResult,
}
export type ShrineProduction = {
	Settle: (Player) -> Types.TransactionResult,
}

function ShrineProduction.new(DataService: DataSource, clock: (() -> number)?): ShrineProduction
	assert(
		type(DataService) == "table" and type(DataService.Update) == "function",
		"[ProductionService.ShrineProduction] DataService.Update required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local api = {}

	function api.Settle(player: Player): Types.TransactionResult
		return DataService.Update(player, "Production.SettleShrines", function(draft)
			-- Epoch seconds preserve saved cursors across servers and retain partial-batch work.
			-- Sample only inside the active transaction; callers cannot supply elapsed time.
			local timestamp = now()
			local ok, problem = ShrineAccounting.SettleToDraft(draft, timestamp)
			return {
				ok = ok,
				code = problem,
				values = if ok then { settledAt = timestamp } else nil,
			}
		end)
	end

	return api
end

return table.freeze(ShrineProduction)
