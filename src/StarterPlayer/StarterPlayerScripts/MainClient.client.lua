-- StarterPlayer/StarterPlayerScripts/MainClient

local playerScripts = script.Parent
local controllersFolder = playerScripts:WaitForChild("Controllers")
local UIController = require(controllersFolder:WaitForChild("UIController"))

local CONTROLLER_ORDER = {
	"EnvironmentController",
	"NoClimbController",
	"ClaimController",
	"MythlingTimerController",
	"NotificationController",
	"CombatController",
	"HotbarController",
	"InventoryController",
	"StandController",
}

local context = {
	PlayerScripts = playerScripts,
	LocalData = require(playerScripts:WaitForChild("State"):WaitForChild("LocalData")),
}

UIController.Init(context)

type Controller = {
	Init: (typeof(context)) -> (),
	Start: () -> (),
	Stop: () -> (),
}

local controllers: { { name: string, controller: Controller } } = {}
for _, name in ipairs(CONTROLLER_ORDER) do
	local loaded, controllerOrError = pcall(require, controllersFolder:WaitForChild(name))
	if not loaded then
		warn(`[MainClient] {name} failed to load: {controllerOrError}`)
		continue
	end
	local controller = controllerOrError :: Controller
	if
		type(controller) ~= "table"
		or type(controller.Init) ~= "function"
		or type(controller.Start) ~= "function"
		or type(controller.Stop) ~= "function"
	then
		warn(`[MainClient] {name} does not implement Init, Start, and Stop`)
		continue
	end
	local initialized, initError = pcall(controller.Init, context)
	if not initialized then
		warn(`[MainClient] {name} failed to initialize: {initError}`)
		continue
	end
	table.insert(controllers, { name = name, controller = controller })
end

local uiStarted, uiError = pcall(UIController.Start)
if not uiStarted then
	warn(`[MainClient] UIController failed to start: {uiError}`)
end

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
