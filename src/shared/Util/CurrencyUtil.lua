-- ReplicatedStorage/Util/CurrencyUtil
-- Client-side cache of the player's currency, and the one place that listens to
-- CurrencyEvent.
--
-- The design system puts the coin pill in every panel header (§08), so the runies total
-- now has several views instead of one. Each of them connecting its own handler to
-- CurrencyEvent would reintroduce the problem the "single owner" pass fixed: whichever
-- view happened to connect after the server's join-time broadcast would sit at zero
-- forever, because the next fire might be minutes away.
--
-- So this module connects once, on require, and replays the current value to every
-- subscriber the moment it subscribes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyEvent: RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CurrencyEvent")

local CurrencyUtil = {}

local runies = 0
local listeners: { (number) -> () } = {}

CurrencyEvent.OnClientEvent:Connect(function(action, payload)
	if action ~= "RuniesUpdate" then
		return
	end
	runies = tonumber(payload) or 0
	for _, listener in ipairs(listeners) do
		task.spawn(listener, runies)
	end
end)

--- The latest known total.
function CurrencyUtil.Runies(): number
	return runies
end

--- Subscribes to changes. Fires immediately with the current value so a pill created after
--- the join broadcast still shows the right number. Returns a disconnect function.
function CurrencyUtil.OnRuniesChanged(listener: (number) -> ()): () -> ()
	table.insert(listeners, listener)
	task.spawn(listener, runies)

	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

--- 1234567 -> "1,234,567". Shared so every coin pill formats identically.
function CurrencyUtil.format(amount: number): string
	local formatted = tostring(math.floor(amount))
	local replaced
	while true do
		formatted, replaced = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

return CurrencyUtil
