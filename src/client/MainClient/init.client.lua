-- StarterPlayer/StarterPlayerScripts/MainClient

local clientModules = script.Parent:WaitForChild("ClientModules")
local controllersFolder = clientModules:WaitForChild("Controllers")
local UIController = require(clientModules:WaitForChild("UIController"))

local CONTROLLER_ORDER = {
	"EnvironmentQualityController",
	"EnvironmentMotionController",
	"EnvironmentAudioController",
	"NoClimbController",
	"ClaimController",
	"MythlingTimerController",
	"StandPromptController",
	"NotificationController",
	"CombatVfxController",
	"CombatClient",
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

local controllers = {}
for _, name in ipairs(CONTROLLER_ORDER) do
	local controller = require(controllersFolder:WaitForChild(name))
	table.insert(controllers, { name = name, controller = controller })
	if type(controller.Init) == "function" then
		controller.Init(context)
	end
end

UIController.Init()
UIController.Start()

for _, entry in ipairs(controllers) do
	local ok, err = pcall(entry.controller.Start, context)
	if not ok then
		warn(`[MainClient] {entry.name} failed to start: {err}`)
	end
end

script.Destroying:Connect(function()
	for index = #controllers, 1, -1 do
		local controller = controllers[index].controller
		if type(controller.Destroy) == "function" then
			pcall(controller.Destroy)
		end
	end
	UIController.Destroy()
end)
