--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/EnvironmentController/Quality

local Quality = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local lifetime = Trove.new()
local isRunning = false
local generation = 0

function Quality.Init(_context: unknown) end

function Quality.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	-- Scales cosmetic world effects to the player's saved graphics quality and device profile.

	local UserInputService = game:GetService("UserInputService")

	local AUTOMATIC_MOBILE_MULTIPLIER = 0.65
	local SMALL_MOBILE_MAX_EDGE = 1280

	local baseParticleRates: { [ParticleEmitter]: number } = {}
	local baseBeamSegments: { [Beam]: number } = {}
	local baseRenderFidelity: { [MeshPart]: Enum.RenderFidelity } = {}
	local appliedParticleRates: { [ParticleEmitter]: number } = {}
	local appliedBeamSegments: { [Beam]: number } = {}
	local appliedRenderFidelity: { [MeshPart]: Enum.RenderFidelity } = {}
	local world = workspace:WaitForChild("World")
	local elementalIslands = world:WaitForChild("ElementalIslands")
	local atmosphere = world:WaitForChild("Atmosphere")
	if not isRunning or generation ~= currentGeneration then
		return
	end
	local originalMultiplier = script:GetAttribute("AppliedMultiplier")
	local appliedMultiplier: number?
	local function releaseInstance(instance: Instance)
		-- Streaming removes descendants without destroying them. Drop both references even
		-- when a later owner changed the property, and capture a fresh baseline on re-entry.
		if instance:IsA("ParticleEmitter") then
			local rate = baseParticleRates[instance]
			local appliedRate = appliedParticleRates[instance]
			baseParticleRates[instance] = nil
			appliedParticleRates[instance] = nil
			if rate ~= nil and instance.Rate == appliedRate then
				instance.Rate = rate
			end
		elseif instance:IsA("Beam") then
			local segments = baseBeamSegments[instance]
			local appliedSegments = appliedBeamSegments[instance]
			baseBeamSegments[instance] = nil
			appliedBeamSegments[instance] = nil
			if segments ~= nil and instance.Segments == appliedSegments then
				instance.Segments = segments
			end
		elseif instance:IsA("MeshPart") then
			local fidelity = baseRenderFidelity[instance]
			local appliedFidelity = appliedRenderFidelity[instance]
			baseRenderFidelity[instance] = nil
			appliedRenderFidelity[instance] = nil
			if fidelity ~= nil and instance.RenderFidelity == appliedFidelity then
				pcall(function()
					instance.RenderFidelity = fidelity
				end)
			end
		end
	end
	lifetime:Add(function()
		for emitter in baseParticleRates do
			releaseInstance(emitter)
		end
		for beam in baseBeamSegments do
			releaseInstance(beam)
		end
		for mesh in baseRenderFidelity do
			releaseInstance(mesh)
		end
		if script:GetAttribute("AppliedMultiplier") == appliedMultiplier then
			script:SetAttribute("AppliedMultiplier", originalMultiplier)
		end
	end)

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
			local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
				or Vector2.zero
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
		appliedParticleRates[emitter] = emitter.Rate
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
		appliedBeamSegments[beam] = beam.Segments
	end

	local function applyMeshQuality(meshPart: MeshPart, multiplier: number)
		local renderFidelity = baseRenderFidelity[meshPart]
		if not renderFidelity then
			renderFidelity = meshPart.RenderFidelity
			baseRenderFidelity[meshPart] = renderFidelity
		end

		pcall(function()
			meshPart.RenderFidelity = if multiplier < 1
				then Enum.RenderFidelity.Performance
				else renderFidelity
			appliedRenderFidelity[meshPart] = meshPart.RenderFidelity
		end)
	end

	local function applyInstance(instance: Instance, multiplier: number)
		if instance:IsA("ParticleEmitter") then
			applyParticleQuality(instance, multiplier)
		elseif instance:IsA("Beam") then
			applyBeamQuality(instance, multiplier)
		elseif
			instance:IsA("MeshPart")
			and (instance:IsDescendantOf(elementalIslands) or instance:IsDescendantOf(atmosphere))
		then
			applyMeshQuality(instance, multiplier)
		end
	end

	local function applyEnvironmentQuality()
		if not isRunning or generation ~= currentGeneration then
			return
		end
		local multiplier = qualityMultiplier()
		appliedMultiplier = multiplier
		script:SetAttribute("AppliedMultiplier", multiplier)

		for _, instance in world:GetDescendants() do
			applyInstance(instance, multiplier)
		end
	end

	lifetime:Add(world.DescendantAdded:Connect(function(instance)
		if isRunning and generation == currentGeneration and instance:IsDescendantOf(world) then
			applyInstance(instance, qualityMultiplier())
		end
	end))
	lifetime:Add(world.DescendantRemoving:Connect(releaseInstance))
	applyEnvironmentQuality()

	local ok, gameSettings = pcall(function()
		return UserSettings().GameSettings
	end)
	if ok then
		lifetime:Add(
			gameSettings
				:GetPropertyChangedSignal("SavedQualityLevel")
				:Connect(applyEnvironmentQuality)
		)
	end
end

function Quality.Stop()
	isRunning = false
	generation += 1
	lifetime:Clean()
end

return Quality
