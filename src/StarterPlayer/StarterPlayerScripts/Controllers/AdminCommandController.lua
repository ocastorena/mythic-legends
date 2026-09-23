--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/AdminCommandController
-- Displays only the requesting player's server-confirmed command feedback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ToastBus = require(script.Parent.Parent.UI.State.ToastBus)
local Types = require(script.Parent.Parent.Types)

local AdminCommandController = {}
local feedback: RemoteEvent
local connection: RBXScriptConnection?

local function showFeedback(message: unknown)
	if type(message) ~= "string" or message == "" then
		return
	end
	local channels = TextChatService:FindFirstChild("TextChannels")
	local channel = channels
		and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
	if channel and channel:IsA("TextChannel") then
		local displayed = pcall(function()
			channel:DisplaySystemMessage(`[Admin] {message}`)
		end)
		if displayed then
			return
		end
	end
	ToastBus.Show(message)
end

function AdminCommandController.Init(_context: Types.ClientContext)
	local remote =
		ReplicatedStorage:WaitForChild("Network"):WaitForChild("Admin"):WaitForChild("Feedback")
	assert(remote:IsA("RemoteEvent"), "[AdminCommandController] Feedback must be a RemoteEvent")
	feedback = remote
end

function AdminCommandController.Start()
	if not connection then
		connection = feedback.OnClientEvent:Connect(showFeedback)
	end
end

function AdminCommandController.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return AdminCommandController
