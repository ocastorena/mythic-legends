-- StarterPlayer/StarterPlayerScripts/EnvironmentMotionController
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
}

type BannerState = {
	model: Model,
	basePivot: CFrame,
	swayDegrees: number,
	speed: number,
	phase: number,
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
	}
end

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

CollectionService:GetInstanceAddedSignal(LIGHT_TAG):Connect(registerLight)
CollectionService:GetInstanceRemovedSignal(LIGHT_TAG):Connect(function(instance)
	if instance:IsA("Light") then
		lightStates[instance] = nil
	end
end)

CollectionService:GetInstanceAddedSignal(BANNER_TAG):Connect(registerBanner)
CollectionService:GetInstanceRemovedSignal(BANNER_TAG):Connect(function(instance)
	if instance:IsA("Model") then
		bannerStates[instance] = nil
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
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
		end
	end

	for model, state in pairs(bannerStates) do
		if not model.Parent then
			bannerStates[model] = nil
		else
			local forwardDegrees = state.swayDegrees * math.sin(now * state.speed + state.phase)
			local sideDegrees = state.swayDegrees * 0.28 * math.sin(now * state.speed * 0.61 + state.phase * 1.4)
			model:PivotTo(
				state.basePivot
					* CFrame.Angles(math.rad(forwardDegrees), 0, math.rad(sideDegrees))
			)
		end
	end
end)
