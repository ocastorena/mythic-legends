--!strict
-- StarterPlayer/StarterPlayerScripts/UI/InputGuard
-- Blocks movement/camera across KB/mouse/gamepad/touch while modal UIs are open.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local localPlayer = Players.LocalPlayer

local ACTION_MOVE = "UI_BlockCharacterMovement"
local ACTION_SCROLL = "UI_DisableScrollZoom"
local ACTION_RMB = "UI_DisableRMBRotate"
local ACTION_KEYS = "UI_DisableCameraKeys"
local ACTION_TOUCH = "UI_DisableTouchTap"

local PRIORITY = Enum.ContextActionPriority.High.Value + 100

local refCount = 0
local guardGeneration = 0
local touchControlsWereEnabled: boolean? = nil

-- Input policy for application panels.
local opts = {
	blockJump = true,
	hideMobileControls = true, -- Hide thumbstick/jump UI while modal
	blockScrollZoom = true, -- Mouse wheel zoom
	blockRMBRotate = true, -- Right-mouse drag rotate
	blockCameraKeys = true, -- I/O zoom, Left/Right rotate
	blockTouchTap = true, -- Sinks generic touch taps
	lockCamera = true, -- Temporarily set CameraType = Scriptable
	disableControls = true, -- PlayerModule controls Disable()
}

-- Movement inputs (WASD/arrows/thumbstick/DPad + jump)
local MOVE_INPUTS: { Enum.KeyCode | Enum.PlayerActions } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Thumbstick1,
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump,
	Enum.KeyCode.Space,
	Enum.KeyCode.ButtonA,
}

local function sink()
	return Enum.ContextActionResult.Sink
end

-- ===== Controls & camera bookkeeping =====
type ControlsApi = {
	controlsEnabled: boolean,
	Enable: (ControlsApi) -> (),
	Disable: (ControlsApi) -> (),
}
type PlayerModuleApi = { GetControls: (PlayerModuleApi) -> ControlsApi }
local Controls: ControlsApi? = nil
local controlsWasEnabled: boolean? = nil
local pendingCharacterConnection: RBXScriptConnection? = nil

local lockedCamera: Camera? = nil
local savedCameraType: Enum.CameraType? = nil
local cameraConnection: RBXScriptConnection? = nil

local function ensureControls()
	if Controls then
		return
	end
	local pmod = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
	-- PlayerModule is injected by Roblox and has no source-backed Rojo module to analyze.
	local PlayerModule = (require :: (ModuleScript) -> PlayerModuleApi)(pmod :: ModuleScript)
	Controls = PlayerModule:GetControls()
end

local function cancelPendingCharacter()
	if pendingCharacterConnection then
		pendingCharacterConnection:Disconnect()
		pendingCharacterConnection = nil
	end
end

local function withCharacter(callback: () -> ())
	cancelPendingCharacter()
	if localPlayer.Character then
		callback()
		return
	end
	-- PlayerModule disabling, including touch visibility changes, calls Player:Move.
	pendingCharacterConnection = localPlayer.CharacterAdded:Connect(function(character)
		if localPlayer.Character == character then
			cancelPendingCharacter()
			callback()
		end
	end)
end

local function disableControls(generation: number)
	if opts.disableControls then
		ensureControls()
	end
	if refCount == 0 or generation ~= guardGeneration then
		return
	end
	withCharacter(function()
		if refCount == 0 or generation ~= guardGeneration then
			return
		end
		if opts.disableControls and Controls then
			if controlsWasEnabled == nil then
				controlsWasEnabled = Controls.controlsEnabled
			end
			if Controls.controlsEnabled then
				Controls:Disable()
			end
		end
		if opts.hideMobileControls and UserInputService.TouchEnabled then
			if touchControlsWereEnabled == nil then
				touchControlsWereEnabled = GuiService.TouchControlsEnabled
			end
			if GuiService.TouchControlsEnabled then
				GuiService.TouchControlsEnabled = false
			end
		end
	end)
end

