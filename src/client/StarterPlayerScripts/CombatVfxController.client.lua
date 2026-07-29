-- StarterPlayerScripts/CombatVfxController
-- The attacker renders contact immediately. The server relays that trusted contact so
-- every other client sees the same presentation and the target applies its own launch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local combatVfxEvent: RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatVfxEvent")
local combatPresentationBus = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("CombatPresentationBus"))
local clientKnockbackController = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("ClientKnockbackController"))
local weaponsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Weapons"))
local localPlayer = Players.LocalPlayer

type AirTrailState = {
	token: number,
	character: Model,
	root: BasePart,
	attachment: Attachment,
	emitter: ParticleEmitter,
	lastPosition: Vector3,
	particleRemainder: number,
	particlesPerStud: number,
}

type PooledImpactSound = {
	sound: Sound,
	inUse: boolean,
	token: number,
}

type LocalHitPresentation = {
	character: Model,
	kind: "Impact" | "ShieldImpact",
}

local activeAirTrails: { [Model]: AirTrailState } = {}
local nextTrailToken = 0
local impactSoundPools: { [string]: { PooledImpactSound } } = {}
local locallyRenderedHits: { [number]: LocalHitPresentation } = {}

local HIT_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local IMPACT_RING_TEXTURE = "rbxassetid://1266170131"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local TRAIL_POLL_SECONDS = 0.03
local TRAIL_FADE_SECONDS = 0.9
local MAX_TRAIL_PARTICLES_PER_POLL = 10
local IMPACT_SOUND_POOL_SIZE = 3
local LOCAL_HIT_MEMORY_SECONDS = 1

local function getNumber(config: any, key: string, fallback: number, minimum: number, maximum: number): number
	local value = if type(config) == "table" then config[key] else nil
	if type(value) ~= "number" or value ~= value then
		return fallback
	end

	return math.clamp(value, minimum, maximum)
end

local function getSoundConfig(config: any): any?
	local soundConfig = if type(config) == "table" then config.impactSound else nil
	return if type(soundConfig) == "table" then soundConfig else nil
end

local function isAssetSoundId(value: any): boolean
	return type(value) == "string" and string.match(value, "^rbxassetid://%d+$") ~= nil
end

-- The impact must be ready before the first swing. Creating a Sound only at hit time
-- makes Roblox fetch/decode the asset after the server confirmation, which feels late.
local function preloadConfiguredImpactSounds()
	local sounds = {}
	local seen: { [string]: boolean } = {}
	for _, profile in pairs(weaponsData.Profiles) do
		local soundConfig = profile.vfx and profile.vfx.impactSound
		local soundId = type(soundConfig) == "table" and soundConfig.id or nil
		if isAssetSoundId(soundId) and not seen[soundId] then
			seen[soundId] = true
			local pool = {}
			impactSoundPools[soundId] = pool
			for _ = 1, IMPACT_SOUND_POOL_SIZE do
				local sound = Instance.new("Sound")
				sound.Name = "CombatImpactSoundPool"
				sound.SoundId = soundId
				sound.Parent = SoundService
				table.insert(pool, {
					sound = sound,
					inUse = false,
					token = 0,
				})
				table.insert(sounds, sound)
			end
		end
	end

	if #sounds > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(sounds)
		end)
	end
end

task.spawn(preloadConfiguredImpactSounds)

local function getEffectPart(character: Model): BasePart?
	for _, name in ipairs({ "UpperTorso", "Torso", "HumanoidRootPart" }) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	return nil
end

