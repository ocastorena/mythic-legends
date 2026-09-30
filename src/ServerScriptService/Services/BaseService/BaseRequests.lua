--!strict
-- ServerScriptService/Services/BaseService/BaseRequests
-- Admit requests before protected work; commands own exact envelopes, access, and receipt replay.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local BaseRequests = {}

export type Dependencies = {
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	getBase: (Player) -> Types.BaseViewResult,
	buildShrine: (Player, unknown) -> Types.TransactionResult,
	expandBase: (Player, unknown) -> Types.TransactionResult,
}
export type Requests = {
	GetBase: (Player) -> Types.BaseViewResult,
	BuildShrine: (Player, unknown) -> Types.TransactionResult,
	ExpandBase: (Player, unknown) -> Types.TransactionResult,
}

function BaseRequests.new(dependencies: Dependencies): Requests
	local function admit(player: Player): string?
		if not dependencies.isAvailable(player) then
			return "DataUnavailable"
		end
		if not dependencies.allowRequest(player) then
			return "RateLimited"
		end
		return nil
	end
	local requests = {} :: Requests
	function requests.GetBase(player: Player): Types.BaseViewResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.getBase(player)
	end

	function requests.BuildShrine(player: Player, input: unknown): Types.TransactionResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.buildShrine(player, input)
	end

	function requests.ExpandBase(player: Player, input: unknown): Types.TransactionResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.expandBase(player, input)
	end

	return requests
end

return BaseRequests
