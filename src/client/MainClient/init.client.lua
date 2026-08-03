-- StarterPlayer/StarterPlayerScripts/MainClient

local clientModules = script.Parent:WaitForChild("ClientModules")
local controllersFolder = clientModules:WaitForChild("Controllers")
local UIController = require(clientModules:WaitForChild("UIController"))

local CONTROLLER_ORDER = {
	"EnvironmentController",
	"NoClimbController",
	"ClaimController",
	"MythlingTimerController",
	"StandPromptController",
	"NotificationController",
	"CombatController",
	"HUDController",
	"HotbarController",
	"StaminaController",
	"InventoryController",
	"ShopController",
	"StandController",
}

local context = {
	ClientModules = clientModules,
	LocalData = require(clientModules:WaitForChild("LocalData")),
	UIController = UIController,
}

UIController.Init(context)

local controllers = {}
for _, name in ipairs(CONTROLLER_ORDER) do
	local controller = require(controllersFolder:WaitForChild(name))
	table.insert(controllers, { name = name, controller = controller })
	controller.Init(context)
end

UIController.Start()

for _, entry in ipairs(controllers) do
	local ok, err = pcall(entry.controller.Start)
	if not ok then
		warn(`[MainClient] {entry.name} failed to start: {err}`)
	end
end

script.Destroying:Connect(function()
	for index = #controllers, 1, -1 do
		local controller = controllers[index].controller
		local ok, err = pcall(controller.Stop)
		if not ok then
			warn(`[MainClient] {controllers[index].name} failed to stop: {err}`)
		end
	end
	local ok, err = pcall(UIController.Stop)
	if not ok then
		warn(`[MainClient] UIController failed to stop: {err}`)
	end
end)
