--!strict
-- ReplicatedFirst/LoadingScreen
-- Keeps startup visually simple while required world and UI assets load.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

type Controls = {
	controlsEnabled: boolean?,
	Enable: (Controls, boolean?) -> (),
	Disable: (Controls) -> (),
}
type PlayerModuleApi = { GetControls: (PlayerModuleApi) -> Controls }
-- Roblox injects PlayerModule at runtime; it is intentionally absent from the Rojo map.
local requirePlayerModule = require :: (ModuleScript) -> PlayerModuleApi

local LOAD_TIMEOUT_SECONDS = 30
local MIN_DISPLAY_SECONDS = 1.5
local STREAM_TIMEOUT_SECONDS = 6
local PRELOAD_BATCH_SIZE = 12
local FADE_SECONDS = 0.4
local MOVEMENT_LOCK_ACTION = "LoadingScreenMovementLock"
local CAMERA_LOCK_ACTION = "LoadingScreenCameraLock"

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local displayedAt = os.clock()
local isDismissed = false
local isAlive = true
local isMovementLocked = true
local movementControls: Controls? = nil
local wereControlsEnabled: boolean? = nil
local lockedCamera: Camera? = nil
local savedCameraType: Enum.CameraType? = nil
local wasTopbarEnabled: boolean? = nil
local lifetime = Trove.new()
local loadingTasks = lifetime:Extend()
local progressMotion = lifetime:Extend()

local function deferLoading(callback: () -> ())
	local thread = task.defer(function()
		callback()
		loadingTasks:Pop(coroutine.running())
	end)
	loadingTasks:Add(thread)
end

local function sinkMovement(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

-- Sink cross-platform character actions immediately, before PlayerModule finishes loading.
-- PlayerActions is supported by this engine API but omitted from the generated signature.
local bindPlayerActions = ContextActionService.BindActionAtPriority :: (
	ContextActionService,
	string,
	(string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult,
	boolean,
	number,
	...Enum.PlayerActions
) -> ()
bindPlayerActions(
	ContextActionService,
	MOVEMENT_LOCK_ACTION,
	sinkMovement,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump
)

ContextActionService:BindActionAtPriority(
	CAMERA_LOCK_ACTION,
	sinkMovement,
	false,
	Enum.ContextActionPriority.High.Value + 100,
	Enum.UserInputType.MouseMovement,
	Enum.UserInputType.MouseWheel,
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.Touch,
	Enum.KeyCode.Thumbstick2,
	Enum.KeyCode.I,
	Enum.KeyCode.O
)

local function restoreCamera()
	if
		lockedCamera
		and savedCameraType
		and lockedCamera.CameraType == Enum.CameraType.Scriptable
	then
		lockedCamera.CameraType = savedCameraType
	end
	lockedCamera = nil
	savedCameraType = nil
end

local function lockCurrentCamera()
	local camera = workspace.CurrentCamera
	if camera == lockedCamera then
		return
	end
	restoreCamera()
	if camera then
		lockedCamera = camera
		savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

lockCurrentCamera()
lifetime:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), lockCurrentCamera)

-- Disabling the standard controls also hides mobile locomotion input from the character.
deferLoading(function()
	local success, controls = pcall(function()
		local playerScripts = localPlayer:WaitForChild("PlayerScripts")
		local module = playerScripts:WaitForChild("PlayerModule")
		assert(module:IsA("ModuleScript"), "[LoadingScreen] Expected Roblox PlayerModule")
		local PlayerModule = requirePlayerModule(module)
		return PlayerModule:GetControls()
	end)
	if not success or not controls or not isAlive or isDismissed then
		return
	end
	movementControls = controls
	wereControlsEnabled = controls.controlsEnabled
	if isMovementLocked and wereControlsEnabled ~= nil then
		pcall(function()
			controls:Disable()
		end)
	end
end)

local function releaseMovement()
	if not isMovementLocked then
		return
	end
	isMovementLocked = false
	ContextActionService:UnbindAction(MOVEMENT_LOCK_ACTION)
	local controls = movementControls
	if controls and wereControlsEnabled ~= nil and controls.controlsEnabled == false then
		pcall(function()
			controls:Enable(wereControlsEnabled)
		end)
	end
end

