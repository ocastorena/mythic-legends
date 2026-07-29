-- ReplicatedFirst/LoadingScreen
-- Keeps startup visually simple while the complete core world and its external assets load.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LOAD_TIMEOUT_SECONDS = 20
local MIN_DISPLAY_SECONDS = 1.5
local STREAM_TIMEOUT_SECONDS = 6
local PRELOAD_BATCH_SIZE = 12
local FADE_SECONDS = 0.4

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local displayedAt = os.clock()
local dismissed = false

--------------------------------------------------------------------------------
-- Minimal presentation
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.DisplayOrder = 10_000
screenGui.IgnoreGuiInset = true
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
progressFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressTrough

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = progressFill

screenGui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- CoreGui can register just after ReplicatedFirst runs. Repeat the request briefly so the
-- platform chrome cannot appear over the otherwise minimal loading screen.
task.spawn(function()
	for _ = 1, 10 do
		if dismissed then
			return
		end
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end)
		task.wait(0.1)
	end
end)

local displayedProgress = 0

local function setProgress(nextProgress: number)
	displayedProgress = math.max(displayedProgress, math.clamp(nextProgress, 0, 1))
	TweenService:Create(
		progressFill,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(displayedProgress, 1) }
	):Play()
end

--------------------------------------------------------------------------------
-- World readiness
--------------------------------------------------------------------------------

local function criticalWorldReady(): boolean
	local map = workspace:FindFirstChild("Map")
	if not map then
		return false
	end

	local arenaStructure = map:FindFirstChild("ArenaStructure")
	local arenaBridges = map:FindFirstChild("ArenaBridges")
	local arena = map:FindFirstChild("Arena")
	local baseIslands = map:FindFirstChild("BaseIslands")
	if not (arenaStructure and arenaBridges and arena and baseIslands) then
		return false
	end
	if #arenaStructure:GetDescendants() == 0 or #arenaBridges:GetDescendants() == 0 then
		return false
	end

	for index = 0, 7 do
		local island = baseIslands:FindFirstChild("BaseIsland" .. index)
		if not (island and island:IsA("Model") and island:FindFirstChild("Grass")) then
			return false
		end
	end
	return true
end

local function waitForCriticalWorld(maxWaitSeconds: number)
	local deadline = os.clock() + maxWaitSeconds
	while not dismissed and not criticalWorldReady() and os.clock() < deadline do
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
		task.spawn(function()
			pcall(function()
				localPlayer:RequestStreamAroundAsync(position, STREAM_TIMEOUT_SECONDS)
			end)
			remaining -= 1
		end)
	end

	local deadline = os.clock() + STREAM_TIMEOUT_SECONDS
	while not dismissed and remaining > 0 and os.clock() < deadline do
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
	while not dismissed and not bases:FindFirstChild(baseName) and os.clock() < deadline do
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

local function appendPreloadables(target: { Instance }, seen: { [Instance]: boolean }, root: Instance?)
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
	while not dismissed and os.clock() < deadline do
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
	return assets
end

local function preloadAssets(assets: { Instance }, startProgress: number)
	if #assets == 0 then
		setProgress(1)
		return
	end
	for startIndex = 1, #assets, PRELOAD_BATCH_SIZE do
		if dismissed then
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
	if dismissed then
		return
	end
	dismissed = true
	setProgress(1)

	local remaining = MIN_DISPLAY_SECONDS - (os.clock() - displayedAt)
	if remaining > 0 then
		task.wait(remaining)
	end

	local tween = TweenService:Create(
		background,
		TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Wait()

	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)
	screenGui:Destroy()
end

task.delay(LOAD_TIMEOUT_SECONDS, dismiss)

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	if dismissed then
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
	dismiss()
end)
