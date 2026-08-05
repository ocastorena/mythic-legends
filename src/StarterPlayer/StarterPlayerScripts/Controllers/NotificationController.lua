-- StarterPlayer/StarterPlayerScripts/Controllers/NotificationController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local ToastUtil = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("ToastUtil"))

local NotificationController = {}

type ClaimPayload = {
	winnerUserId: number?,
	displayName: string?,
}

local VOWELS: { [string]: boolean } = { a = true, e = true, i = true, o = true, u = true }

local initialized = false
local connection: RBXScriptConnection?
local spawnEvent: RemoteEvent

local function withArticle(displayName: string): string
	local firstCharacter = string.sub(displayName, 1, 1):lower()
	local article = if VOWELS[firstCharacter] then "an" else "a"
	return `{article} {displayName}`
end

local function resolveName(payload: ClaimPayload): string
	local displayName = payload.displayName
	if type(displayName) == "string" and displayName ~= "" then
		return withArticle(displayName)
	end
	return "a Mythling"
end

function NotificationController.Init(_context: Types.ClientContext)
	if initialized then
		return
	end
	initialized = true
	spawnEvent = ReplicatedStorage:WaitForChild("Network"):WaitForChild("World"):WaitForChild("Spawned") :: RemoteEvent
end

function NotificationController.Start()
	assert(initialized, "[NotificationController] Init must run before Start")
	if connection then
		return
	end

	connection = spawnEvent.OnClientEvent:Connect(function(eventName: unknown, rawPayload: unknown)
		if eventName ~= "Claimed" or type(rawPayload) ~= "table" then
			return
		end
		local payload = rawPayload :: ClaimPayload
		if payload.winnerUserId ~= Players.LocalPlayer.UserId then
			return
		end
		ToastUtil.Show(`You claimed {resolveName(payload)}!`)
	end)
end

function NotificationController.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return NotificationController
