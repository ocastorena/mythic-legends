-- ReplicatedStorage/Util/ModalUtil
-- Single owner of the modal backdrop, the input guard and the backpack toggle.
--
-- InventoryController and StandController each used to hold their own reference to the
-- shared Background ScreenGui and each connected its own handler to
-- Background:GetPropertyChangedSignal("Enabled") -- two handlers doing identical work on
-- one signal. Because the guard keyed off the backdrop's Enabled property rather than off
-- how many panels were open, this sequence unguarded input with a panel still up:
--
--   1. open Inventory        -> Background.Enabled = true, guard on
--   2. open a Stand          -> Background already enabled, so no signal fires
--   3. close the Stand       -> Background.Enabled = false, guard OFF
--      ...while the Inventory is still on screen.
--
-- Panels now declare themselves open or closed by name and never touch the backdrop.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local InputGuardUtil = require(script.Parent.InputGuardUtil)

local ModalUtil = {}

local localPlayer = Players.LocalPlayer

-- Names of every panel currently open. The backdrop is up whenever this is non-empty.
local openPanels: { [string]: true } = {}
local backdropShown = false

local function getBackdrop(): ScreenGui?
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	local backdrop = playerGui and playerGui:FindFirstChild("Background")
	return (backdrop and backdrop:IsA("ScreenGui")) and backdrop or nil
end

local function anyOpen(): boolean
	return next(openPanels) ~= nil
end

--- Brings the backdrop and input guard in line with the set of open panels. Only acts on
--- the empty <-> non-empty transition, so opening a second panel is a no-op.
local function sync()
	local shouldShow = anyOpen()
	if shouldShow == backdropShown then
		return
	end
	backdropShown = shouldShow

	local backdrop = getBackdrop()
	if backdrop then
		backdrop.Enabled = shouldShow
	end

	if shouldShow then
		InputGuardUtil.open()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	else
		InputGuardUtil.close()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
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
