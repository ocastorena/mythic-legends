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
	local RunService = game:GetService("RunService")

	local AUTOMATIC_MOBILE_MULTIPLIER = 0.65
	local SMALL_MOBILE_MAX_EDGE = 1280
	local DISTANCE_UPDATE_INTERVAL = 0.25

	type DistanceEffect = ParticleEmitter | Beam | Light
	type DistanceState = {
		fadeStart: number,
		fadeEnd: number,
		fade: number,
		isInRange: boolean,
		baseEnabled: boolean,
		appliedEnabled: boolean?,
	}

	local baseParticleRates: { [ParticleEmitter]: number } = {}
	local baseBeamSegments: { [Beam]: number } = {}
	local baseRenderFidelity: { [MeshPart]: Enum.RenderFidelity } = {}
	local appliedParticleRates: { [ParticleEmitter]: number } = {}
	local appliedBeamSegments: { [Beam]: number } = {}
	local appliedRenderFidelity: { [MeshPart]: Enum.RenderFidelity } = {}
	local distanceEffects: { [DistanceEffect]: DistanceState } = {}
	local effectObservers: { [DistanceEffect]: { RBXScriptConnection } } = {}
	local environment = workspace:WaitForChild("Visuals"):WaitForChild("Environment")
	if not isRunning or generation ~= currentGeneration then
		return
	end
	local originalMultiplier = script:GetAttribute("AppliedMultiplier")
	local appliedMultiplier: number?
	local function releaseDistanceEffect(effect: DistanceEffect)
		local state = distanceEffects[effect]
		if state and state.appliedEnabled ~= nil and effect.Enabled == state.appliedEnabled then
			effect.Enabled = state.baseEnabled
		end
		distanceEffects[effect] = nil
	end
	local function releaseInstance(instance: Instance)
		-- Streaming removes descendants without destroying them. Drop both references even
		-- when a later owner changed the property, and capture a fresh baseline on re-entry.
		if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Light") then
			releaseDistanceEffect(instance)
			local observers = effectObservers[instance]
			if observers then
				for _, connection in observers do
					connection:Disconnect()
				end
				effectObservers[instance] = nil
			end
		end
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
		for effect in effectObservers do
			releaseInstance(effect)
		end
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
		local distanceState = distanceEffects[emitter]
		emitter.Rate = baseRate * multiplier * (if distanceState then distanceState.fade else 1)
		appliedParticleRates[emitter] = emitter.Rate
	end

	local function effectDistance(effect: DistanceEffect, cameraPosition: Vector3): number?
		if effect:IsA("Beam") then
			local startAttachment, endAttachment = effect.Attachment0, effect.Attachment1
			if startAttachment and endAttachment then
				local startPosition = startAttachment.WorldPosition
				local segment = endAttachment.WorldPosition - startPosition
				local lengthSquared = segment:Dot(segment)
				local alpha = if lengthSquared > 0
					then math.clamp(
						(cameraPosition - startPosition):Dot(segment) / lengthSquared,
						0,
						1
					)
					else 0
				-- A long lavafall must remain visible near either end, not just its midpoint.
				return (cameraPosition - (startPosition + segment * alpha)).Magnitude
			end
		end
		local parent = effect.Parent
		if parent and parent:IsA("Attachment") then
			return (cameraPosition - parent.WorldPosition).Magnitude
		elseif parent and parent:IsA("BasePart") then
			return (cameraPosition - parent.Position).Magnitude
		end
		return nil
	end

	local function updateDistanceEffect(effect: DistanceEffect, state: DistanceState)
		local camera = workspace.CurrentCamera
		local distance = if camera then effectDistance(effect, camera.CFrame.Position) else nil
		if distance == nil then
			return
		end
		state.fade =
			math.clamp((state.fadeEnd - distance) / (state.fadeEnd - state.fadeStart), 0, 1)
		if effect:IsA("ParticleEmitter") then
			-- Leave Enabled untouched so authored disabled emitters never begin emitting.
			applyParticleQuality(effect, appliedMultiplier or 1)
		else
			local reentryBand = math.min(16, (state.fadeEnd - state.fadeStart) * 0.1)
			if distance >= state.fadeEnd then
				state.isInRange = false
			elseif distance <= state.fadeEnd - reentryBand then
				state.isInRange = true
			end
			effect.Enabled = state.baseEnabled and state.isInRange
			state.appliedEnabled = effect.Enabled
		end
	end

	local function observeDistanceEffect(effect: DistanceEffect)
		if effectObservers[effect] then
			return
		end
		local function refresh()
			if
				not isRunning
				or generation ~= currentGeneration
				or not effect:IsDescendantOf(environment)
			then
				return
			end
			local fadeStart = effect:GetAttribute("EffectFadeStart")
			local fadeEnd = effect:GetAttribute("EffectFadeEnd")
			if
				typeof(fadeStart) == "number"
				and typeof(fadeEnd) == "number"
				and fadeStart >= 0
				and fadeEnd > fadeStart
				and fadeEnd < math.huge
			then
				local state = distanceEffects[effect]
				if not state then
					local initialState: DistanceState = {
						fadeStart = fadeStart,
						fadeEnd = fadeEnd,
						fade = 1,
						isInRange = true,
						baseEnabled = effect.Enabled,
					}
					state = initialState
					distanceEffects[effect] = state
				else
					state.fadeStart, state.fadeEnd = fadeStart, fadeEnd
				end
				updateDistanceEffect(effect, state)
			else
				releaseDistanceEffect(effect)
				if effect:IsA("ParticleEmitter") then
					applyParticleQuality(effect, appliedMultiplier or 1)
				end
			end
		end
		effectObservers[effect] = {
			effect:GetAttributeChangedSignal("EffectFadeStart"):Connect(refresh),
			effect:GetAttributeChangedSignal("EffectFadeEnd"):Connect(refresh),
		}
		refresh()
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
		if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Light") then
			observeDistanceEffect(instance)
		end
		if instance:IsA("ParticleEmitter") then
			applyParticleQuality(instance, multiplier)
		elseif instance:IsA("Beam") then
			applyBeamQuality(instance, multiplier)
		elseif instance:IsA("MeshPart") then
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

		for _, instance in environment:GetDescendants() do
			applyInstance(instance, multiplier)
		end
	end

	lifetime:Add(environment.DescendantAdded:Connect(function(instance)
		if
			isRunning
			and generation == currentGeneration
			and instance:IsDescendantOf(environment)
		then
			applyInstance(instance, qualityMultiplier())
		end
	end))
	lifetime:Add(environment.DescendantRemoving:Connect(releaseInstance))
	applyEnvironmentQuality()
	local distanceAccumulator = 0
	lifetime:Add(RunService.Heartbeat:Connect(function(deltaTime)
		if not isRunning or generation ~= currentGeneration then
			return
		end
		distanceAccumulator += deltaTime
		if distanceAccumulator < DISTANCE_UPDATE_INTERVAL then
			return
		end
		distanceAccumulator %= DISTANCE_UPDATE_INTERVAL
		-- Only opted-in effects are visited here; meshes retain event-driven quality updates.
		for effect, state in distanceEffects do
			updateDistanceEffect(effect, state)
		end
	end))

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
