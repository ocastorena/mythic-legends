--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/ClaimController
-- Restartable presentation of server-confirmed capture progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Trove = require(ReplicatedStorage.Packages.Trove)

type TroveInstance = Trove.Trove
type Bar = { gui: BillboardGui, fill: Frame, percent: TextLabel, motion: TroveInstance }
local ClaimController = {}
local lifetime = Trove.new()
local isRunning = false
local generation = 0
local overheadBars: { [number]: Bar } = {}

local function hideBar(userId: number)
	local bar = overheadBars[userId]
	if bar then
		bar.motion:Destroy()
		bar.gui:Destroy()
		overheadBars[userId] = nil
	end
end

function ClaimController.Init(_context: unknown) end

function ClaimController.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	local template = ReplicatedStorage:WaitForChild("Assets")
		:WaitForChild("Templates")
		:WaitForChild("Billboards")
		:WaitForChild("ClaimProgressBar")
	local claimEvent = ReplicatedStorage.Network.World.ClaimState
	if not isRunning or generation ~= currentGeneration then
		return
	end
	assert(
		template:IsA("BillboardGui"),
		"[ClaimController] ClaimProgressBar must be a BillboardGui"
	)
	local function getBar(player: Player): Bar?
		local existing = overheadBars[player.UserId]
		if existing and existing.gui.Parent then
			return existing
		end
		hideBar(player.UserId)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return nil
		end
		local gui = template:Clone()
		local progressRoot = gui:FindFirstChild("ProgressRoot")
		local fill = progressRoot and progressRoot:FindFirstChild("Fill")
		local percent = progressRoot and progressRoot:FindFirstChild("PercentLabel")
		if not fill or not fill:IsA("Frame") or not percent or not percent:IsA("TextLabel") then
			gui:Destroy()
			warn("[ClaimController] ClaimProgressBar is missing its Fill or PercentLabel")
			return nil
		end
		gui.Adornee = root
		gui.Enabled = true
		gui.Parent = root
		local bar = { gui = gui, fill = fill, percent = percent, motion = Trove.new() }
		overheadBars[player.UserId] = bar
		return bar
	end
	lifetime:Connect(claimEvent.OnClientEvent, function(verb: unknown, rawPayload: unknown)
		if not isRunning or type(rawPayload) ~= "table" then
			return
		end
		local payload = rawPayload :: { [string]: unknown }
		if verb == "Claimed" then
			for userId, bar in overheadBars do
				if userId == payload.winnerId then
					bar.motion:Clean()
					bar.fill.Size = UDim2.fromScale(1, 1)
					bar.percent.Text = "100%"
				else
					hideBar(userId)
				end
			end
			return
		end
		if verb ~= "StateUpdate" or type(payload.userId) ~= "number" then
			return
		end
		local userId = payload.userId
		if not payload.mythlingId or payload.mode == "Idle" then
			hideBar(userId)
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		local bar = player and getBar(player)
		if not bar then
			return
		end
		bar.motion:Clean()
		local progress = if type(payload.progress) == "number" then payload.progress else 0
		bar.fill.Size = UDim2.fromScale(math.clamp(progress / 100, 0, 1), 1)
		bar.percent.Text = string.format("%d%%", math.floor(progress + 0.5))
		local target: number
		local duration: number
		if
			payload.mode == "Filling"
			and type(payload.fillRate) == "number"
			and payload.fillRate > 0
		then
			target = 100
			duration = (100 - progress) / payload.fillRate
		elseif
			payload.mode == "Draining"
			and type(payload.drainRate) == "number"
			and payload.drainRate > 0
		then
			target = 0
			duration = progress / payload.drainRate
		else
			return
		end
		if duration <= 0 then
			bar.fill.Size = UDim2.fromScale(target / 100, 1)
			bar.percent.Text = string.format("%d%%", target)
			return
		end
		local value = Instance.new("NumberValue")
		value.Value = progress
		bar.motion:Add(value)
		bar.motion:Connect(value.Changed, function(current: number)
			bar.fill.Size = UDim2.fromScale(math.clamp(current / 100, 0, 1), 1)
			bar.percent.Text = string.format("%d%%", math.floor(current + 0.5))
		end)
		local tween = TweenService:Create(
			value,
			TweenInfo.new(duration, Enum.EasingStyle.Linear),
			{ Value = target }
		)
		bar.motion:Add(tween, "Cancel")
		tween:Play()
	end)
	lifetime:Connect(Players.PlayerRemoving, function(player)
		hideBar(player.UserId)
	end)
end

function ClaimController.Stop()
	isRunning = false
	generation += 1
	lifetime:Clean()
	for userId in overheadBars do
		hideBar(userId)
	end
end

return ClaimController
