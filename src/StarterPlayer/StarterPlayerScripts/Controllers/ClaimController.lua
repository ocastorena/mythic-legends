-- StarterPlayer/StarterPlayerScripts/Controllers/ClaimController

local ClaimController = {}
local stopImpl: (() -> ())?

function ClaimController.Init(_context: any)
end

function ClaimController.Start()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local ClaimEvent = ReplicatedStorage.Network.World.ClaimState

local Player = Players.LocalPlayer


local TEMPLATE    = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Templates")
	:WaitForChild("Billboards")
	:WaitForChild("ClaimProgressBar")

-- Overhead UI cache: OverheadBars[userId] = { gui = BillboardGui, fill = Frame, tween = Tween }
local OverheadBars = {}

-- Creates or returns an overhead bar for a given player
local function getOverheadBar(forPlayer: Player)
	local userId = forPlayer.UserId
	local entry = OverheadBars[userId]
	if entry and entry.gui and entry.gui.Parent then
		return entry
	end

	local char = forPlayer.Character or forPlayer.CharacterAdded:Wait()
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local billboard = TEMPLATE:Clone()
	billboard.Name = "ClaimProgressBar"
	billboard.Adornee = hrp
	billboard.Enabled = true
	billboard.Parent  = hrp

	entry = {
		gui = billboard,
		fill = billboard.ProgressRoot.Fill,
		tween = nil,
		percent = billboard.ProgressRoot.PercentLabel,
	}
	
	OverheadBars[userId] = entry
	return entry
end

local function hideOverheadBar(userId: number)
	local entry = OverheadBars[userId]
	if not entry then return end
	if entry.tween then
		entry.tween:Cancel()
		entry.tween = nil
	end
	if entry.gui then
		entry.gui:Destroy()
	end
	OverheadBars[userId] = nil
end

local function updateOverheadFromState(payload)
	local userId     = payload.userId
	local mythlingId = payload.mythlingId
	local mode       = payload.mode
	local progress   = payload.progress or 0
	local fillRate   = payload.fillRate
	local drainRate  = payload.drainRate

	-- No active claim: hide
	if not mythlingId or mode == "Idle" then
		hideOverheadBar(userId)
		return
	end

	local plr = Players:GetPlayerByUserId(userId)
	if not plr then
		hideOverheadBar(userId)
		return
	end

	local entry = getOverheadBar(plr)
	if not entry then return end

	-- cancel previous tweens (both bar + percent)
	if entry.tween then
		entry.tween:Cancel()
		entry.tween = nil
	end
	if entry.percentTween then
		entry.percentTween:Cancel()
		entry.percentTween = nil
	end
	if entry.percentValue then
		entry.percentValue:Destroy()
		entry.percentValue = nil
	end

	-- snap bar + text to server snapshot
	local startAlpha = math.clamp(progress / 100, 0, 1)
	entry.fill.Size = UDim2.fromScale(startAlpha, 1)
	entry.percent.Text = string.format("%d%%", math.floor(progress + 0.5))

	-- choose target + duration
	local targetAlpha, duration

	if mode == "Filling" and fillRate and fillRate > 0 then
		targetAlpha = 1
		local remaining = 100 - progress
		duration = remaining / fillRate

	elseif mode == "Draining" and drainRate and drainRate > 0 then
		targetAlpha = 0
		local remaining = progress
		duration = remaining / drainRate

	else
		-- unknown rates or mode: just keep snapshot
		return
	end

	if duration <= 0 then
		entry.fill.Size = UDim2.fromScale(targetAlpha, 1)
		entry.percent.Text = string.format("%d%%", targetAlpha * 100)
		return
	end

	-- NumberValue drives the percent text
	local numberVal = Instance.new("NumberValue")
	numberVal.Value = progress -- 0–100
	entry.percentValue = numberVal

	numberVal.Changed:Connect(function(v)
		-- if GUI was destroyed / cleared mid-tween, abort safely
		if not entry.percent or not entry.percent.Parent then return end
		entry.percent.Text = string.format("%d%%", math.floor(v + 0.5))
	end)

	local percentTween = TweenService:Create(
		numberVal,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Value = targetAlpha * 100 }
	)
	entry.percentTween = percentTween

	percentTween.Completed:Connect(function()
		if entry.percentValue == numberVal then
			entry.percentValue = nil
		end
		numberVal:Destroy()
	end)

	-- Bar fill tween (visual)
	local barTween = TweenService:Create(
		entry.fill,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(targetAlpha, 1) }
	)
	entry.tween = barTween

	percentTween:Play()
	barTween:Play()
end



-- Listen for server events (state + claimed)

local claimConnection = ClaimEvent.OnClientEvent:Connect(function(verb, payload)
	if verb == "StateUpdate" then
		updateOverheadFromState(payload)

	elseif verb == "Claimed" then
		-- optional: emphasize winner, then clear others
		local winnerId = payload.winnerId
		local mythlingId = payload.mythlingId

		-- You can add a little effect here; for now just clear everything non-winner
		for userId, entry in pairs(OverheadBars) do
			if userId ~= winnerId then
				hideOverheadBar(userId)
			else
				-- snap winner to full
				if entry.tween then entry.tween:Cancel() end
				entry.fill.Size = UDim2.fromScale(1, 1)
			end
		end
	end
end)


-- Zone detection lives entirely on the server now. It reads the character's position
-- directly, so this controller only renders the progress bars the server broadcasts.
stopImpl = function()
	claimConnection:Disconnect()
	for userId in OverheadBars do
		hideOverheadBar(userId)
	end
end
end

function ClaimController.Stop()
	if stopImpl then
		stopImpl()
		stopImpl = nil
	end
end

return ClaimController