local function releaseCamera()
	ContextActionService:UnbindAction(CAMERA_LOCK_ACTION)
	restoreCamera()
end

local function cleanup()
	if not isAlive then
		return
	end
	isAlive = false
	isDismissed = true
	-- Dismiss can run on an owned loading/timeout thread; never cancel the cleanup itself.
	loadingTasks:Pop(coroutine.running())
	lifetime:Pop(coroutine.running())
	lifetime:Destroy()
	releaseMovement()
	releaseCamera()
	if wasTopbarEnabled ~= nil then
		pcall(function()
			if StarterGui:GetCore("TopbarEnabled") == false then
				StarterGui:SetCore("TopbarEnabled", wasTopbarEnabled)
			end
		end)
	end
end

lifetime:Connect(script.Destroying, cleanup)

--------------------------------------------------------------------------------
-- Minimal presentation
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.DisplayOrder = 10_000
screenGui.IgnoreGuiInset = true
screenGui.ScreenInsets = Enum.ScreenInsets.None
screenGui.ClipToDeviceSafeArea = false
screenGui.ResetOnSpawn = false

local background = Instance.new("CanvasGroup")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(7, 12, 20)
background.BorderSizePixel = 0
background.Parent = screenGui

local loadingLabel = Instance.new("TextLabel")
loadingLabel.Name = "LoadingLabel"
loadingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
loadingLabel.Position = UDim2.fromScale(0.5, 0.47)
loadingLabel.Size = UDim2.fromOffset(240, 52)
loadingLabel.BackgroundTransparency = 1
loadingLabel.FontFace = Font.fromName("Nunito", Enum.FontWeight.ExtraBold)
loadingLabel.Text = "Loading..."
loadingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
loadingLabel.TextSize = 28
loadingLabel.Parent = background

local progressTrough = Instance.new("Frame")
progressTrough.Name = "ProgressTrough"
progressTrough.AnchorPoint = Vector2.new(0.5, 0.5)
progressTrough.Position = UDim2.fromScale(0.5, 0.54)
progressTrough.Size = UDim2.new(0.42, 0, 0, 8)
progressTrough.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
progressTrough.BackgroundTransparency = 0.82
progressTrough.BorderSizePixel = 0
progressTrough.ClipsDescendants = true
progressTrough.Parent = background

local troughSize = Instance.new("UISizeConstraint")
troughSize.MinSize = Vector2.new(220, 8)
troughSize.MaxSize = Vector2.new(420, 8)
troughSize.Parent = progressTrough

local troughCorner = Instance.new("UICorner")
troughCorner.CornerRadius = UDim.new(1, 0)
troughCorner.Parent = progressTrough

local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = Color3.fromRGB(74, 163, 255)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressTrough

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = progressFill

screenGui.Parent = playerGui
lifetime:Add(screenGui)
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- CoreGui can register just after ReplicatedFirst runs. Repeat the request briefly so the
-- platform chrome cannot appear over the otherwise minimal loading screen.
deferLoading(function()
	for _ = 1, 10 do
		if isDismissed then
			return
		end
		pcall(function()
			if wasTopbarEnabled == nil then
				local current: unknown = StarterGui:GetCore("TopbarEnabled")
				if type(current) ~= "boolean" then
					return
				end
				wasTopbarEnabled = current
			end
			StarterGui:SetCore("TopbarEnabled", false)
		end)
		task.wait(0.1)
	end
end)

local displayedProgress = 0

local function setProgress(nextProgress: number)
	if not isAlive or isDismissed then
		return
	end
	displayedProgress = math.max(displayedProgress, math.clamp(nextProgress, 0, 1))
	progressMotion:Clean()
	local tween = TweenService:Create(
		progressFill,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(displayedProgress, 1) }
	)
	progressMotion:Add(tween)
	tween:Play()
end

--------------------------------------------------------------------------------
-- World readiness
--------------------------------------------------------------------------------

