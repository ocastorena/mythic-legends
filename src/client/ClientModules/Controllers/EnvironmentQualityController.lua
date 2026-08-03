-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/EnvironmentQualityController

local EnvironmentQualityController = {}

function EnvironmentQualityController.Start(_context: any)
-- Scales cosmetic world effects to the player's saved graphics quality and device profile.

local UserInputService = game:GetService("UserInputService")

local AUTOMATIC_MOBILE_MULTIPLIER = 0.65
local SMALL_MOBILE_MAX_EDGE = 1280

local baseParticleRates: { [ParticleEmitter]: number } = {}
local baseBeamSegments: { [Beam]: number } = {}
local baseRenderFidelity: { [MeshPart]: Enum.RenderFidelity } = {}
local environment = workspace:WaitForChild("Visuals"):WaitForChild("Environment")

local function savedQualityValue(): number
	local ok, quality = pcall(function()
		return UserSettings().GameSettings.SavedQualityLevel
	end)
	if not ok or quality == Enum.SavedQualitySetting.Automatic then
		return 0
	end
	return quality.Value
end

local function qualityMultiplier(): number
	local quality = savedQualityValue()
	if quality > 0 then
		if quality <= 3 then
			return 0.4
		elseif quality <= 6 then
			return 0.65
		elseif quality <= 8 then
			return 0.85
		end
		return 1
	end

	if UserInputService.TouchEnabled then
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
		if math.max(viewport.X, viewport.Y) <= SMALL_MOBILE_MAX_EDGE then
			return 0.55
		end
		return AUTOMATIC_MOBILE_MULTIPLIER
	end

	return 1
end

local function applyParticleQuality(emitter: ParticleEmitter, multiplier: number)
	local baseRate = baseParticleRates[emitter]
	if not baseRate then
		baseRate = emitter.Rate
		baseParticleRates[emitter] = baseRate
	end
	emitter.Rate = baseRate * multiplier
end

local function applyBeamQuality(beam: Beam, multiplier: number)
	local baseSegments = baseBeamSegments[beam]
	if not baseSegments then
		baseSegments = beam.Segments
		baseBeamSegments[beam] = baseSegments
	end

	if multiplier <= 0.4 then
		beam.Segments = math.min(baseSegments, 4)
	elseif multiplier < 1 then
		beam.Segments = math.min(baseSegments, 6)
	else
		beam.Segments = baseSegments
	end
end

local function applyMeshQuality(meshPart: MeshPart, multiplier: number)
	local renderFidelity = baseRenderFidelity[meshPart]
	if not renderFidelity then
		renderFidelity = meshPart.RenderFidelity
		baseRenderFidelity[meshPart] = renderFidelity
	end

	pcall(function()
		meshPart.RenderFidelity = if multiplier < 1 then Enum.RenderFidelity.Performance else renderFidelity
	end)
end

local function applyInstance(instance: Instance, multiplier: number)
	if instance:IsA("ParticleEmitter") then
		applyParticleQuality(instance, multiplier)
	elseif instance:IsA("Beam") then
		applyBeamQuality(instance, multiplier)
	elseif instance:IsA("MeshPart") then
		applyMeshQuality(instance, multiplier)
	end
end

local function applyEnvironmentQuality()
	local multiplier = qualityMultiplier()
	script:SetAttribute("AppliedMultiplier", multiplier)

	for _, instance in environment:GetDescendants() do
		applyInstance(instance, multiplier)
	end
end

applyEnvironmentQuality()

environment.DescendantAdded:Connect(function(instance)
	applyInstance(instance, qualityMultiplier())
end)

local ok, gameSettings = pcall(function()
	return UserSettings().GameSettings
end)
if ok then
	gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(applyEnvironmentQuality)
end
end

function EnvironmentQualityController.Destroy()
end

return EnvironmentQualityController
