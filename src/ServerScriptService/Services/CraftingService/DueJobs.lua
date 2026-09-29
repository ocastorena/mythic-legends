--!strict
-- ServerScriptService/Services/CraftingService/DueJobs
-- The saved deadline is authoritative; the timer only requests an atomic due-job settlement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ReplicatedStorage.Shared.Types)
local ServerTypes = require(ServerScriptService.Shared.Types)
local Crafting = require(ReplicatedStorage.Shared.Configurations.Crafting)

export type DataSource = {
	GetLoadedData: (Player) -> Types.PlayerDoc?,
	Update: (Player, string, ServerTypes.ProfileMutation) -> Types.TransactionResult,
}
export type DueJobs = { Step: (number) -> () }

local DueJobs = {}

local function due(data: Types.PlayerDoc, now: number): boolean
	if type(data.craftingJobs) ~= "table" then
		return false
	end
	for _, job in data.craftingJobs or {} do
		if type(job) ~= "table" then
			continue
		end
		local receipt = job.receipt
		if
			job.status == "Active"
			and type(receipt) == "table"
			and receipt.version == Crafting.receiptVersion
			and type(receipt.completesAt) == "number"
			and receipt.completesAt <= now
		then
			return true
		end
	end
	return false
end

function DueJobs.new(
	DataService: DataSource,
	players: () -> { Player },
	interval: number,
	clock: (() -> number)?,
	onFailure: ((Player, string?) -> ())?
): DueJobs
	assert(
		type(interval) == "number" and interval > 0 and interval < math.huge,
		"[CraftingService.DueJobs] Positive finite interval required"
	)
	local now = clock or function(): number
		return workspace:GetServerTimeNow()
	end
	local elapsed = 0
	local failures: { [Player]: string } = setmetatable({}, { __mode = "k" })
	local api = {}
	function api.Step(delta: number)
		if type(delta) ~= "number" or delta ~= delta or delta < 0 or delta >= math.huge then
			return
		end
		elapsed += delta
		if elapsed < interval then
			return
		end
		elapsed %= interval
		local timestamp = now()
		if
			type(timestamp) ~= "number"
			or timestamp ~= timestamp
			or timestamp < 0
			or timestamp >= 2 ^ 53
		then
			return
		end
		for _, player in players() do
			local data = DataService.GetLoadedData(player)
			if data and due(data, timestamp) then
				-- DataService runs the registered job preparation before this no-op callback.
				local result = DataService.Update(player, "Crafting.Resolve", function()
					return { ok = true }
				end)
				if result.ok then
					failures[player] = nil
				else
					local code = result.code or "SettlementFailed"
					local report = onFailure
					if failures[player] ~= code and report then
						report(player, result.code)
					end
					failures[player] = code
				end
			else
				failures[player] = nil
			end
		end
	end
	return api
end

return table.freeze(DueJobs)
