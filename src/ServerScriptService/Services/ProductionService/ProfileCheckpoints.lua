--!strict
-- ServerScriptService/Services/ProductionService/ProfileCheckpoints
-- Bounded online checkpoint cadence; never loads profiles or requests a DataStore save.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local ProfileCheckpoints = {}

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Checkpoint: (Player) -> Types.TransactionResult,
}
export type ProfileCheckpoints = { Step: (number) -> () }

function ProfileCheckpoints.new(
	DataService: DataSource,
	players: () -> { Player },
	intervalSeconds: number,
	onFailure: ((Player, string) -> ())?
): ProfileCheckpoints
	assert(
		intervalSeconds == intervalSeconds and intervalSeconds > 0 and intervalSeconds < math.huge,
		"[ProductionService.ProfileCheckpoints] A positive finite interval is required"
	)
	local elapsed = 0
	local api = {}
	function api.Step(deltaSeconds: number)
		if deltaSeconds ~= deltaSeconds or deltaSeconds <= 0 or deltaSeconds == math.huge then
			return
		end
		elapsed += deltaSeconds
		if elapsed < intervalSeconds then
			return
		end
		-- One current-time settlement catches up all work; do not replay missed checkpoint ticks.
		elapsed %= intervalSeconds
		for _, player in players() do
			if DataService.GetLoadedData(player) then
				local result = DataService.Checkpoint(player)
				local report = onFailure
				if not result.ok and result.code ~= "DataUnavailable" and report then
					report(player, result.code or "CheckpointFailed")
				end
			end
		end
	end
	return api
end

return table.freeze(ProfileCheckpoints)
