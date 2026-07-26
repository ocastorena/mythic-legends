-- StarterPlayer/StarterPlayerScripts/NotificationController
-- The one place that decides which server events deserve a toast. The toast itself lives
-- in ToastUtil, so adding a notification here is a couple of lines rather than a new
-- controller with its own copy of the tween code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToastUtil = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("ToastUtil"))

local localPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SpawnEvent = Remotes:WaitForChild("SpawnEvent")

local VOWELS = { a = true, e = true, i = true, o = true, u = true }

local function withArticle(displayName: string): string
	local firstChar = string.sub(displayName, 1, 1):lower()
	local article = VOWELS[firstChar] and "an" or "a"
	return string.format("%s %s", article, displayName)
end

local function resolveName(payload): string
	if payload and typeof(payload.displayName) == "string" and payload.displayName ~= "" then
		return withArticle(payload.displayName)
	end
	return "a Mythling"
end

-- Server fires: SpawnEvent:FireAllClients("Claimed", { mythlingId, winnerUserId, displayName })
SpawnEvent.OnClientEvent:Connect(function(event, payload)
	if event ~= "Claimed" then
		return
	end
	if not payload or payload.winnerUserId ~= localPlayer.UserId then
		return
	end
	ToastUtil.Show(("You claimed %s!"):format(resolveName(payload)))
end)
