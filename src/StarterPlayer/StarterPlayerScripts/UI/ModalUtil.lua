-- StarterPlayer/StarterPlayerScripts/UI/ModalUtil
-- Single owner of modal state and the input guard. UI/Overlays/ModalBackdrop observes it.
--
-- The Inventory and Stand views each used to hold their own reference to the
-- shared ModalBackdropGui ScreenGui and each connected its own handler to
-- ModalBackdropGui:GetPropertyChangedSignal("Enabled") -- two handlers doing identical work on
-- one signal. Because the guard keyed off the backdrop's Enabled property rather than off
-- how many panels were open, this sequence unguarded input with a panel still up:
--
--   1. open Inventory        -> ModalBackdropGui.Enabled = true, guard on
--   2. open a Stand          -> ModalBackdropGui already enabled, so no signal fires
--   3. close the Stand       -> ModalBackdropGui.Enabled = false, guard OFF
--      ...while the Inventory is still on screen.
--
-- Panels now declare themselves open or closed by name and never touch the backdrop.

local InputGuardUtil = require(script.Parent.InputGuardUtil)

local ModalUtil = {}

-- Names of every panel currently open. The backdrop is up whenever this is non-empty.
local openPanels: { [string]: true } = {}
local isGuardActive = false

-- Anything that needs to get out of a panel's way. The backpack used to be toggled from
-- here through SetCoreGuiEnabled, but HotbarController owns that CoreGui flag now -- it
-- keeps the platform hotbar off for the whole session -- so re-enabling it here would put
-- Roblox's unstyled hotbar back on screen every time a panel closed.
local listeners: { (boolean) -> () } = {}

local function anyOpen(): boolean
	return next(openPanels) ~= nil
end

--- Brings the backdrop and input guard in line with the set of open panels. Only acts on
--- the empty <-> non-empty transition, so opening a second panel is a no-op.
local function sync()
	local shouldShow = anyOpen()
	if shouldShow == isGuardActive then
		return
	end
	isGuardActive = shouldShow

	if shouldShow then
		InputGuardUtil.Open()
	else
		InputGuardUtil.Close()
	end

	for _, listener in ipairs(table.clone(listeners)) do
		local ok, err = pcall(listener, shouldShow)
		if not ok then
			warn(`[ModalUtil] Listener failed: {err}`)
		end
	end
end

--- Calls `listener(anyPanelOpen)` now and on every empty <-> non-empty transition after.
--- Returns a function that unsubscribes.
function ModalUtil.OnChanged(listener: (boolean) -> ()): () -> ()
	table.insert(listeners, listener)
	local ok, err = pcall(listener, anyOpen())
	if not ok then
		warn(`[ModalUtil] Initial listener failed: {err}`)
	end

	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

--- Marks `panelName` as open. Calling twice for the same panel is harmless.
function ModalUtil.Open(panelName: string)
	assert(type(panelName) == "string" and panelName ~= "", "[ModalUtil] panelName required")
	openPanels[panelName] = true
	sync()
end

--- Marks `panelName` as closed. The backdrop stays up while any other panel is open.
function ModalUtil.Close(panelName: string)
	assert(type(panelName) == "string" and panelName ~= "", "[ModalUtil] panelName required")
	openPanels[panelName] = nil
	sync()
end

function ModalUtil.IsOpen(panelName: string): boolean
	return openPanels[panelName] == true
end

--- True while any panel holds the backdrop.
function ModalUtil.AnyOpen(): boolean
	return anyOpen()
end

return ModalUtil