local function destroyAfter(instance: Instance, seconds: number)
	task.delay(seconds, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

local function playHitBurst(character: Model, config: any)
	local effectPart = getEffectPart(character)
	if not effectPart then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatHitBurst"
	attachment.Position = Vector3.new(0, effectPart.Size.Y * 0.18, 0)
	attachment.Parent = effectPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CombatHitSparks"
	emitter.Texture = HIT_TEXTURE
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.55)
	emitter.Speed = NumberRange.new(10, 17)
	emitter.Drag = 7
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 72, 24), Color3.fromRGB(255, 164, 46))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = false
	emitter.Parent = attachment

	local ring = Instance.new("ParticleEmitter")
	ring.Name = "CombatHitRing"
	ring.Texture = IMPACT_RING_TEXTURE
	ring.Rate = 0
	ring.Lifetime = NumberRange.new(0.35, 0.45)
	ring.Speed = NumberRange.new(0, 0)
	ring.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 3.6),
	})
	ring.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	ring.Color = ColorSequence.new(Color3.fromRGB(255, 82, 28), Color3.fromRGB(255, 174, 58))
	ring.LightEmission = 1
	ring.LightInfluence = 0
	ring.LockedToPart = false
	ring.Parent = attachment

	local existingFlash = character:FindFirstChild("CombatHitFlash")
	if existingFlash and existingFlash:IsA("Highlight") then
		existingFlash:Destroy()
	end

	local flash = Instance.new("Highlight")
	flash.Name = "CombatHitFlash"
	flash.Adornee = character
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.FillColor = Color3.fromRGB(255, 70, 24)
	flash.FillTransparency = 0.45
	flash.OutlineColor = Color3.fromRGB(255, 166, 64)
	flash.OutlineTransparency = 0.05
	flash.Parent = character

	emitter:Emit(math.floor(getNumber(config, "hitBurstParticles", 26, 0, 48)))
	ring:Emit(1)
	destroyAfter(attachment, 0.9)
	destroyAfter(flash, 0.18)
end

local function playShieldBurst(character: Model, shield: Tool?)
	local effectPart = if shield then shield:FindFirstChild("ShieldFace", true) else nil
	if not (effectPart and effectPart:IsA("BasePart")) then
		effectPart = getEffectPart(character)
	end
	if not effectPart then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "ShieldImpactBurst"
	attachment.Parent = effectPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ShieldImpactSparks"
	emitter.Texture = HIT_TEXTURE
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(7, 12)
	emitter.Drag = 6
	emitter.SpreadAngle = Vector2.new(160, 160)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 218, 105), Color3.fromRGB(118, 225, 255))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = false
	emitter.Parent = attachment
	emitter:Emit(22)

	local flash = Instance.new("Highlight")
	flash.Name = "ShieldImpactFlash"
	flash.Adornee = shield or character
	flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	flash.FillColor = Color3.fromRGB(255, 205, 72)
	flash.FillTransparency = 0.7
	flash.OutlineColor = Color3.fromRGB(135, 229, 255)
	flash.OutlineTransparency = 0.05
	flash.Parent = character

	destroyAfter(attachment, 0.7)
	destroyAfter(flash, 0.16)
end

local function acquireImpactSound(soundId: string): PooledImpactSound?
	local pool = impactSoundPools[soundId]
	if not pool then
		return nil
	end

	for _, entry in ipairs(pool) do
		if not entry.inUse then
			entry.inUse = true
			entry.token += 1
			return entry
		end
	end
	return nil
end

local function releaseImpactSound(entry: PooledImpactSound, token: number)
	if entry.token ~= token then
		return
	end

	entry.inUse = false
	entry.sound:Stop()
	entry.sound.TimePosition = 0
	entry.sound.Parent = SoundService
end

