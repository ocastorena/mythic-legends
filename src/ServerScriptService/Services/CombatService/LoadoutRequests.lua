--!strict
-- ServerScriptService/Services/CombatService/LoadoutRequests
-- Admit loadout requests without yielding or initiating profile loads.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local LoadoutRequests = {}

export type Snapshot = {
	equipment: { { instanceId: string, definitionId: string } },
	primaryWeaponInstanceId: string?,
	shieldInstanceId: string?,
}
export type Result = { ok: boolean, code: string?, snapshot: Snapshot? }
export type Dependencies = {
	DataService: { GetLoadedData: (Player) -> Types.PlayerDoc? },
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	resolveLoadout: (Player) -> (),
	snapshotLoadout: (Player) -> Snapshot,
	equipOwnedInstance: (Player, unknown) -> (boolean, string?),
	now: (() -> number)?,
}
export type Requests = {
	Get: (Player) -> Result,
	Equip: (Player, unknown) -> Result,
	Forget: (Player) -> (),
	Clear: () -> (),
}

local EQUIP_INTERVAL_SECONDS = 0.5

function LoadoutRequests.new(dependencies: Dependencies): Requests
	local nextEquipAt: { [Player]: number } = {}
	local now = dependencies.now or os.clock
	local requests = {} :: Requests

	local function admit(player: Player, isEquip: boolean): string?
		if not dependencies.isAvailable(player) then
			return "Unavailable"
		end
		if not dependencies.allowRequest(player) then
			return "RateLimited"
		end
		if isEquip and now() < (nextEquipAt[player] or 0) then
			return "RateLimited"
		end
		if not dependencies.DataService.GetLoadedData(player) then
			return "NotReady"
		end
		return nil
	end

	function requests.Get(player: Player): Result
		local rejection = admit(player, false)
		if rejection then
			return { ok = false, code = rejection }
		end
		dependencies.resolveLoadout(player)
		return { ok = true, snapshot = dependencies.snapshotLoadout(player) }
	end

	function requests.Equip(player: Player, instanceId: unknown): Result
		local rejection = admit(player, true)
		if rejection then
			return { ok = false, code = rejection }
		end
		nextEquipAt[player] = now() + EQUIP_INTERVAL_SECONDS
		local ok, reason = dependencies.equipOwnedInstance(player, instanceId)
		if not ok then
			return { ok = false, code = reason }
		end
		return { ok = true, snapshot = dependencies.snapshotLoadout(player) }
	end

	function requests.Forget(player: Player)
		nextEquipAt[player] = nil
	end

	function requests.Clear()
		table.clear(nextEquipAt)
	end

	return requests
end

return LoadoutRequests
