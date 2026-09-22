--!strict
-- StarterPlayer/StarterPlayerScripts/UI/ViewportUtil
-- Binds responsive layout to the current camera for exactly one GUI lifetime.

local ViewportUtil = {}

function ViewportUtil.Observe(owner: Instance, update: (Vector2) -> ()): () -> ()
	local isAlive = true
	local viewportConnection: RBXScriptConnection? = nil
	local cameraConnection: RBXScriptConnection? = nil
	local destroyConnection: RBXScriptConnection? = nil

	local function disconnect()
		if not isAlive then
			return
		end
		isAlive = false
		if viewportConnection then
			viewportConnection:Disconnect()
		end
		if cameraConnection then
			cameraConnection:Disconnect()
		end
		if destroyConnection then
			destroyConnection:Disconnect()
		end
	end

	local function bindCamera()
		if viewportConnection then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end
		local camera = workspace.CurrentCamera
		if not camera or not isAlive then
			return
		end
		local function refresh()
			if isAlive and workspace.CurrentCamera == camera then
				update(camera.ViewportSize)
			end
		end
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		refresh()
	end

	cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	destroyConnection = owner.Destroying:Once(disconnect)
	bindCamera()
	return disconnect
end

return ViewportUtil
