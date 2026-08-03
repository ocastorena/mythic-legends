-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/CombatController/PresentationBus

local PresentationBus = {}

local event: BindableEvent?

function PresentationBus.Init(_context: any)
end

function PresentationBus.Start()
	if event then
		return
	end
	local created = Instance.new("BindableEvent")
	created.Name = "CombatPresentationBus"
	event = created
end

function PresentationBus.GetEvent(): RBXScriptSignal
	assert(event, "[PresentationBus] Start must run before GetEvent")
	return event.Event
end

function PresentationBus.Fire(...)
	if event then
		event:Fire(...)
	end
end

function PresentationBus.Stop()
	if event then
		event:Destroy()
		event = nil
	end
end

return PresentationBus
