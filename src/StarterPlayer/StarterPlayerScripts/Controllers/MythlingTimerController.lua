--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/MythlingTimerController

local MythlingTimerController = {}
local stopImpl: (() -> ())?
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local lifetime = Trove.new()
local isRunning = false
local generation = 0

function MythlingTimerController.Init(_context: unknown) end

function MythlingTimerController.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	local RunService = game:GetService("RunService")

	local runtimeFolder = workspace:WaitForChild("Runtime")
	local mythlingsFolder = runtimeFolder:WaitForChild("Mythlings")
	if not isRunning or generation ~= currentGeneration then
		return
	end

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
	type Timer = {
		gui: BillboardGui,
		label: TextLabel,
		originalText: string,
		originalEnabled: boolean,
		lastText: string?,
		lastEnabled: boolean?,
	}
	local tracked: { [Model]: Timer } = {}

	local function tryAttach(model: Instance)
		if not model:IsA("Model") then
			return
		end
		if tracked[model] then
			return
		end

		local expireAt = model:GetAttribute("ExpireAt")
		if typeof(expireAt) ~= "number" then
			return
		end

		local gui = model:FindFirstChild("MythlingExpireTimer")
		if not (gui and gui:IsA("BillboardGui")) then
			return
		end

		local label = gui:FindFirstChild("TimerLabel")
		if not (label and label:IsA("TextLabel")) then
			return
		end

		tracked[model] =
			{ gui = gui, label = label, originalText = label.Text, originalEnabled = gui.Enabled }
	end

	local function detach(model: Instance)
		if not model:IsA("Model") then
			return
		end
		local entry = tracked[model]
		if entry then
			if entry.gui.Parent and entry.gui.Enabled == entry.lastEnabled then
				entry.gui.Enabled = entry.originalEnabled
			end
			if entry.label.Parent and entry.label.Text == entry.lastText then
				entry.label.Text = entry.originalText
			end
			tracked[model] = nil
		end
	end

	-- -- Initial scan + hooks --------------------------------------------------

	for _, child in ipairs(mythlingsFolder:GetChildren()) do
		tryAttach(child)
	end

	lifetime:Add(mythlingsFolder.ChildAdded:Connect(function(child)
		tryAttach(child)
	end))

	lifetime:Add(mythlingsFolder.ChildRemoved:Connect(function(child)
		detach(child)
	end))

	-- If server edits ExpireAt later (rare), catch it:
	lifetime:Add(mythlingsFolder.DescendantAdded:Connect(function(desc)
		local model = desc:FindFirstAncestorOfClass("Model")
		if model and model.Parent == mythlingsFolder then
			tryAttach(model)
		end
	end))

	-- -- Update loop (throttled) ----------------------------------------------

	local accumulator = 0
	local UPDATE_HZ = 5 -- 5 times per second is plenty for a timer
	local UPDATE_DT = 1 / UPDATE_HZ

	lifetime:Add(RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < UPDATE_DT then
			return
		end
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
				entry.lastEnabled = entry.gui.Enabled
				entry.lastText = entry.label.Text
			end
		end
	end))
	stopImpl = function()
		lifetime:Clean()
		for model in tracked do
			detach(model)
		end
		table.clear(tracked)
	end
end

function MythlingTimerController.Stop()
	isRunning = false
	generation += 1
	if stopImpl then
		stopImpl()
		stopImpl = nil
	end
end

return MythlingTimerController
