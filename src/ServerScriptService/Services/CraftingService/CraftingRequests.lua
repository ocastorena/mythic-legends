--!strict
-- ServerScriptService/Services/CraftingService/CraftingRequests
-- Admit raw requests before protected work; command-owned access checks follow receipt admission.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local CraftingRequests = {}

export type Dependencies = {
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	getStation: (Player, unknown) -> Types.CraftingStationViewResult,
	startJob: (Player, unknown) -> Types.TransactionResult,
	cancelJob: (Player, unknown) -> Types.TransactionResult,
}
export type Requests = {
	GetStation: (Player, unknown) -> Types.CraftingStationViewResult,
	StartJob: (Player, unknown) -> Types.TransactionResult,
	CancelJob: (Player, unknown) -> Types.TransactionResult,
}

function CraftingRequests.new(dependencies: Dependencies): Requests
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
	function requests.GetStation(player: Player, input: unknown): Types.CraftingStationViewResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.getStation(player, input)
	end

	function requests.StartJob(player: Player, input: unknown): Types.TransactionResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		-- No current location, job, or price precheck may supersede a committed retry.
		return dependencies.startJob(player, input)
	end

	function requests.CancelJob(player: Player, input: unknown): Types.TransactionResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.cancelJob(player, input)
	end

	return requests
end

return CraftingRequests
