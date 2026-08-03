-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/NotificationController

local NotificationController = {}
local connection: RBXScriptConnection?

function NotificationController.Init(_context: any)
end

function NotificationController.Start()
-- The one place that decides which server events deserve a toast. The toast itself lives
-- in ToastUtil, so adding a notification here is a couple of lines rather than a new
-- controller with its own copy of the tween code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToastUtil = require(script:FindFirstAncestor("ClientModules"):WaitForChild("UI"):WaitForChild("ToastUtil"))

local localPlayer = Players.LocalPlayer
local SpawnEvent = ReplicatedStorage:WaitForChild("Network"):WaitForChild("World"):WaitForChild("Spawned")

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
connection = SpawnEvent.OnClientEvent:Connect(function(event, payload)
	if event ~= "Claimed" then
		return
	end
	if not payload or payload.winnerUserId ~= localPlayer.UserId then
		return
	end
	ToastUtil.Show(("You claimed %s!"):format(resolveName(payload)))
end)
end

function NotificationController.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return NotificationController
