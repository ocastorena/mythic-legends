--!strict
-- StarterPlayer/StarterPlayerScripts/UI/State/SubscriptionList
-- Each registration owns one idempotent unsubscribe, even for the same callback.
-- Delivery is synchronous and error-isolated. Removed listeners are skipped; listeners
-- added during delivery wait for the next publication. State adapters explicitly deliver
-- their initial snapshot; event-only channels never replay an old event.

local SubscriptionList = {}

export type Channel<T> = {
	Subscribe: ((T) -> ()) -> () -> (),
	Notify: ((T) -> (), T) -> (),
	Publish: (T) -> (),
}

function SubscriptionList.new<T>(tag: string): Channel<T>
	type Entry = { listener: (T) -> (), isSubscribed: boolean }
	local entries: { Entry } = {}
	local function notify(listener: (T) -> (), value: T)
		local ok, err = pcall(function()
			listener(value)
			return true
		end)
		if not ok then
			warn(`[{tag}] Listener failed: {err}`)
		end
	end
	return {
		Subscribe = function(listener)
			local entry: Entry = { listener = listener, isSubscribed = true }
			table.insert(entries, entry)
			return function()
				if not entry.isSubscribed then
					return
				end
				entry.isSubscribed = false
				local index = table.find(entries, entry)
				if index then
					table.remove(entries, index)
				end
			end
		end,
		Notify = notify,
		Publish = function(value)
			for _, entry in table.clone(entries) do
				if entry.isSubscribed then
					notify(entry.listener, value)
				end
			end
		end,
	}
end

return SubscriptionList