local function restoreControls(generation: number)
	if controlsWasEnabled == nil and touchControlsWereEnabled == nil then
		return
	end
	withCharacter(function()
		if refCount > 0 or generation ~= guardGeneration then
			return
		end
		if touchControlsWereEnabled and not GuiService.TouchControlsEnabled then
			GuiService.TouchControlsEnabled = true
		end
		touchControlsWereEnabled = nil
		if Controls and controlsWasEnabled and not Controls.controlsEnabled then
			Controls:Enable()
		end
		controlsWasEnabled = nil
	end)
end

local function restoreCamera()
	local camera = lockedCamera
	local previousType = savedCameraType
	lockedCamera = nil
	savedCameraType = nil
	if
		camera
		and camera.Parent
		and previousType
		and camera.CameraType == Enum.CameraType.Scriptable
	then
		camera.CameraType = previousType
	end
	-- CameraSubject is never changed by this guard; respawn and other camera owners keep it.
end

local function lockCurrentCamera()
	if workspace.CurrentCamera == lockedCamera then
		return
	end
	restoreCamera()
	local camera = workspace.CurrentCamera
	if refCount > 0 and opts.lockCamera and camera and camera.Parent then
		lockedCamera = camera
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

local function lockCamera()
	if not opts.lockCamera then
		return
	end
	cameraConnection =
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(lockCurrentCamera)
	lockCurrentCamera()
end

local function unlockCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	restoreCamera()
end

-- ===== ContextActionService binds =====
local function bindMovement()
	local list: { Enum.KeyCode | Enum.PlayerActions } = {}
	for _, code in ipairs(MOVE_INPUTS) do
		local isJumpInput = code == Enum.PlayerActions.CharacterJump
			or code == Enum.KeyCode.Space
			or code == Enum.KeyCode.ButtonA
		if opts.blockJump or not isJumpInput then
			table.insert(list, code)
		end
	end
	ContextActionService:BindActionAtPriority(
		ACTION_MOVE,
		sink,
		false,
		PRIORITY,
		table.unpack(list)
	)
end

local function unbindMovement()
	ContextActionService:UnbindAction(ACTION_MOVE)
end

local function bindCameraBlocks()
	-- Mouse wheel (zoom)
	if opts.blockScrollZoom then
		ContextActionService:BindActionAtPriority(
			ACTION_SCROLL,
			sink,
			false,
			PRIORITY,
			Enum.UserInputType.MouseWheel
		)
	end
	-- Right mouse button (drag to rotate)
	if opts.blockRMBRotate then
		ContextActionService:BindActionAtPriority(
			ACTION_RMB,
			sink,
			false,
			PRIORITY,
			Enum.UserInputType.MouseButton2
		)
	end
	-- Keyboard camera controls (I/O zoom, Left/Right rotate)
	if opts.blockCameraKeys then
		ContextActionService:BindActionAtPriority(
			ACTION_KEYS,
			sink,
			false,
			PRIORITY,
			Enum.KeyCode.I,
			Enum.KeyCode.O,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right
		)
	end
	-- Generic touch taps (extra safety)
	if opts.blockTouchTap and UserInputService.TouchEnabled then
		ContextActionService:BindActionAtPriority(
			ACTION_TOUCH,
			sink,
			false,
			PRIORITY,
			Enum.UserInputType.Touch
		)
	end
end

local function unbindCameraBlocks()
	ContextActionService:UnbindAction(ACTION_SCROLL)
	ContextActionService:UnbindAction(ACTION_RMB)
	ContextActionService:UnbindAction(ACTION_KEYS)
	ContextActionService:UnbindAction(ACTION_TOUCH)
end

-- ===== Public API =====
local InputGuard = {}

function InputGuard.Open()
	refCount += 1
	if refCount == 1 then
		guardGeneration += 1
		local generation = guardGeneration
		cancelPendingCharacter()
		lockCamera()
		bindMovement()
		bindCameraBlocks()
		disableControls(generation)
	end
end

function InputGuard.Close()
	if refCount <= 0 then
		return
	end
	refCount -= 1
	if refCount == 0 then
		guardGeneration += 1
		cancelPendingCharacter()
		unbindMovement()
		unbindCameraBlocks()
		unlockCamera()
		restoreControls(guardGeneration)
	end
end

return InputGuard
