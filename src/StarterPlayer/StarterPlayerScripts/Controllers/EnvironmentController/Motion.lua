--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/EnvironmentController/Motion

local Motion = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local lifetime = Trove.new()
local isRunning = false

function Motion.Init(_context: unknown) end

function Motion.Start()
	if isRunning then
		return
	end
	isRunning = true
	-- Lightweight client-only motion for tagged ambient lights and arena banners.

	local CollectionService = game:GetService("CollectionService")
	local RunService = game:GetService("RunService")

	local LIGHT_TAG = "AmbientLightVariation"
	local BANNER_TAG = "AmbientBanner"
	local UPDATE_INTERVAL = 1 / 15

	type LightState = {
		light: Light,
		baseBrightness: number,
		amplitude: number,
		speed: number,
		phase: number,
		originalBrightness: number,
		lastBrightness: number?,
	}

	type BannerState = {
		model: Model,
		basePivot: CFrame,
		swayDegrees: number,
		speed: number,
		phase: number,
		lastPivot: CFrame?,
	}

	local lightStates: { [Light]: LightState } = {}
	local bannerStates: { [Model]: BannerState } = {}
	local accumulator = 0

	local function numberAttribute(instance: Instance, name: string, fallback: number): number
		local value = instance:GetAttribute(name)
		return if typeof(value) == "number" then value else fallback
	end

	local function registerLight(instance: Instance)
		if not instance:IsA("Light") or lightStates[instance] then
			return
		end

		lightStates[instance] = {
			light = instance,
			baseBrightness = numberAttribute(instance, "BaseBrightness", instance.Brightness),
			amplitude = math.max(0, numberAttribute(instance, "VariationAmplitude", 0.12)),
			speed = math.max(0.05, numberAttribute(instance, "VariationSpeed", 1)),
			phase = numberAttribute(instance, "VariationPhase", 0),
			originalBrightness = instance.Brightness,
		}
	end
	local function restoreLight(instance: Light)
		local state = lightStates[instance]
		if state and instance.Parent and instance.Brightness == state.lastBrightness then
			instance.Brightness = state.originalBrightness
		end
		lightStates[instance] = nil
	end
	local function restoreBanner(instance: Model)
		local state = bannerStates[instance]
		if state and instance.Parent and instance:GetPivot() == state.lastPivot then
			instance:PivotTo(state.basePivot)
		end
		bannerStates[instance] = nil
	end
	lifetime:Add(function()
		for instance in lightStates do
			restoreLight(instance)
		end
		for instance in bannerStates do
			restoreBanner(instance)
		end
	end)

	local function registerBanner(instance: Instance)
		if not instance:IsA("Model") or bannerStates[instance] then
			return
		end

		bannerStates[instance] = {
			model = instance,
			basePivot = instance:GetPivot(),
			swayDegrees = math.max(0, numberAttribute(instance, "SwayDegrees", 1.4)),
			speed = math.max(0.05, numberAttribute(instance, "SwaySpeed", 0.55)),
			phase = numberAttribute(instance, "SwayPhase", 0),
		}
	end

	for _, instance in ipairs(CollectionService:GetTagged(LIGHT_TAG)) do
		registerLight(instance)
	end

	for _, instance in ipairs(CollectionService:GetTagged(BANNER_TAG)) do
		registerBanner(instance)
	end

	lifetime:Add(CollectionService:GetInstanceAddedSignal(LIGHT_TAG):Connect(registerLight))
	lifetime:Add(CollectionService:GetInstanceRemovedSignal(LIGHT_TAG):Connect(function(instance)
		if instance:IsA("Light") then
			restoreLight(instance)
		end
	end))

	lifetime:Add(CollectionService:GetInstanceAddedSignal(BANNER_TAG):Connect(registerBanner))
	lifetime:Add(CollectionService:GetInstanceRemovedSignal(BANNER_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			restoreBanner(instance)
		end
	end))

	lifetime:Add(RunService.RenderStepped:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < UPDATE_INTERVAL then
			return
		end
		accumulator %= UPDATE_INTERVAL

		local now = workspace:GetServerTimeNow()

		for light, state in pairs(lightStates) do
			if not light.Parent then
				lightStates[light] = nil
			else
				local wave = 0.58 * math.sin(now * state.speed + state.phase)
					+ 0.29 * math.sin(now * state.speed * 0.47 + state.phase * 1.7)
					+ 0.13 * math.sin(now * state.speed * 0.23 + state.phase * 2.3)
				light.Brightness = math.max(0, state.baseBrightness + state.amplitude * wave)
				state.lastBrightness = light.Brightness
			end
		end

		for model, state in pairs(bannerStates) do
			if not model.Parent then
				bannerStates[model] = nil
			else
				local forwardDegrees = state.swayDegrees * math.sin(now * state.speed + state.phase)
				local sideDegrees = state.swayDegrees
					* 0.28
					* math.sin(now * state.speed * 0.61 + state.phase * 1.4)
				model:PivotTo(
					state.basePivot
						* CFrame.Angles(math.rad(forwardDegrees), 0, math.rad(sideDegrees))
				)
				state.lastPivot = model:GetPivot()
			end
		end
	end))
end

function Motion.Stop()
	isRunning = false
	lifetime:Clean()
end

return Motion