local function playImpactSound(character: Model, config: any)
	local effectPart = getEffectPart(character)
	local soundConfig = getSoundConfig(config)
	local soundId = soundConfig and soundConfig.id
	if not (effectPart and isAssetSoundId(soundId)) then
		return
	end

	local pooledSound = acquireImpactSound(soundId)
	local sound = pooledSound and pooledSound.sound or Instance.new("Sound")
	if not pooledSound then
		sound.Name = "CombatImpactSoundFallback"
		sound.SoundId = soundId
	end

	sound.Volume = getNumber(soundConfig, "volume", 0.65, 0, 2)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = getNumber(soundConfig, "minDistance", 7, 1, 40)
	sound.RollOffMaxDistance = getNumber(soundConfig, "maxDistance", 60, 5, 200)
	sound.Parent = effectPart
	sound.TimePosition = getNumber(soundConfig, "startTimeSeconds", 0, 0, 0.5)
	sound:Play()

	local poolToken = if pooledSound then pooledSound.token else 0
	local function cleanup()
		if pooledSound then
			releaseImpactSound(pooledSound, poolToken)
		elseif sound.Parent then
			sound:Destroy()
		end
	end
	sound.Ended:Once(function()
		cleanup()
	end)
	task.delay(4, cleanup)
end

local function destroyAirTrail(state: AirTrailState, preserveParticles: boolean)
	state.emitter.Enabled = false
	if preserveParticles then
		destroyAfter(state.attachment, TRAIL_FADE_SECONDS)
	elseif state.attachment.Parent then
		state.attachment:Destroy()
	end
end

local function stopAirTrail(character: Model, expectedToken: number?, preserveParticles: boolean): boolean
	local state = activeAirTrails[character]
	if not state or (expectedToken and state.token ~= expectedToken) then
		return false
	end

	activeAirTrails[character] = nil
	destroyAirTrail(state, preserveParticles)
	return true
end

local function startAirTrail(character: Model, durationSeconds: number, config: any)
	if durationSeconds <= 0 then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	-- A later confirmed impact replaces the old visual rather than stacking emitters.
	stopAirTrail(character, nil, false)

	nextTrailToken += 1
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatAirSmoke"
	attachment.Position = Vector3.new(0, -0.45, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CombatAirSmokeEmitter"
	emitter.Texture = SMOKE_TEXTURE
	emitter.Enabled = true
	-- Explicit distance-based emits leave smoke where the ragdoll travelled. A zero
	-- Rate avoids the old effect that continuously created a cloud around the root.
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.65, 0.95)
	emitter.Speed = NumberRange.new(0.15, 0.5)
	emitter.Drag = 2
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-25, 25)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 2.1),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.35, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(172, 156, 135), Color3.fromRGB(107, 99, 94))
	emitter.LightInfluence = 1
	emitter.VelocityInheritance = 0
	emitter.LockedToPart = false
	emitter.Parent = attachment

	local state: AirTrailState = {
		token = nextTrailToken,
		character = character,
		root = root,
		attachment = attachment,
		emitter = emitter,
		lastPosition = root.Position,
		particleRemainder = 0,
		particlesPerStud = getNumber(config, "airTrailParticlesPerStud", 1.15, 0.25, 3),
	}
	activeAirTrails[character] = state

	emitter:Emit(math.floor(getNumber(config, "airTrailBurstParticles", 12, 0, 30)))

	task.spawn(function()
		while activeAirTrails[character] == state do
			if not (state.character.Parent and state.root.Parent) then
				stopAirTrail(character, state.token, true)
				return
			end

			local currentPosition = state.root.Position
			local distance = (currentPosition - state.lastPosition).Magnitude
			state.lastPosition = currentPosition
			state.particleRemainder += distance * state.particlesPerStud

			local requestedParticles = math.floor(state.particleRemainder)
			if requestedParticles > 0 then
				local emittedParticles = math.min(requestedParticles, MAX_TRAIL_PARTICLES_PER_POLL)
				emitter:Emit(emittedParticles)
				if requestedParticles > MAX_TRAIL_PARTICLES_PER_POLL then
					-- Ignore teleport-sized gaps rather than making a cloud at the new position.
					state.particleRemainder = 0
				else
					state.particleRemainder -= emittedParticles
				end
			end

			task.wait(TRAIL_POLL_SECONDS)
		end
	end)

	task.delay(durationSeconds, function()
		stopAirTrail(character, state.token, true)
	end)
end

