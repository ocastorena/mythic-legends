--!strict
-- ServerScriptService/Services/ProductionService/ProfileProduction
-- Pure profile-boundary hook; remains usable after ProductionService stops its runtime tasks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local ShrineAccounting = require(ServerScriptService.Shared.ShrineAccounting)
local ProductionClockUtil = require(ServerScriptService.Shared.ProductionClockUtil)

local ProfileProduction = {}

function ProfileProduction.Settle(
	draft: Types.PlayerDoc,
	now: number,
	boundary: ServerTypes.ProfileBoundary
): Types.TransactionOutcome
	if boundary ~= "Ready" and boundary ~= "Checkpoint" and boundary ~= "Release" then
		return { ok = false, code = "InvalidProfileBoundary" }
	end
	local clock = draft.productionClock
	if not clock then
		return { ok = false, code = "MissingProductionClock" }
	end
	if not ProductionClockUtil.ValidateLifecycle(clock) then
		return { ok = false, code = "InvalidProductionClock" }
	end
	-- Only Ready can start a new online session; other callers must not clear an offline boundary.
	if
		boundary ~= "Ready" and (clock.lastOnlineCheckpointAt == nil or clock.offlineSince ~= nil)
	then
		return { ok = false, code = "ProfileNotReady" }
	end
	local ok, problem = ShrineAccounting.SettleToDraft(draft, now)
	if not ok then
		return { ok = false, code = problem or "SettlementFailed" }
	end
	local settled = draft.productionClock
	assert(settled, "[ProductionService.ProfileProduction] Settlement must retain its clock")
	if boundary == "Release" then
		settled.offlineSince = now
	else
		settled.lastOnlineCheckpointAt = now
		settled.offlineSince = nil
	end
	return { ok = true }
end

return table.freeze(ProfileProduction)
