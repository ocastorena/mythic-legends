-- StarterCharacterScripts/ClaimClient

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")

local ClaimEvent        = ReplicatedStorage.Remotes.ClaimEvent

local Player = Players.LocalPlayer
local Char   = Player.Character or Player.CharacterAdded:Wait()
local Hum    = Char:WaitForChild("Humanoid")
local Hrp    = Char:WaitForChild("HumanoidRootPart")

local INTERVAL = 0.2

local TEMPLATE    = ReplicatedStorage:WaitForChild("Templates")
	:WaitForChild("GUI")
	:WaitForChild("ProgressBar")

-- Cache all mythling zones
local mythlingZones = CollectionService:GetTagged("MythlingZone")
CollectionService:GetInstanceAddedSignal("MythlingZone"):Connect(function(part)
	table.insert(mythlingZones, part)
end)
CollectionService:GetInstanceRemovedSignal("MythlingZone"):Connect(function(part)
	local i = table.find(mythlingZones, part)
	if i then table.remove(mythlingZones, i) end
end)


local ClaimState = { state = "OutZone", zone = nil }

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
	billboard.Name = "ProgressBar"
	billboard.Adornee = hrp
	billboard.Enabled = true
	billboard.Parent  = hrp

	entry = {
		gui = billboard,
		fill = billboard.Background.Bar,
		tween = nil,
		percent = billboard.Background.Percent,
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

ClaimEvent.OnClientEvent:Connect(function(verb, payload)
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


-- Zone detection (unchanged except verbs payload shape)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < INTERVAL then return end
	acc -= INTERVAL

	local pos = Hrp.Position
	local inAny = false

	for _, zone in ipairs(mythlingZones) do
		local mythling = zone.Parent
		local zoneCenter = zone.Position
		local zoneRadius = zone.Size * 0.5

		local inside = (pos - zoneCenter).Magnitude <= zoneRadius.X

		if inside then
			inAny = true
			if ClaimState.state ~= "InZone" or ClaimState.zone ~= zone then
				ClaimState.state = "InZone"
				ClaimState.zone  = zone
				ClaimEvent:FireServer("InZone", {
					mythlingId = mythling:GetAttribute("Id"),
					playerPos  = pos,
				})
			end
			break
		end
	end

	if not inAny and ClaimState.state ~= "OutZone" then
		ClaimState.state = "OutZone"
		local oldZone = ClaimState.zone
		ClaimState.zone = nil
		ClaimEvent:FireServer("OutZone", {
			zone = oldZone,
		})
	end
end)
