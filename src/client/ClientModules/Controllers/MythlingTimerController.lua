-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/MythlingTimerController

local MythlingTimerController = {}

function MythlingTimerController.Start(_context: any)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local runtimeFolder = workspace:WaitForChild("Runtime")
local mythlingsFolder = runtimeFolder:WaitForChild("Mythlings")

-- -- Helpers ---------------------------------------------------------------

local function serverNow()
	-- better sync than os.time() on clients
	return workspace:GetServerTimeNow()
end

local function fmtSeconds(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

-- tracked entries: { model = Model, gui = BillboardGui, label = TextLabel }
local tracked: {[Model]: {model: Model, gui: BillboardGui, label: TextLabel}} = {}

local function tryAttach(model: Instance)
	if not model:IsA("Model") then return end
	if tracked[model] then return end

	local expireAt = model:GetAttribute("ExpireAt")
	if typeof(expireAt) ~= "number" then return end

	local gui = model:FindFirstChild("MythlingExpireTimer")
	if not (gui and gui:IsA("BillboardGui")) then return end

	local label = gui:FindFirstChild("TimerLabel")
	if not (label and label:IsA("TextLabel")) then return end

	tracked[model] = { model = model, gui = gui, label = label }
end

local function detach(model: Instance)
	if tracked[model] then
		tracked[model] = nil
	end
end

-- -- Initial scan + hooks --------------------------------------------------

for _, child in ipairs(mythlingsFolder:GetChildren()) do
	tryAttach(child)
end

mythlingsFolder.ChildAdded:Connect(function(child)
	tryAttach(child)
end)

mythlingsFolder.ChildRemoved:Connect(function(child)
	detach(child)
end)

-- If server edits ExpireAt later (rare), catch it:
mythlingsFolder.DescendantAdded:Connect(function(desc)
	local model = desc:FindFirstAncestorOfClass("Model")
	if model and model.Parent == mythlingsFolder then
		tryAttach(model)
	end
end)

-- -- Update loop (throttled) ----------------------------------------------

local accumulator = 0
local UPDATE_HZ = 5               -- 5 times per second is plenty for a timer
local UPDATE_DT = 1 / UPDATE_HZ

RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < UPDATE_DT then return end
	accumulator -= UPDATE_DT

	local now = serverNow()

	for model, entry in pairs(tracked) do
		if not model.Parent then
			tracked[model] = nil
		else
			local expireAt = model:GetAttribute("ExpireAt")
			if typeof(expireAt) ~= "number" then
				entry.gui.Enabled = false
			else
				local remain = expireAt - now
				entry.label.Text = fmtSeconds(remain)
				entry.gui.Enabled = (remain > 0)
			end
		end
	end
end)
end

function MythlingTimerController.Destroy()
end

return MythlingTimerController