combatPresentationBus.Event:Connect(function(
	action: string,
	character: Model,
	presentation: any,
	sequence: number
)
	if type(sequence) ~= "number"
		or not (character and character:IsA("Model")) then
		return
	end

	local kind: "Impact" | "ShieldImpact"
	if action == "LocalImpact" then
		kind = "Impact"
		playImpactSound(character, presentation)
		playHitBurst(character, presentation)
	elseif action == "LocalShieldImpact" and presentation and presentation:IsA("Tool") then
		kind = "ShieldImpact"
		playShieldBurst(character, presentation)
	else
		return
	end

	local localPresentation: LocalHitPresentation = {
		character = character,
		kind = kind,
	}
	locallyRenderedHits[sequence] = localPresentation
	task.delay(LOCAL_HIT_MEMORY_SECONDS, function()
		if locallyRenderedHits[sequence] == localPresentation then
			locallyRenderedHits[sequence] = nil
		end
	end)
end)

combatVfxEvent.OnClientEvent:Connect(function(action: string, payload: any)
	if type(payload) ~= "table" then
		return
	end

	if action == "ApplyKnockback" then
		local character = payload.character
		local launchVelocity = payload.launchVelocity
		local angularVelocity = payload.angularVelocity
		local hitId = payload.hitId
		local launchDurationSeconds = payload.launchDurationSeconds
		local preserveControl = payload.preserveControl == true
		if character ~= localPlayer.Character
			or typeof(launchVelocity) ~= "Vector3"
			or typeof(angularVelocity) ~= "Vector3"
			or type(hitId) ~= "number"
			or type(launchDurationSeconds) ~= "number" then
			return
		end

		clientKnockbackController.Apply(
			character,
			hitId,
			launchVelocity,
			angularVelocity,
			launchDurationSeconds,
			preserveControl
		)
		return
	end

	if action == "Recovered" then
		local character = payload.character
		if character ~= localPlayer.Character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 then
			if root and root:IsA("BasePart") then
				root.AssemblyAngularVelocity = Vector3.zero
			end
			humanoid.AutoRotate = true
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			task.delay(0.08, function()
				if humanoid.Parent and humanoid.Health > 0
					and (humanoid:GetState() == Enum.HumanoidStateType.Physics
						or humanoid:GetState() == Enum.HumanoidStateType.PlatformStanding) then
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
			end)
		end
		return
	end

	local character = payload.character
	if not (character and character:IsA("Model")) then
		return
	end
	if action == "Landed" then
		stopAirTrail(character, nil, true)
		return
	end
	if action == "ShieldImpact" then
		local shield = payload.shield
		local sequence = payload.sequence
		local localPresentation = type(sequence) == "number" and locallyRenderedHits[sequence] or nil
		local wasLocallyRendered = payload.attackerUserId == localPlayer.UserId
			and localPresentation ~= nil
			and localPresentation.character == character
			and localPresentation.kind == "ShieldImpact"
		if localPresentation and localPresentation.character == character then
			locallyRenderedHits[sequence] = nil
		end
		if not wasLocallyRendered then
			playShieldBurst(character, if shield and shield:IsA("Tool") then shield else nil)
		end
		return
	end

	if action ~= "Impact" then
		return
	end

	local sequence = payload.sequence
	local localPresentation = type(sequence) == "number" and locallyRenderedHits[sequence] or nil
	local wasLocallyRendered = payload.attackerUserId == localPlayer.UserId
		and localPresentation ~= nil
		and localPresentation.character == character
		and localPresentation.kind == "Impact"
	if localPresentation and localPresentation.character == character then
		locallyRenderedHits[sequence] = nil
	end

	-- Suppress only the attacker's duplicate burst. Smoke still starts from the relay.
	if not wasLocallyRendered then
		playImpactSound(character, payload.config)
		playHitBurst(character, payload.config)
	end
	local airTrailSeconds = payload.airTrailSeconds
	if type(airTrailSeconds) == "number" and airTrailSeconds > 0 then
		startAirTrail(character, airTrailSeconds, payload.config)
	end
end)
