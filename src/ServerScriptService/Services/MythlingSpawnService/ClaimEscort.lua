--!strict
-- ServerScriptService/Services/MythlingSpawnService/ClaimEscort
-- Idle and escort presentation have encounter-owned, cancellable lifetimes.

local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerTypes = require(ServerScriptService.Shared.Types)
local LogUtil = require(ServerScriptService.Infrastructure.LogUtil)
local log = LogUtil.For("MythlingSpawnService.ClaimEscort")
local ClaimEscort = {}
local MIN_WAYPOINT_DISTANCE = 1e-4

-- Tries to create or find an Animator on the model (Humanoid or AnimationController).
local function getAnimator(model: Model): Animator?
	if not model then
		return nil
	end

	-- Prefer an existing Humanoid
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildWhichIsA("Animator")
		if animator then
			return animator
		end
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		return newAnimator
	end

	-- Fallback to an AnimationController
	local controller: AnimationController? = model:FindFirstChildWhichIsA("AnimationController")
	if not controller then
		local created = Instance.new("AnimationController")
		created.Name = "AnimationController"
		created.Parent = model
		controller = created
	end
	assert(controller, "[MythlingSpawnService.ClaimEscort] Animation controller is unavailable")
	local animator = controller:FindFirstChildWhichIsA("Animator")
	if animator then
		return animator
	end
	local newAnimator = Instance.new("Animator")
	newAnimator.Parent = controller
	return newAnimator
end

-- Optional clips are authored on the template; their playback belongs to the cloned model.
local function playLoopingAnimation(
	model: Model,
	animationName: string,
	priority: Enum.AnimationPriority
): (() -> ())?
	local animationsFolder = model:FindFirstChild("Animations") or model:FindFirstChild("Animation")
	local animation = animationsFolder and animationsFolder:FindFirstChild(animationName)
	if not (animation and animation:IsA("Animation")) or not animation.AnimationId:match("%S") then
		return nil
	end

	local animator = getAnimator(model)
	if not animator then
		return nil
	end

	local loaded, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not loaded or not track then
		log.warn(`Could not load {animationName} animation for {model.Name}: {track}`)
		return nil
	end

	local isCleaned = false
	local destroyingConn: RBXScriptConnection?
	local function cleanup()
		if isCleaned then
			return
		end
		isCleaned = true
		if destroyingConn then
			destroyingConn:Disconnect()
			destroyingConn = nil
		end
		pcall(function()
			track:Stop(0)
		end)
		pcall(function()
			track:Destroy()
		end)
	end
	destroyingConn = model.Destroying:Connect(cleanup)

	local started, startProblem = pcall(function()
		track.Looped = true
		track.Priority = priority
		track:Play()
		if animationName == "Walking" then
			track:AdjustSpeed(1.75)
		end
	end)
	if not started then
		cleanup()
		log.warn(`Could not play {animationName} animation for {model.Name}: {startProblem}`)
		return nil
	end
	return cleanup
end

function ClaimEscort.StartIdle(model: Model): (() -> ())?
	return playLoopingAnimation(model, "Idle", Enum.AnimationPriority.Idle)
end

function ClaimEscort.Start(
	entry: ServerTypes.SpawnEntry,
	baseAnchor: BasePart,
	owner: Trove.Trove,
	onComplete: () -> ()
)
	local isActive = true
	owner:Add(function()
		isActive = false
	end)
	owner:Add(task.defer(function()
		local root = entry.model.PrimaryPart
		if not root then
			owner:Pop(coroutine.running())
			onComplete()
			return
		end
		local path = owner:Add(PathfindingService:CreatePath({
			AgentRadius = 4,
			AgentHeight = 6,
			AgentCanJump = false,
			WaypointSpacing = 4,
		}))
		local success, errorMessage = pcall(function()
			path:ComputeAsync(
				root.Position,
				Vector3.new(baseAnchor.Position.X, root.Position.Y, baseAnchor.Position.Z)
			)
		end)
		if not isActive or not entry.model.Parent then
			return
		end
		if success then
			local stopWalking =
				playLoopingAnimation(entry.model, "Walking", Enum.AnimationPriority.Movement)
			if stopWalking then
				owner:Add(function()
					stopWalking()
				end)
			end
			for _, waypoint in path:GetWaypoints() do
				if not isActive or not root.Parent then
					return
				end
				local target =
					Vector3.new(waypoint.Position.X, root.Position.Y, waypoint.Position.Z)
				local distance = (target - root.Position).Magnitude
				-- Start and repeated end waypoints can already match the root position.
				if distance <= MIN_WAYPOINT_DISTANCE then
					continue
				end
				local facing = CFrame.lookAt(root.Position, target)
				local destination = CFrame.new(target) * (facing - facing.Position)
				local durationSeconds = math.max(distance / 4, 0.05)
				local tween = TweenService:Create(
					root,
					TweenInfo.new(durationSeconds, Enum.EasingStyle.Linear),
					{ CFrame = destination }
				)
				local function cleanupTween()
					tween:Cancel()
					tween:Destroy()
				end
				owner:Add(cleanupTween)
				tween:Play()
				tween.Completed:Wait()
				owner:Remove(cleanupTween)
			end
		else
			log.warn(`Escort pathfinding failed for {entry.id}: {errorMessage}`)
		end
		if isActive then
			owner:Pop(coroutine.running())
			onComplete()
		end
	end))
end

return ClaimEscort
