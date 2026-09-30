--!strict
-- ServerScriptService/Services/InventoryService/InventoryRequests
-- Admit untrusted requests before domain work; commands retain validation and receipt ownership.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local InventoryRequests = {}

export type Command = (Player, unknown) -> Types.TransactionResult
export type Commands = {
	EvolveMythling: Command,
	SellMythling: Command,
	SellEquipment: Command,
	SellMaterial: Command,
	DiscardMaterial: Command,
	UpgradeCapacity: Command,
}
export type LegacyResult = { ok: boolean, code: string? }
export type Dependencies = {
	isAvailable: (Player) -> boolean,
	allowRequest: (Player) -> boolean,
	commands: Commands,
}
export type Requests = Commands & {
	DeleteMythling: (Player, unknown) -> LegacyResult,
}

function InventoryRequests.new(dependencies: Dependencies): Requests
	local function admit(player: Player): string?
		if not dependencies.isAvailable(player) then
			return "DataUnavailable"
		end
		if not dependencies.allowRequest(player) then
			return "RateLimited"
		end
		return nil
	end

	local function admitted(command: Command): Command
		return function(player: Player, input: unknown): Types.TransactionResult
			local rejection = admit(player)
			if rejection then
				return { ok = false, code = rejection, revision = 0 }
			end
			-- Forward unchanged: current-state prechecks must never supersede a committed retry.
			return command(player, input)
		end
	end

	return {
		EvolveMythling = admitted(dependencies.commands.EvolveMythling),
		SellMythling = admitted(dependencies.commands.SellMythling),
		SellEquipment = admitted(dependencies.commands.SellEquipment),
		SellMaterial = admitted(dependencies.commands.SellMaterial),
		DiscardMaterial = admitted(dependencies.commands.DiscardMaterial),
		UpgradeCapacity = admitted(dependencies.commands.UpgradeCapacity),
		DeleteMythling = function(player: Player, _input: unknown): LegacyResult
			-- Keep the old response shape for retained clients, but never detach, delete, or sell.
			local rejection = admit(player)
			return { ok = false, code = rejection or "UnsupportedAction" }
		end,
	}
end

return InventoryRequests
