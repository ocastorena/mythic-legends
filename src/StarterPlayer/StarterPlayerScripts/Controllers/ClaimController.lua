--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/ClaimController
-- Restartable presentation of server-confirmed capture progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Trove = require(ReplicatedStorage.Packages.Trove)

type TroveInstance = Trove.Trove
type Bar = {
	gui: BillboardGui,
	fill: Frame,
	percent: TextLabel,
	motion: TroveInstance,
	character: Model,
	mythlingId: string,
}
local MAX_UNCONFIRMED_PROGRESS = 99
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
	local characters: { [Player]: Model } = {}
	local playerLifetimes: { [Player]: TroveInstance } = {}
	local lastSamples: { [number]: number } = {}
	local function watchPlayer(player: Player)
		if playerLifetimes[player] then
			return
		end
		local playerLifetime = lifetime:Extend()
		playerLifetimes[player] = playerLifetime
		characters[player] = player.Character
		playerLifetime:Connect(player.CharacterRemoving, function(character)
			if characters[player] == character then
				characters[player] = nil
				hideBar(player.UserId)
			end
		end)
		playerLifetime:Connect(player.CharacterAdded, function(character)
			hideBar(player.UserId)
			characters[player] = character
		end)
	end
	lifetime:Connect(Players.PlayerAdded, watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	local function getBar(player: Player, character: Model, mythlingId: string): Bar?
		local existing = overheadBars[player.UserId]
		if existing and existing.gui.Parent and existing.character == character then
			existing.mythlingId = mythlingId
			return existing
		end
		hideBar(player.UserId)
		local root = character:FindFirstChild("HumanoidRootPart")
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
		local bar = {
			gui = gui,
			fill = fill,
			percent = percent,
			motion = Trove.new(),
			character = character,
			mythlingId = mythlingId,
		}
		overheadBars[player.UserId] = bar
		return bar
	end
	lifetime:Connect(claimEvent.OnClientEvent, function(verb: unknown, rawPayload: unknown)
		if not isRunning or type(rawPayload) ~= "table" then
			return
		end
		local payload = rawPayload :: { [string]: unknown }
		if verb == "Claimed" then
			if type(payload.mythlingId) ~= "string" then
				return
			end
			for userId, bar in overheadBars do
				if bar.mythlingId ~= payload.mythlingId then
					continue
				end
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
		local player = Players:GetPlayerByUserId(userId)
		local character = player and characters[player]
		if not player or payload.character ~= character or player.Character ~= character then
			return
		end
		local sampledAt = if type(payload.sampledAt) == "number"
			then payload.sampledAt
			else workspace:GetServerTimeNow()
		local lastSample = lastSamples[userId]
		if lastSample and sampledAt < lastSample then
			return
		end
		lastSamples[userId] = sampledAt
		if not payload.mythlingId or payload.mode == "Idle" then
			hideBar(userId)
			return
		end
		if not character or type(payload.mythlingId) ~= "string" then
			return
		end
		local bar = getBar(player, character, payload.mythlingId)
		if not bar then
			return
		end
		bar.motion:Clean()
		if payload.mode == "Full" then
			bar.fill.Size = UDim2.fromScale(0, 1)
			bar.percent.Text = "Inventory full"
			return
		end
		local progress = if type(payload.progress) == "number" then payload.progress else 0
		local elapsed = math.max(0, workspace:GetServerTimeNow() - sampledAt)
		if payload.mode == "Filling" and type(payload.fillRate) == "number" then
			progress += math.max(0, payload.fillRate) * elapsed
		elseif payload.mode == "Draining" and type(payload.drainRate) == "number" then
			progress -= math.max(0, payload.drainRate) * elapsed
		end
		-- Only a server-confirmed win presents 100%; interpolation never awards a capture.
		progress = math.clamp(progress, 0, MAX_UNCONFIRMED_PROGRESS)
		bar.fill.Size = UDim2.fromScale(math.clamp(progress / 100, 0, 1), 1)
		bar.percent.Text = string.format("%d%%", math.floor(progress + 0.5))
		local target: number
		local duration: number
		if
			payload.mode == "Filling"
			and type(payload.fillRate) == "number"
			and payload.fillRate > 0
		then
			target = MAX_UNCONFIRMED_PROGRESS
			duration = (target - progress) / payload.fillRate
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
		characters[player] = nil
		lastSamples[player.UserId] = nil
		local playerLifetime = playerLifetimes[player]
		if playerLifetime then
			lifetime:Remove(playerLifetime)
			playerLifetimes[player] = nil
		end
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
