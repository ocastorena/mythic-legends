-- StarterGui/MainGui/HudController
-- Owns every widget in MainGui: the always-on-screen HUD.
--
-- The inventory open button lives in MainGui but used to be hooked by InventoryController
-- reaching across into another ScreenGui. MainGui owns its own button now and asks for the
-- inventory by toggling that ScreenGui's Enabled property, which is the contract
-- InventoryController already reacts to.

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ButtonUtil = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("ButtonUtil"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CurrencyEvent: RemoteEvent = Remotes.CurrencyEvent

-- GUI components
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local mainFrame = script.Parent.MainFrame
local runiesTotalLabel = mainFrame.RuniesFrame.RuniesTotalLabel
local openButton = mainFrame.OpenButton

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
		runiesTotalLabel.Text = formatRunies(payload)
	end
end)

ButtonUtil.hookClick(openButton, function()
	local inventoryGui = playerGui:FindFirstChild("InventoryGui")
	if inventoryGui and inventoryGui:IsA("ScreenGui") then
		inventoryGui.Enabled = not inventoryGui.Enabled
	end
end)
