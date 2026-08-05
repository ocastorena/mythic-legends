-- StarterPlayer/StarterPlayerScripts/UI/State/ToastBus
-- Event-only toast API. UI/Overlays/Toast owns rendering and animation.

local ToastBus = {}

export type Listener = (message: string) -> ()

local listeners: { Listener } = {}

function ToastBus.Subscribe(listener: Listener): () -> ()
	assert(type(listener) == "function", "[ToastBus] listener must be a function")
	table.insert(listeners, listener)
	local isSubscribed = true
	return function()
		if not isSubscribed then
			return
		end
		isSubscribed = false
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function ToastBus.Show(message: string)
	if type(message) ~= "string" or message == "" then
		return
	end
	for _, listener in table.clone(listeners) do
		local ok, err = pcall(listener, message)
		if not ok then
			warn(`[ToastBus] Toast listener failed: {err}`)
		end
	end
end

return ToastBus
