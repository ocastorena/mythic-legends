-- StarterPlayer/StarterPlayerScripts/UI/ToastUtil
-- Event-only toast API. UI/Overlays/Toast owns rendering and animation.

local ToastUtil = {}

export type Listener = (message: string) -> ()

local listeners: { Listener } = {}

function ToastUtil.Subscribe(listener: Listener): () -> ()
	assert(type(listener) == "function", "[ToastUtil] listener must be a function")
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

function ToastUtil.Show(message: string)
	if type(message) ~= "string" or message == "" then
		return
	end
	for _, listener in table.clone(listeners) do
		local ok, err = pcall(listener, message)
		if not ok then
			warn(`[ToastUtil] Toast listener failed: {err}`)
		end
	end
end

return ToastUtil