local function criticalWorldReady(): boolean
	local map = workspace:FindFirstChild("Map")
	if not map then
		return false
	end

	local arena = map:FindFirstChild("Arena")
	local floatingIsland = map:FindFirstChild("FloatingIsland")
	local baseIslands = map:FindFirstChild("BaseIslands")
	if not (arena and arena:IsA("BasePart") and floatingIsland and baseIslands) then
		return false
	end
	if #floatingIsland:GetDescendants() < 67 then
		return false
	end

	for index = 0, 7 do
		local island = baseIslands:FindFirstChild("BaseIsland" .. index)
		local grass = island and island:FindFirstChild("Grass")
		local hasVisualGeometry = false
		if island then
			for _, descendant in island:GetDescendants() do
				if descendant:IsA("BasePart") and descendant ~= grass then
					hasVisualGeometry = true
					break
				end
			end
		end
		if
			not (
				island
				and island:IsA("Model")
				and grass
				and grass:IsA("BasePart")
				and hasVisualGeometry
			)
		then
			return false
		end
	end
	return true
end

local function waitForCriticalWorld(maxWaitSeconds: number)
	local deadline = os.clock() + maxWaitSeconds
	while not isDismissed and not criticalWorldReady() and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function streamCoreWorld()
	if not workspace.StreamingEnabled then
		return
	end

	local map = workspace:FindFirstChild("Map")
	local baseIslands = map and map:FindFirstChild("BaseIslands")
	local arena = map and map:FindFirstChild("Arena")
	if not (map and baseIslands and arena and arena:IsA("BasePart")) then
		return
	end

	local positions = { arena.Position }
	for index = 0, 7 do
		local island = baseIslands:FindFirstChild("BaseIsland" .. index)
		if island and island:IsA("Model") then
			table.insert(positions, island:GetPivot().Position)
		end
	end

	local remaining = #positions
	for _, position in ipairs(positions) do
		deferLoading(function()
			pcall(function()
				localPlayer:RequestStreamAroundAsync(position, STREAM_TIMEOUT_SECONDS)
			end)
			remaining -= 1
		end)
	end

	local deadline = os.clock() + STREAM_TIMEOUT_SECONDS
	while not isDismissed and remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function waitForRuntimeBase(maxWaitSeconds: number)
	local runtime = workspace:FindFirstChild("Runtime")
	local bases = runtime and runtime:FindFirstChild("Bases")
	if not bases then
		return
	end

	local baseName = tostring(localPlayer.UserId)
	local deadline = os.clock() + maxWaitSeconds
	while not isDismissed and not bases:FindFirstChild(baseName) and os.clock() < deadline do
		task.wait(0.1)
	end
end

--------------------------------------------------------------------------------
-- Asset loading
--------------------------------------------------------------------------------

local function isPreloadable(instance: Instance): boolean
	return instance:IsA("MeshPart")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("ImageLabel")
		or instance:IsA("ImageButton")
		or instance:IsA("Sound")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Animation")
		or instance:IsA("SpecialMesh")
		or instance:IsA("Sky")
		or instance:IsA("Shirt")
		or instance:IsA("Pants")
		or instance:IsA("ShirtGraphic")
		or instance:IsA("CharacterMesh")
end

local function appendPreloadables(
	target: { Instance },
	seen: { [Instance]: boolean },
	root: Instance?
)
	if not root then
		return
	end
	if isPreloadable(root) and not seen[root] then
		seen[root] = true
		table.insert(target, root)
	end
	for _, instance in root:GetDescendants() do
		if isPreloadable(instance) and not seen[instance] then
			seen[instance] = true
			table.insert(target, instance)
		end
	end
end

local function appendGeometry(target: { Instance }, seen: { [Instance]: boolean }, root: Instance?)
	if not root then
		return
	end
	if root:IsA("BasePart") and not seen[root] then
		seen[root] = true
		table.insert(target, root)
	end
	for _, instance in root:GetDescendants() do
		if instance:IsA("BasePart") and not seen[instance] then
			seen[instance] = true
			table.insert(target, instance)
		end
	end
end

local function assetRoots(): { Instance }
	local roots: { Instance } = {
		workspace,
		game:GetService("Lighting"),
		game:GetService("SoundService"),
		game:GetService("ReplicatedStorage"),
		game:GetService("StarterGui"),
		game:GetService("StarterPack"),
		playerGui,
	}
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(roots, backpack)
	end
	return roots
end

local function countPresentPreloadables(): number
	local count = 0
	for _, root in ipairs(assetRoots()) do
		if isPreloadable(root) then
			count += 1
		end
		for _, instance in root:GetDescendants() do
			if isPreloadable(instance) then
				count += 1
			end
		end
	end
	return count
