-- StarterPlayer/StarterPlayerScripts/Controllers/MythlingTimerController

local MythlingTimerController = {}
local stopImpl: (() -> ())?

function MythlingTimerController.Init(_context: unknown) end

function MythlingTimerController.Start()
	local connections: { RBXScriptConnection } = {}
	local RunService = game:GetService("RunService")

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
	local tracked: { [Model]: { model: Model, gui: BillboardGui, label: TextLabel } } = {}

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

	table.insert(
		connections,
		mythlingsFolder.ChildAdded:Connect(function(child)
			tryAttach(child)
		end)
	)

	table.insert(
		connections,
		mythlingsFolder.ChildRemoved:Connect(function(child)
			detach(child)
		end)
	)

	-- If server edits ExpireAt later (rare), catch it:
	table.insert(
		connections,
		mythlingsFolder.DescendantAdded:Connect(function(desc)
			local model = desc:FindFirstAncestorOfClass("Model")
			if model and model.Parent == mythlingsFolder then
				tryAttach(model)
			end
		end)
	)

	-- -- Update loop (throttled) ----------------------------------------------

	local accumulator = 0
	local UPDATE_HZ = 5 -- 5 times per second is plenty for a timer
	local UPDATE_DT = 1 / UPDATE_HZ

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
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
				end
			end
		end)
	)
	stopImpl = function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, entry in tracked do
			entry.gui:Destroy()
		end
		table.clear(tracked)
	end
end

function MythlingTimerController.Stop()
	if stopImpl then
		stopImpl()
		stopImpl = nil
	end
end

return MythlingTimerController
