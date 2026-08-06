-- StarterPlayer/StarterPlayerScripts/UI/State/MenuState
-- Owns the single active top-level menu. Screens register their transition API; callers
-- express intent by semantic name instead of mutating ScreenGui.Enabled directly.

local MenuState = {}

export type Menu = {
	Open: (skipAnimation: boolean?) -> (),
	Close: (skipAnimation: boolean?) -> (),
	IsOpen: () -> boolean,
}

local menus: { [string]: Menu } = {}
local activeName: string? = nil
local listeners: { [(string?) -> ()]: boolean } = {}

local function notifyListeners()
	for listener in listeners do
		listener(activeName)
	end
end

function MenuState.Subscribe(listener: (string?) -> ()): () -> ()
	listeners[listener] = true
	listener(activeName)

	return function()
		listeners[listener] = nil
	end
end

function MenuState.Register(name: string, menu: Menu): () -> ()
	assert(type(name) == "string" and name ~= "", "[MenuState] name required")
	assert(menus[name] == nil, `[MenuState] {name} is already registered`)
	menus[name] = menu

	return function()
		if menus[name] ~= menu then
			return
		end
		if activeName == name then
			activeName = nil
			notifyListeners()
		end
		menu.Close(true)
		menus[name] = nil
	end
end

function MenuState.Open(name: string): boolean
	local menu = menus[name]
	if not menu then
		return false
	end
	if activeName == name then
		if not menu.IsOpen() then
			menu.Open()
		end
		return true
	end

	activeName = name
	notifyListeners()

	-- Claim the backdrop for the incoming menu before the outgoing menu releases it. Both
	-- operations happen in one task, so there is no frame where world input becomes active.
	menu.Open()
	for otherName, otherMenu in menus do
		if otherName ~= name then
			-- Close also finishes a menu that was already partway through its exit animation.
			otherMenu.Close(true)
		end
	end
	return true
end

function MenuState.Close(name: string): boolean
	local menu = menus[name]
	if not menu then
		return false
	end
	if activeName == name then
		activeName = nil
		notifyListeners()
	end
	menu.Close()
	return true
end

function MenuState.Toggle(name: string): boolean
	if activeName == name then
		return MenuState.Close(name)
	end
	return MenuState.Open(name)
end

function MenuState.GetActiveName(): string?
	return activeName
end

return MenuState