end

local function waitForAssetPopulation(maxWaitSeconds: number)
	local deadline = os.clock() + maxWaitSeconds
	local lastCount = -1
	local stableSince = os.clock()
	while not isDismissed and os.clock() < deadline do
		local currentCount = countPresentPreloadables()
		if currentCount ~= lastCount then
			lastCount = currentCount
			stableSince = os.clock()
		elseif os.clock() - stableSince >= 0.75 then
			return
		end
		task.wait(0.15)
	end
end

local function collectAssets(): { Instance }
	local assets = {}
	local seen: { [Instance]: boolean } = {}
	for _, root in ipairs(assetRoots()) do
		appendPreloadables(assets, seen, root)
	end

	-- Let the Arena stream and render naturally instead of blocking startup on more than a
	-- thousand static parts. Only the authored spawn-island geometry is explicitly preloaded.
	local map = workspace:FindFirstChild("Map")
	if map then
		appendGeometry(assets, seen, map:FindFirstChild("FloatingIsland"))

		local baseIslands = map:FindFirstChild("BaseIslands")
		if baseIslands then
			for index = 0, 7 do
				appendGeometry(assets, seen, baseIslands:FindFirstChild("BaseIsland" .. index))
			end
		end
	end
	return assets
end

local function preloadAssets(assets: { Instance }, startProgress: number)
	if #assets == 0 then
		setProgress(1)
		return
	end
	for startIndex = 1, #assets, PRELOAD_BATCH_SIZE do
		if isDismissed then
			return
		end
		local batch = {}
		local endIndex = math.min(startIndex + PRELOAD_BATCH_SIZE - 1, #assets)
		for index = startIndex, endIndex do
			table.insert(batch, assets[index])
		end
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		local completed = endIndex / #assets
		setProgress(startProgress + (1 - startProgress) * completed)
	end
end

--------------------------------------------------------------------------------
-- Completion
--------------------------------------------------------------------------------

local function dismiss()
	if isDismissed or not isAlive then
		return
	end
	setProgress(1)
	isDismissed = true
	loadingTasks:Pop(coroutine.running())
	loadingTasks:Clean()
	-- Adopt a loading thread that is now finishing the fade instead of preloading.
	lifetime:Add(coroutine.running())

	local remaining = MIN_DISPLAY_SECONDS - (os.clock() - displayedAt)
	if remaining > 0 then
		task.wait(remaining)
	end
	if not isAlive then
		return
	end

	local fadeInfo = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTweens: { Tween } = {}
	local function addFadeTween(guiObject: GuiObject)
		local goals: { [string]: number } = {
			BackgroundTransparency = 1,
		}
		if
			guiObject:IsA("TextLabel")
			or guiObject:IsA("TextButton")
			or guiObject:IsA("TextBox")
		then
			goals.TextTransparency = 1
			goals.TextStrokeTransparency = 1
		elseif guiObject:IsA("ImageLabel") or guiObject:IsA("ImageButton") then
			goals.ImageTransparency = 1
		end
		local tween = TweenService:Create(guiObject, fadeInfo, goals)
		lifetime:Add(tween)
		table.insert(fadeTweens, tween)
	end

	-- Fade every rendered property explicitly so CanvasGroup child rendering cannot
	-- outlive the full-screen background on slower startup frames.
	addFadeTween(background)
	for _, descendant in background:GetDescendants() do
		if descendant:IsA("GuiObject") then
			addFadeTween(descendant)
		end
	end
	for _, tween in fadeTweens do
		tween:Play()
	end
	fadeTweens[1].Completed:Wait()

	cleanup()
end

loadingTasks:Add(task.delay(LOAD_TIMEOUT_SECONDS, dismiss))

deferLoading(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	if isDismissed then
		return
	end

	setProgress(0.08)
	waitForCriticalWorld(6)
	setProgress(0.2)
	streamCoreWorld()
	setProgress(0.4)
	waitForRuntimeBase(4)
	setProgress(0.48)
	waitForAssetPopulation(3)
	setProgress(0.55)
	preloadAssets(collectAssets(), 0.55)
	-- Give the renderer a brief quiet window after the essential preload completes.
	task.wait(1)
	dismiss()
end)
