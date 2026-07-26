-- StarterGui/MainGui/RuniesController
-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CurrencyEvent: RemoteEvent = Remotes.CurrencyEvent

-- GUI components
local RuniesFrame = script.Parent.MainFrame.RuniesFrame
local RuniesTotalLabel = RuniesFrame.RuniesTotalLabel

local function formatRunies(amount: number): string
	-- formats 1234567 -> "1,234,567"
	local formatted = tostring(math.floor(amount))
	local k
	while true do
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

CurrencyEvent.OnClientEvent:Connect(function(action, payload)
	if action == "RuniesUpdate" then
		RuniesTotalLabel.Text = formatRunies(payload)
	end
end)
