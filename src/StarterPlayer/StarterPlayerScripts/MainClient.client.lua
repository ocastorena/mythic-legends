--!strict
-- StarterPlayer/StarterPlayerScripts/MainClient
-- One terminal application lifetime; controllers stop before private state is destroyed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Types = require(script.Parent.Types)
local LocalData = require(script.Parent.State.LocalData)
local UIController = require(script.Parent.Controllers.UIController)

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

type ControllerEntry = { name: string, controller: Types.Controller }
local controllers: { ControllerEntry } = {}
local lifetime = Trove.new()
local isShuttingDown = false
local context: Types.ClientContext = { PlayerScripts = script.Parent, LocalData = LocalData }

local function stopController(entry: ControllerEntry)
	local succeeded, message = pcall(function()
		entry.controller.Stop()
		return true
	end)
	if not succeeded then
		warn(`[MainClient] {entry.name} failed to stop: {message}`)
	end
end

local function shutdown()
	if isShuttingDown then
		return
	end
	isShuttingDown = true
	lifetime:Destroy()
	for index = #controllers, 1, -1 do
		stopController(controllers[index])
	end
	stopController({ name = "UIController", controller = UIController })
	LocalData.Destroy()
end

lifetime:Connect(script.Destroying, shutdown)
lifetime:Add(task.defer(function()
	UIController.Init(context)
	local controllersFolder = script.Parent:WaitForChild("Controllers")
	for _, name in ipairs(CONTROLLER_ORDER) do
		if isShuttingDown then
			return
		end
		local loaded, controllerOrError = pcall(require, controllersFolder:WaitForChild(name))
		if isShuttingDown then
			return
		end
		if not loaded then
			warn(`[MainClient] {name} failed to load: {controllerOrError}`)
			continue
		end
		-- Controller modules are loaded by the static manifest; verify their lifecycle boundary.
		local controller = controllerOrError :: Types.Controller
		if
			type(controller) ~= "table"
			or type(controller.Init) ~= "function"
			or type(controller.Start) ~= "function"
			or type(controller.Stop) ~= "function"
		then
			warn(`[MainClient] {name} does not implement Init, Start, and Stop`)
			continue
		end
		local entry = { name = name, controller = controller }
		-- Register before Init so shutdown also releases partially initialized controllers.
		table.insert(controllers, entry)
		local initialized, initError = pcall(function()
			controller.Init(context)
			return true
		end)
		if not initialized then
			warn(`[MainClient] {name} failed to initialize: {initError}`)
			stopController(entry)
			table.remove(controllers)
		end
	end
	if isShuttingDown then
		return
	end
	local uiStarted, uiError = pcall(function()
		UIController.Start()
		return true
	end)
	if not uiStarted then
		warn(`[MainClient] UIController failed to start: {uiError}`)
	end
	for _, entry in ipairs(controllers) do
		if isShuttingDown then
			return
		end
		local started, startError = pcall(function()
			entry.controller.Start()
			return true
		end)
		if not started then
			warn(`[MainClient] {entry.name} failed to start: {startError}`)
			stopController(entry)
		end
	end
	lifetime:Pop(coroutine.running())
end))
