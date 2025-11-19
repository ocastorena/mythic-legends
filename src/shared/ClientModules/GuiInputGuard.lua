-- ReplicatedStorage/ClientModules/uiInputGuard.lua
-- Blocks movement/camera across KB/mouse/gamepad/touch while modal UIs are open.

local Players = game:GetService("Players")
local CAS     = game:GetService("ContextActionService")
local UIS     = game:GetService("UserInputService")
local LP      = Players.LocalPlayer

local ACTION_MOVE   = "UI_BlockCharacterMovement"
local ACTION_SCROLL = "UI_DisableScrollZoom"
local ACTION_RMB    = "UI_DisableRMBRotate"
local ACTION_KEYS   = "UI_DisableCameraKeys"
local ACTION_TOUCH  = "UI_DisableTouchTap"

local PRIORITY = Enum.ContextActionPriority.High.Value + 100

local refCount = 0

-- Defaults (override via M.open{ ... })
local opts = {
	blockJump        = true,
	hideMobileControls = true,   -- Hide thumbstick/jump UI while modal
	blockScrollZoom  = true,     -- Mouse wheel zoom
	blockRMBRotate   = true,     -- Right-mouse drag rotate
	blockCameraKeys  = true,     -- I/O zoom, Left/Right rotate
	blockTouchTap    = true,     -- Sinks generic touch taps
	lockCamera       = true,     -- Temporarily set CameraType = Scriptable
	disableControls  = true,     -- PlayerModule controls Disable()
}

-- Movement inputs (WASD/arrows/thumbstick/DPad + jump)
local MOVE_INPUTS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight,
	Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump, Enum.KeyCode.Space, Enum.KeyCode.ButtonA,
}

local function sink() return Enum.ContextActionResult.Sink end

-- ===== Controls & camera bookkeeping =====
local Controls -- PlayerModule controls handle
local controlsWasEnabled = nil

local cam = workspace.CurrentCamera
local savedCamType, savedCamSubject

local function ensureControls()
	if Controls then return end
	local pmod = LP:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
	local PlayerModule = require(pmod)
	Controls = PlayerModule:GetControls()
end

local function disableControls()
	if not opts.disableControls then return end
	ensureControls()
	if Controls then
		-- Remember previous state on first disable
		if controlsWasEnabled == nil then
			controlsWasEnabled = Controls.enabled ~= false
		end
		Controls:Disable()
	end
end

local function restoreControls()
	if not opts.disableControls then return end
	if Controls and controlsWasEnabled ~= nil then
		if controlsWasEnabled then Controls:Enable() end
	end
	controlsWasEnabled = nil
end

local function lockCamera()
	if not opts.lockCamera or not cam then return end
	if not savedCamType then
		savedCamType   = cam.CameraType
		savedCamSubject = cam.CameraSubject
	end
	cam.CameraType = Enum.CameraType.Scriptable
end

local function unlockCamera()
	if not opts.lockCamera or not cam then return end
	if savedCamType then
		cam.CameraType   = savedCamType
		cam.CameraSubject = savedCamSubject
	end
	savedCamType, savedCamSubject = nil, nil
end

-- ===== CAS binds =====
local function bindMovement()
	local list = table.create(#MOVE_INPUTS)
	for _, code in ipairs(MOVE_INPUTS) do
		if not opts.blockJump and (code == Enum.PlayerActions.CharacterJump
			or code == Enum.KeyCode.Space or code == Enum.KeyCode.ButtonA) then
			-- skip jump inputs
		else
			table.insert(list, code)
		end
	end
	CAS:BindActionAtPriority(ACTION_MOVE, sink, false, PRIORITY, table.unpack(list))
end

local function unbindMovement()
	CAS:UnbindAction(ACTION_MOVE)
end

local function bindCameraBlocks()
	-- Mouse wheel (zoom)
	if opts.blockScrollZoom then
		CAS:BindActionAtPriority(ACTION_SCROLL, sink, false, PRIORITY, Enum.UserInputType.MouseWheel)
	end
	-- Right mouse button (drag to rotate)
	if opts.blockRMBRotate then
		CAS:BindActionAtPriority(ACTION_RMB, sink, false, PRIORITY, Enum.UserInputType.MouseButton2)
	end
	-- Keyboard camera controls (I/O zoom, Left/Right rotate)
	if opts.blockCameraKeys then
		CAS:BindActionAtPriority(
			ACTION_KEYS,
			sink,
			false,
			PRIORITY,
			Enum.KeyCode.I, Enum.KeyCode.O, Enum.KeyCode.Left, Enum.KeyCode.Right
		)
	end
	-- Generic touch taps (extra safety)
	if opts.blockTouchTap and UIS.TouchEnabled then
		CAS:BindActionAtPriority(ACTION_TOUCH, sink, false, PRIORITY, Enum.UserInputType.Touch)
	end

	-- Hide mobile controls cosmetically while menus are up
	if opts.hideMobileControls and UIS.TouchEnabled then
		UIS.ModalEnabled = true
	end
end

local function unbindCameraBlocks()
	CAS:UnbindAction(ACTION_SCROLL)
	CAS:UnbindAction(ACTION_RMB)
	CAS:UnbindAction(ACTION_KEYS)
	CAS:UnbindAction(ACTION_TOUCH)
	if UIS.TouchEnabled then
		UIS.ModalEnabled = false
	end
end

-- ===== Public API =====
local M = {}

function M.open()
	refCount += 1
	if refCount == 1 then
		disableControls()
		lockCamera()
		bindMovement()
		bindCameraBlocks()
	end
end

function M.close()
	if refCount <= 0 then return end
	refCount -= 1
	if refCount == 0 then
		unbindMovement()
		unbindCameraBlocks()
		unlockCamera()
		restoreControls()
	end
end

return M

