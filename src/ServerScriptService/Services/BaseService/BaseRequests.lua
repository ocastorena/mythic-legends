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
	getShrine: (Player, unknown) -> Types.ShrineViewResult,
	assignShrineWorker: (Player, unknown) -> Types.TransactionResult,
	removeShrineWorker: (Player, unknown) -> Types.TransactionResult,
	upgradeShrine: (Player, unknown) -> Types.TransactionResult,
	dismantleShrine: (Player, unknown) -> Types.TransactionResult,
}
export type Requests = {
	GetBase: (Player) -> Types.BaseViewResult,
	BuildShrine: (Player, unknown) -> Types.TransactionResult,
	ExpandBase: (Player, unknown) -> Types.TransactionResult,
	GetShrine: (Player, unknown) -> Types.ShrineViewResult,
	AssignShrineWorker: (Player, unknown) -> Types.TransactionResult,
	RemoveShrineWorker: (Player, unknown) -> Types.TransactionResult,
	UpgradeShrine: (Player, unknown) -> Types.TransactionResult,
	DismantleShrine: (Player, unknown) -> Types.TransactionResult,
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

	function requests.GetShrine(player: Player, input: unknown): Types.ShrineViewResult
		local rejection = admit(player)
		if rejection then
			return { ok = false, code = rejection, revision = 0 }
		end
		return dependencies.getShrine(player, input)
	end

	local function command(
		action: (Player, unknown) -> Types.TransactionResult
	): (Player, unknown) -> Types.TransactionResult
		return function(player: Player, input: unknown): Types.TransactionResult
			local rejection = admit(player)
			if rejection then
				return { ok = false, code = rejection, revision = 0 }
			end
			return action(player, input)
		end
	end
	requests.BuildShrine = command(dependencies.buildShrine)
	requests.ExpandBase = command(dependencies.expandBase)
	requests.AssignShrineWorker = command(dependencies.assignShrineWorker)
	requests.RemoveShrineWorker = command(dependencies.removeShrineWorker)
	requests.UpgradeShrine = command(dependencies.upgradeShrine)
	requests.DismantleShrine = command(dependencies.dismantleShrine)

	return requests
end

return BaseRequests
