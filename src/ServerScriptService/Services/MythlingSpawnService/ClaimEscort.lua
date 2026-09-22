--!strict
-- ServerScriptService/Services/MythlingSpawnService/ClaimEscort
-- Claimed-model presentation has an encounter-owned, cancellable lifetime.

local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Trove = require(ReplicatedStorage.Packages.Trove)
local ServerTypes = require(ServerScriptService.Domain.Types)
local LogUtil = require(ServerScriptService.Infrastructure.LogUtil)
local log = LogUtil.For("MythlingSpawnService.ClaimEscort")
local ClaimEscort = {}

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

-- Plays a looping Walking animation if present; returns a cleanup callback.
local function playWalkingAnimation(model: Model): (() -> ())?
	local animationsFolder = model:FindFirstChild("Animations") or model:FindFirstChild("Animation")
	if not animationsFolder then
		return nil
	end

	local walking = animationsFolder:FindFirstChild("Walking")
	if not (walking and walking:IsA("Animation")) then
		return nil
	end

	local animator = getAnimator(model)
	if not animator then
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(walking)
	end)
	if not ok or not track then
		return nil
	end

	track.Looped = true
	track:Play()

	local destroyingConn: RBXScriptConnection?
	destroyingConn = model.Destroying:Connect(function()
		if destroyingConn then
			destroyingConn:Disconnect()
		end
		if track then
			pcall(function()
				track:Stop()
			end)
		end
	end)

	return function()
		if destroyingConn then
			destroyingConn:Disconnect()
			destroyingConn = nil
		end
		if track then
			pcall(function()
				track:Stop()
			end)
		end
	end
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
			local stopWalking = playWalkingAnimation(entry.model)
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
				local facing = CFrame.lookAt(root.Position, target)
				local destination = CFrame.new(target) * (facing - facing.Position)
				local durationSeconds = math.max((target - root.Position).Magnitude / 4, 0.05)
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
