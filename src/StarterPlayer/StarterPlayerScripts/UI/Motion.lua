-- StarterPlayer/StarterPlayerScripts/UI/Motion

local TweenService = game:GetService("TweenService")

local ModalState = require(script.Parent:WaitForChild("State"):WaitForChild("ModalState"))

local Motion = {}

-- These values mirror Roblox's current in-experience menu motion.
local MENU_OPEN_TIME = 0.5
local MENU_CLOSE_TIME = 0.4
local TAB_TIME = 0.1
local REDUCED_MOTION_TIME = 0.25
local MENU_HIDDEN_POSITION = UDim2.new(0, 0, 1, 36)

local UserGameSettings = UserSettings():GetService("UserGameSettings")

export type MenuTransitionConfig = {
	screenGui: ScreenGui,
	motionRoot: CanvasGroup,
	panelName: string,
	onOpen: (() -> ())?,
	onCloseStart: (() -> ())?,
	onClosed: (() -> ())?,
}

export type MenuTransition = {
	Open: (skipAnimation: boolean?) -> (),
	Close: (skipAnimation: boolean?) -> (),
	IsOpen: () -> boolean,
	Destroy: () -> (),
}

local activeTweens: { [Instance]: Tween } = setmetatable({}, { __mode = "k" })

function Motion.IsReduced(): boolean
	local ok, reducedMotion = pcall(function()
		return UserGameSettings.ReducedMotion
	end)
	return ok and reducedMotion == true
end

local function cancelTween(instance: Instance)
	local tween = activeTweens[instance]
	if tween then
		activeTweens[instance] = nil
		tween:Cancel()
	end
end

local function playTween(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): Tween
	cancelTween(instance)
	local tween = TweenService:Create(instance, tweenInfo, goal)
	activeTweens[instance] = tween
	tween.Completed:Once(function()
		if activeTweens[instance] == tween then
			activeTweens[instance] = nil
		end
	end)
	tween:Play()
	return tween
end

function Motion.CreateMenuTransition(config: MenuTransitionConfig): MenuTransition
	local screenGui = config.screenGui
	local motionRoot = config.motionRoot
	local isOpen = false
	local generation = 0

	screenGui.Enabled = false
	motionRoot.Position = MENU_HIDDEN_POSITION
	motionRoot.GroupTransparency = 0

	local function finishClose(closeGeneration: number)
		if generation ~= closeGeneration or isOpen then
			return
		end
		screenGui.Enabled = false
		motionRoot.Position = MENU_HIDDEN_POSITION
		motionRoot.GroupTransparency = 0
		ModalState.Close(config.panelName)
		if config.onClosed then
			config.onClosed()
		end
	end

	local function open(skipAnimation: boolean?)
		if isOpen then
			return
		end

		local wasVisible = screenGui.Enabled
		isOpen = true
		generation += 1
		cancelTween(motionRoot)

		if config.onOpen then
			config.onOpen()
		end
		if not isOpen then
			return
		end

		screenGui.Enabled = true
		ModalState.Open(config.panelName)

		if skipAnimation then
			motionRoot.Position = UDim2.new()
			motionRoot.GroupTransparency = 0
		elseif Motion.IsReduced() then
			motionRoot.Position = UDim2.new()
			if not wasVisible then
				motionRoot.GroupTransparency = 1
			end
			playTween(motionRoot, TweenInfo.new(REDUCED_MOTION_TIME), { GroupTransparency = 0 })
		else
			motionRoot.GroupTransparency = 0
			if not wasVisible then
				motionRoot.Position = MENU_HIDDEN_POSITION
			end
			playTween(
				motionRoot,
				TweenInfo.new(MENU_OPEN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
				{ Position = UDim2.new() }
			)
		end
	end

	local function close(skipAnimation: boolean?)
		if not isOpen and not screenGui.Enabled then
			return
		end

		isOpen = false
		generation += 1
		local closeGeneration = generation
		cancelTween(motionRoot)
		ModalState.BeginClose(config.panelName)
		if config.onCloseStart then
			config.onCloseStart()
		end

		if skipAnimation then
			finishClose(closeGeneration)
			return
		end

		local tween
		if Motion.IsReduced() then
			motionRoot.Position = UDim2.new()
			tween = playTween(motionRoot, TweenInfo.new(REDUCED_MOTION_TIME), { GroupTransparency = 1 })
		else
			motionRoot.GroupTransparency = 0
			tween = playTween(
				motionRoot,
				TweenInfo.new(MENU_CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = MENU_HIDDEN_POSITION }
			)
		end

		tween.Completed:Once(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				finishClose(closeGeneration)
			end
		end)
	end

	local function destroy()
		generation += 1
		isOpen = false
		cancelTween(motionRoot)
		screenGui.Enabled = false
		ModalState.Close(config.panelName)
	end

	return {
		Open = open,
		Close = close,
		IsOpen = function()
			return isOpen
		end,
		Destroy = destroy,
	}
end

local function prepareTabObject(object: GuiObject)
	cancelTween(object)
	object.Position = UDim2.new()
	if object:IsA("CanvasGroup") then
		object.GroupTransparency = 0
	end
end

--- Slides complete tab pages in the direction of the selected tab. Passing parallel arrays
--- lets Inventory move its grid and details columns as one page without coupling the shell
--- to feature content.
function Motion.TransitionTab(
	previous: { GuiObject },
	nextPage: { GuiObject },
	direction: number,
	onComplete: (() -> ())?
)
	for _, object in previous do
		prepareTabObject(object)
		object.Visible = true
	end
	for _, object in nextPage do
		prepareTabObject(object)
		object.Visible = true
	end

	if Motion.IsReduced() then
		local pending = #previous
		local function completePrevious()
			pending -= 1
			if pending == 0 and onComplete then
				onComplete()
			end
		end

		for _, object in nextPage do
			if object:IsA("CanvasGroup") then
				object.GroupTransparency = 1
			end
		end

		for _, object in previous do
			if object:IsA("CanvasGroup") then
				local tween = playTween(object, TweenInfo.new(REDUCED_MOTION_TIME), { GroupTransparency = 1 })
				tween.Completed:Once(function(playbackState)
					if playbackState == Enum.PlaybackState.Completed then
						object.Visible = false
						object.GroupTransparency = 0
						completePrevious()
					end
				end)
			else
				object.Visible = false
				completePrevious()
			end
		end
		for _, object in nextPage do
			if object:IsA("CanvasGroup") then
				playTween(object, TweenInfo.new(REDUCED_MOTION_TIME), { GroupTransparency = 0 })
			end
		end
		if #previous == 0 and onComplete then
			onComplete()
		end
		return
	end

	for _, object in nextPage do
		object.Position = UDim2.fromScale(direction, 0)
		playTween(
			object,
			TweenInfo.new(TAB_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new() }
		)
	end
	local pending = #previous
	for _, object in previous do
		local tween = playTween(
			object,
			TweenInfo.new(TAB_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(-direction, 0) }
		)
		tween.Completed:Once(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				object.Visible = false
				object.Position = UDim2.new()
				pending -= 1
				if pending == 0 and onComplete then
					onComplete()
				end
			end
		end)
	end
	if #previous == 0 and onComplete then
		onComplete()
	end
end

return Motion
