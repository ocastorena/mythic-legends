--!strict
-- ServerScriptService/Services/DataService/ProfileSettlements
-- Run every registered profile-boundary rule in one detached, non-yielding transaction.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Transactions = require(script.Parent.Transactions)

export type Profile = {
	Data: Types.PlayerDoc,
	IsActive: (Profile) -> boolean,
}
export type ProfileSettlements = {
	Register: (string, ServerTypes.ProfileSettlement) -> (),
	Seal: () -> (),
	Run: (Profile, ServerTypes.ProfileBoundary, (() -> boolean)?) -> Types.TransactionResult,
	Finalize: (Profile, (() -> boolean)?) -> Types.TransactionResult,
}

local ProfileSettlements = {}

local function copyResult(result: Types.TransactionResult): Types.TransactionResult
	local copy = table.clone(result)
	if result.values then
		copy.values = table.clone(result.values)
	end
	return copy
end

function ProfileSettlements.new(
	clock: (() -> number)?,
	createId: (() -> string)?
): ProfileSettlements
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local nextId = createId or function(): string
		return HttpService:GenerateGUID(false)
	end
	local hooks: { ServerTypes.ProfileSettlement } = {}
	local owners: { [string]: boolean } = {}
	local sealed = false
	-- A released profile must not be retained for the entire server lifetime.
	local finalized: { [Profile]: Types.TransactionResult } = setmetatable({}, { __mode = "k" })
	local api = {}

	function api.Register(owner: string, settle: ServerTypes.ProfileSettlement)
		assert(not sealed, "[DataService.ProfileSettlements] Registration is closed")
		assert(
			type(owner) == "string" and #owner > 0 and #owner <= 64,
			"[DataService.ProfileSettlements] Invalid owner"
		)
		assert(not owners[owner], "[DataService.ProfileSettlements] Duplicate owner")
		assert(type(settle) == "function", "[DataService.ProfileSettlements] Callback required")
		owners[owner] = true
		table.insert(hooks, settle)
	end

	function api.Seal()
		sealed = true
	end

	function api.Run(
		profile: Profile,
		boundary: ServerTypes.ProfileBoundary,
		isCurrent: (() -> boolean)?
	): Types.TransactionResult
		sealed = true
		local revision = Transactions.GetRevision(profile.Data)
		if boundary ~= "Ready" and boundary ~= "Checkpoint" and boundary ~= "Release" then
			return { ok = false, code = "InvalidBoundary", revision = revision }
		end
		local validatedBoundary = boundary :: ServerTypes.ProfileBoundary
		local function isActive(): boolean
			return profile:IsActive() and (isCurrent == nil or isCurrent())
		end
		return Transactions.Run(profile.Data, {
			id = `{revision}:{nextId()}`,
			expectedRevision = revision,
			operation = `Data.Profile{boundary}`,
			signature = "",
		}, function(draft: Types.PlayerDoc): Types.TransactionOutcome
			local timestamp = now()
			if
				type(timestamp) ~= "number"
				or timestamp ~= timestamp
				or timestamp < 0
				or timestamp >= 2 ^ 53
			then
				return { ok = false, code = "InvalidTimestamp" }
			end
			for _, settle in hooks do
				local outcome = settle(draft, timestamp, validatedBoundary)
				if type(outcome) ~= "table" or type(outcome.ok) ~= "boolean" then
					error("[DataService.ProfileSettlements] Invalid settlement outcome")
				end
				if not outcome.ok then
					return outcome
				end
			end
			return { ok = true }
		end, isActive)
	end

	function api.Finalize(profile: Profile, isCurrent: (() -> boolean)?): Types.TransactionResult
		local previous = finalized[profile]
		if previous then
			return copyResult(previous)
		end
		local result = api.Run(profile, "Release", isCurrent)
		finalized[profile] = copyResult(result)
		return result
	end

	return api
end

return table.freeze(ProfileSettlements)
