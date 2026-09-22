--!strict
-- ServerScriptService/Infrastructure/ServiceLifecycle
-- Services have one terminal lifetime. Duplicate Start while running and duplicate Stop are harmless;
-- restarting a stopped service requires a fresh module lifetime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)

local ServiceLifecycle = {}
ServiceLifecycle.__index = ServiceLifecycle

type State = { name: string, phase: "new" | "running" | "stopped", trove: Trove.Trove }
export type ServiceLifecycle = typeof(setmetatable({} :: State, ServiceLifecycle))

function ServiceLifecycle.new(name: string): ServiceLifecycle
	local state: State = { name = name, phase = "new", trove = Trove.new() }
	return setmetatable(state, ServiceLifecycle)
end

function ServiceLifecycle.Start(self: ServiceLifecycle): boolean
	assert(self.phase ~= "stopped", `[ServiceLifecycle] {self.name} cannot restart after Stop`)
	if self.phase == "running" then
		return false
	end
	self.phase = "running"
	return true
end

function ServiceLifecycle.IsRunning(self: ServiceLifecycle): boolean
	return self.phase == "running"
end

function ServiceLifecycle.Stop(self: ServiceLifecycle): boolean
	if self.phase == "stopped" then
		return false
	end
	self.phase = "stopped"
	self.trove:Destroy()
	return true
end

return ServiceLifecycle
