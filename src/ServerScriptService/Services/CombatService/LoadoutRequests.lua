--!strict
-- ServerScriptService/Services/CombatService/LoadoutRequests
-- Admit loadout requests without yielding or initiating profile loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local Configuration = require(ReplicatedStorage.Shared.Configurations.LoadoutRequests)

local LoadoutRequests = {}

export type Snapshot = {
	equipment: { { instanceId: string, definitionId: string, finishId: string? } },
	primaryWeaponInstanceId: string?,
	shieldInstanceId: string?,
}
export type Result = { ok: boolean, code: string?, snapshot: Snapshot? }
export type Dependencies = {
	DataService: { GetLoadedData: (Player) -> Types.PlayerDoc? },
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	snapshotLoadout: (Player) -> Snapshot,
	equipOwnedInstance: (Player, unknown) -> (boolean, string?),
	equipEquipment: (Player, unknown) -> Types.TransactionResult,
	unequipEquipment: (Player, unknown) -> Types.TransactionResult,
	now: (() -> number)?,
}
export type Requests = {
	Get: (Player) -> Result,
	Equip: (Player, unknown) -> Result,
	EquipEquipment: (Player, unknown) -> Types.TransactionResult,
	UnequipEquipment: (Player, unknown) -> Types.TransactionResult,
	Forget: (Player) -> (),
	Clear: () -> (),
}

function LoadoutRequests.new(dependencies: Dependencies): Requests
	local interval = Configuration.mutationIntervalSeconds
	assert(
		type(interval) == "number" and interval > 0 and interval < math.huge,
		"[CombatService.LoadoutRequests] Invalid mutation interval"
	)
	local nextMutationAt: { [Player]: number } = {}
	local now = dependencies.now or os.clock
	local requests = {} :: Requests

	local function admit(player: Player, isMutation: boolean): string?
		if not dependencies.isAvailable(player) then
			return "Unavailable"
		end
		if not dependencies.allowRequest(player) then
			return "RateLimited"
		end
		local timestamp = if isMutation then now() else 0
		if isMutation and timestamp < (nextMutationAt[player] or 0) then
			return "RateLimited"
		end
		if not dependencies.DataService.GetLoadedData(player) then
			return "NotReady"
		end
		if isMutation then
			nextMutationAt[player] = timestamp + interval
		end
		return nil
	end

	function requests.Get(player: Player): Result
		local rejection = admit(player, false)
		if rejection then
			return { ok = false, code = rejection }
		end
		return { ok = true, snapshot = dependencies.snapshotLoadout(player) }
	end

	function requests.Equip(player: Player, instanceId: unknown): Result
		local rejection = admit(player, true)
		if rejection then
			return { ok = false, code = rejection }
		end
		local ok, reason = dependencies.equipOwnedInstance(player, instanceId)
		if not ok then
			return { ok = false, code = reason }
		end
		return { ok = true, snapshot = dependencies.snapshotLoadout(player) }
	end

	local function command(
		player: Player,
		input: unknown,
		apply: (Player, unknown) -> Types.TransactionResult
	): Types.TransactionResult
		local rejection = admit(player, true)
		if rejection then
			return {
				ok = false,
				code = if rejection == "RateLimited" then rejection else "DataUnavailable",
				revision = 0,
			}
		end
		-- Replay and closed-envelope validation belong to the canonical command, not admission.
		return apply(player, input)
	end

	function requests.EquipEquipment(player: Player, input: unknown): Types.TransactionResult
		return command(player, input, dependencies.equipEquipment)
	end

	function requests.UnequipEquipment(player: Player, input: unknown): Types.TransactionResult
		return command(player, input, dependencies.unequipEquipment)
	end

	function requests.Forget(player: Player)
		nextMutationAt[player] = nil
	end

	function requests.Clear()
		table.clear(nextMutationAt)
	end

	return requests
end

return LoadoutRequests
