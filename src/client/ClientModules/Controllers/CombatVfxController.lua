-- StarterPlayer/StarterPlayerScripts/ClientModules/Controllers/CombatVfxController

local CombatVfxController = {}

function CombatVfxController.Start(_context: any)
-- All effects are cosmetic; CombatImpact carries only server-confirmed outcomes.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Equipment = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Metadata"):WaitForChild("Equipment"))
local presentationBus = require(script:FindFirstAncestor("ClientModules"):WaitForChild("CombatPresentationBus"))
local CombatImpact = ReplicatedStorage:WaitForChild("Network"):WaitForChild("CombatImpact") :: RemoteEvent
local localPlayer = Players.LocalPlayer

type AirTrailState = {
	token: number,
	character: Model,
	root: BasePart,
	attachment: Attachment,
	emitter: ParticleEmitter,
	lastPosition: Vector3,
	particleRemainder: number,
	observedTakeoff: boolean,
}

type LocalPresentation = {
	character: Model,
	kind: "Impact" | "ShieldImpact",
}

type PooledSound = {
	sound: Sound,
	inUse: boolean,
	token: number,
}

local HIT_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local IMPACT_RING_TEXTURE = "rbxassetid://1266170131"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local HIT_BURST_PARTICLES = 26
local AIR_TRAIL_PARTICLES_PER_STUD = 1.15
local AIR_TRAIL_BURST_PARTICLES = 8
local TRAIL_POLL_SECONDS = 0.03
local TRAIL_FADE_SECONDS = 0.9
local MAX_TRAIL_PARTICLES_PER_POLL = 10
local SOUND_POOL_SIZE = 3

local activeTrails: { [Model]: AirTrailState } = {}
local localPresentations: { [number]: LocalPresentation } = {}
local soundPools: { [string]: { PooledSound } } = {}
local nextTrailToken = 0

local function destroyAfter(instance: Instance, seconds: number)
	task.delay(seconds, function()
		if instance.Parent then instance:Destroy() end
	end)
end

local function getEffectPart(character: Model): BasePart?
	for _, name in { "UpperTorso", "Torso", "HumanoidRootPart" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then return part end
	end
	return nil
end

local function getShieldModel(character: Model): Model?
	local folder = character:FindFirstChild("EquippedEquipment")
	local shield = folder and folder:FindFirstChild("LeftEquipment")
	return if shield and shield:IsA("Model") then shield else nil
end

local function preloadImpactSounds()
	local sounds = {}
	for _, profile in Equipment.Profiles do
		local soundId = profile.impactSoundId
		if type(soundId) == "string" and soundId ~= "" and not soundPools[soundId] then
			local pool = {}
			soundPools[soundId] = pool
			for _ = 1, SOUND_POOL_SIZE do
				local sound = Instance.new("Sound")
				sound.Name = "CombatImpactSoundPool"
				sound.SoundId = soundId
				sound.Parent = SoundService
				table.insert(pool, { sound = sound, inUse = false, token = 0 })
				table.insert(sounds, sound)
			end
		end
	end
	if #sounds > 0 then
		pcall(ContentProvider.PreloadAsync, ContentProvider, sounds)
	end
end

task.spawn(preloadImpactSounds)

local function playHitBurst(character: Model)
	local effectPart = getEffectPart(character)
	if not effectPart then return end
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatHitBurst"
	attachment.Position = Vector3.new(0, effectPart.Size.Y * 0.18, 0)
	attachment.Parent = effectPart

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "CombatHitSparks"
	sparks.Texture = HIT_TEXTURE
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.35, 0.55)
	sparks.Speed = NumberRange.new(10, 17)
	sparks.Drag = 7
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-180, 180)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 72, 24), Color3.fromRGB(255, 164, 46))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.LockedToPart = false
	sparks.Parent = attachment

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

	local existing = character:FindFirstChild("CombatHitFlash")
	if existing then existing:Destroy() end
	local flash = Instance.new("Highlight")
	flash.Name = "CombatHitFlash"
	flash.Adornee = character
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.FillColor = Color3.fromRGB(255, 70, 24)
	flash.FillTransparency = 0.45
	flash.OutlineColor = Color3.fromRGB(255, 166, 64)
	flash.OutlineTransparency = 0.05
	flash.Parent = character

	sparks:Emit(HIT_BURST_PARTICLES)
	ring:Emit(1)
	destroyAfter(attachment, 0.9)
	destroyAfter(flash, 0.18)
