--!strict
-- ServerScriptService/Services/DataService/MutationPreparations
-- Ordered draft-only preparation, inside the caller's existing transaction and rollback boundary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)

export type MutationPreparations = {
	Register: (string, ServerTypes.MutationPreparation) -> (),
	Seal: () -> (),
	ApplyToDraft: (Types.PlayerDoc, number) -> Types.TransactionOutcome,
}

local MutationPreparations = {}

function MutationPreparations.new(): MutationPreparations
	local hooks: { ServerTypes.MutationPreparation } = {}
	local owners: { [string]: boolean } = {}
	local sealed = false
	local api = {}

	function api.Register(owner: string, prepare: ServerTypes.MutationPreparation)
		assert(not sealed, "[DataService.MutationPreparations] Registration is closed")
		assert(
			type(owner) == "string" and #owner > 0 and #owner <= 64,
			"[DataService.MutationPreparations] Invalid owner"
		)
		assert(not owners[owner], "[DataService.MutationPreparations] Duplicate owner")
		assert(type(prepare) == "function", "[DataService.MutationPreparations] Callback required")
		owners[owner] = true
		table.insert(hooks, prepare)
	end

	function api.Seal()
		sealed = true
	end

	function api.ApplyToDraft(draft: Types.PlayerDoc, now: number): Types.TransactionOutcome
		sealed = true
		if type(now) ~= "number" or now ~= now or now < 0 or now >= 2 ^ 53 then
			return { ok = false, code = "InvalidTimestamp" }
		end
		for _, prepare in hooks do
			local outcome = prepare(draft, now)
			if type(outcome) ~= "table" or type(outcome.ok) ~= "boolean" then
				error("[DataService.MutationPreparations] Invalid preparation outcome")
			end
			if not outcome.ok then
				return outcome
			end
		end
		return { ok = true }
	end

	return api
end

return table.freeze(MutationPreparations)
