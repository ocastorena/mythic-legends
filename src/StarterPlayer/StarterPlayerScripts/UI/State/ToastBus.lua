--!strict
-- StarterPlayer/StarterPlayerScripts/UI/State/ToastBus
-- Event-only toast API. UI/Overlays/Toast owns rendering and animation.

local SubscriptionList = require(script.Parent.SubscriptionList)

local ToastBus = {}

export type Listener = (message: string) -> ()

local listeners: SubscriptionList.Channel<string> = (SubscriptionList.new :: (
	string
) -> SubscriptionList.Channel<string>)("ToastBus.SubscriptionList")

function ToastBus.Subscribe(listener: Listener): () -> ()
	return listeners.Subscribe(listener)
end
function ToastBus.Show(message: string)
	if type(message) ~= "string" or message == "" then
		return
	end
	listeners.Publish(message)
end

return ToastBus