end

local function playShieldBurst(character: Model, shield: Model?, attackerCharacter: Model?)
	local bubble = character:FindFirstChild("ShieldBubble")
	local effectPart: BasePart? = if bubble and bubble:IsA("BasePart") then bubble else nil
	if not effectPart then
		local shieldFace = shield and shield:FindFirstChild("ShieldFace", true)
		effectPart = if shieldFace and shieldFace:IsA("BasePart") then shieldFace else nil
	end
	if not effectPart or not effectPart:IsA("BasePart") then
		effectPart = getEffectPart(character)
	end
	if not effectPart or not effectPart:IsA("BasePart") then return end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ShieldImpactBurst"
	attachment.Parent = effectPart
	if effectPart == bubble then
		local attackerRoot = attackerCharacter and attackerCharacter:FindFirstChild("HumanoidRootPart")
		local outward = if attackerRoot and attackerRoot:IsA("BasePart")
			then attackerRoot.Position - effectPart.Position
			else -effectPart.CFrame.LookVector
		if outward.Magnitude > 0.001 then
			attachment.Position = effectPart.CFrame:VectorToObjectSpace(outward.Unit)
				* (effectPart.Size.X * 0.48)
		end
	end
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "ShieldImpactSparks"
	sparks.Texture = HIT_TEXTURE
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.25, 0.45)
	sparks.Speed = NumberRange.new(7, 12)
	sparks.Drag = 6
	sparks.SpreadAngle = Vector2.new(160, 160)
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-120, 120)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 218, 105), Color3.fromRGB(118, 225, 255))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.LockedToPart = false
	sparks.Parent = attachment
	sparks:Emit(22)

	local flash = Instance.new("Highlight")
	flash.Name = "ShieldImpactFlash"
	flash.Adornee = bubble or shield or character
	flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	flash.FillColor = Color3.fromRGB(255, 205, 72)
	flash.FillTransparency = 0.7
	flash.OutlineColor = Color3.fromRGB(135, 229, 255)
	flash.OutlineTransparency = 0.05
	flash.Parent = character
	destroyAfter(attachment, 0.7)
	destroyAfter(flash, 0.16)
end

local function playImpactSound(character: Model, soundId: any)
	local effectPart = getEffectPart(character)
	if not effectPart or type(soundId) ~= "string" or soundId == "" then return end
	local entry: PooledSound? = nil
	for _, candidate in soundPools[soundId] or {} do
		if not candidate.inUse then
			entry = candidate
			break
		end
	end
	local sound = if entry then entry.sound else Instance.new("Sound")
	if entry then
		entry.inUse = true
		entry.token += 1
	else
		sound.SoundId = soundId
	end
	local token = entry and entry.token or 0
	sound.Volume = 0.65
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 7
	sound.RollOffMaxDistance = 60
	sound.Parent = effectPart
	sound.TimePosition = 0.06
	sound:Play()
	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		if entry and entry.token == token then
			entry.inUse = false
			sound:Stop()
			sound.TimePosition = 0
			sound.Parent = SoundService
		elseif not entry and sound.Parent then
			sound:Destroy()
		end
	end
	sound.Ended:Once(cleanup)
	task.delay(4, cleanup)
end

local function stopAirTrail(character: Model, preserveParticles: boolean)
	local state = activeTrails[character]
	if not state then return end
	activeTrails[character] = nil
	state.emitter.Enabled = false
	if preserveParticles then
		destroyAfter(state.attachment, TRAIL_FADE_SECONDS)
	elseif state.attachment.Parent then
		state.attachment:Destroy()
	end
end

local function startAirTrail(character: Model, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or duration <= 0 then return end
	stopAirTrail(character, false)
	nextTrailToken += 1
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatAirSmoke"
	attachment.Position = Vector3.new(0, -0.45, 0)
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "CombatAirSmokeEmitter"
	emitter.Texture = SMOKE_TEXTURE
	emitter.Enabled = true
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
		observedTakeoff = false,
	}
	activeTrails[character] = state
	emitter:Emit(AIR_TRAIL_BURST_PARTICLES)
	task.spawn(function()
		while activeTrails[character] == state do
			if not character.Parent or not root.Parent then
				stopAirTrail(character, true)
				return
			end
			local position = root.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			params.IgnoreWater = true
			local velocity = root.AssemblyLinearVelocity
			local grounded = workspace:Raycast(position, -Vector3.yAxis * 3, params) ~= nil
			if velocity.Y >= 2 or not grounded then
				state.observedTakeoff = true
			end
			if state.observedTakeoff and velocity.Y <= 0 and math.abs(velocity.Y) <= 12 and grounded then
				stopAirTrail(character, true)
				return
			end
			state.particleRemainder += (position - state.lastPosition).Magnitude * AIR_TRAIL_PARTICLES_PER_STUD
			state.lastPosition = position
			local requested = math.floor(state.particleRemainder)
			if requested > 0 then
				local emitted = math.min(requested, MAX_TRAIL_PARTICLES_PER_POLL)
				emitter:Emit(emitted)
				state.particleRemainder = if requested > MAX_TRAIL_PARTICLES_PER_POLL
					then 0 else state.particleRemainder - emitted
			end
			task.wait(TRAIL_POLL_SECONDS)
		end
	end)
	task.delay(duration, function()
		if activeTrails[character] == state then stopAirTrail(character, true) end
	end)
end

presentationBus.Event:Connect(function(action: string, character: Model, presentation: any, sequence: number)
	if type(sequence) ~= "number" or not character or not character:IsA("Model") then return end
	if action == "Landed" then
		stopAirTrail(character, true)
		return
	end
	local kind: "Impact" | "ShieldImpact"
	if action == "LocalImpact" then
		kind = "Impact"
		playImpactSound(character, presentation)
		playHitBurst(character)
	elseif action == "LocalShieldImpact" then
		kind = "ShieldImpact"
		playShieldBurst(
			character,
			if presentation and presentation:IsA("Model") then presentation else nil,
			localPlayer.Character
		)
	else
		return
	end
	local entry = { character = character, kind = kind }
	localPresentations[sequence] = entry
	task.delay(1, function()
		if localPresentations[sequence] == entry then localPresentations[sequence] = nil end
	end)
end)

CombatImpact.OnClientEvent:Connect(function(action: unknown, payload: any)
	if type(payload) ~= "table" then return end
	local target = type(payload.targetUserId) == "number" and Players:GetPlayerByUserId(payload.targetUserId)
	local character = target and target.Character
	if action == "Landed" then
		if character then stopAirTrail(character, true) end
		return
	end
	if action ~= "Impact" or not character then return end
	local kind = if payload.blocked == true then "ShieldImpact" else "Impact"
	local localEntry = type(payload.sequence) == "number" and localPresentations[payload.sequence] or nil
	local wasLocal = payload.attackerUserId == localPlayer.UserId
		and localEntry ~= nil
		and localEntry.character == character
		and localEntry.kind == kind
	if localEntry and localEntry.character == character then
		localPresentations[payload.sequence] = nil
	end
	if not wasLocal then
		if kind == "ShieldImpact" then
			local attacker = type(payload.attackerUserId) == "number"
				and Players:GetPlayerByUserId(payload.attackerUserId)
			playShieldBurst(character, getShieldModel(character), attacker and attacker.Character)
		else
			playImpactSound(character, payload.impactSoundId)
			playHitBurst(character)
		end
	end
	if kind == "Impact" and type(payload.airTrailSeconds) == "number" then
		startAirTrail(character, payload.airTrailSeconds)
	end
end)
end

function CombatVfxController.Destroy()
end

return CombatVfxController
