--!strict
-- StarterPlayer/StarterPlayerScripts/Controllers/EnvironmentController/Audio

local Audio = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local lifetime = Trove.new()
local isRunning = false
local generation = 0

function Audio.Init(_context: unknown) end

function Audio.Start()
	if isRunning then
		return
	end
	isRunning = true
	generation += 1
	local currentGeneration = generation
	-- Restrained ambient audio layers for the floating-island environment.

	local SoundService = game:GetService("SoundService")

	local WIND_SOUND_ID = "rbxassetid://8202539690"
	local VOLCANO_SOUND_ID = "rbxassetid://9112823563"
	local GUST_SOUND_ID = "rbxassetid://9113286782"

	local AMBIENCE_GROUP_NAME = "EnvironmentAmbience"
	local ARENA_RADIUS = 245
	local GUST_HEIGHT_OFFSET = 14

	local runtime = workspace:WaitForChild("Runtime")
	if not isRunning or generation ~= currentGeneration then
		return
	end
	local audioFolder = Instance.new("Folder")
	audioFolder.Name = "Audio"
	audioFolder.Parent = runtime
	lifetime:Add(audioFolder)

	local function createSoundGroup(): SoundGroup
		local existing = SoundService:FindFirstChild(AMBIENCE_GROUP_NAME)
		if existing and existing:IsA("SoundGroup") then
			return existing
		end

		local soundGroup = Instance.new("SoundGroup")
		soundGroup.Name = AMBIENCE_GROUP_NAME
		soundGroup.Volume = 1
		soundGroup.Parent = SoundService
		lifetime:Add(soundGroup)
		return soundGroup
	end

	local function createAnchor(name: string, position: Vector3): Part
		local anchor = Instance.new("Part")
		anchor.Name = name
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Size = Vector3.one
		anchor.Transparency = 1
		anchor.Position = position
		anchor.Parent = audioFolder
		lifetime:Add(anchor)
		return anchor
	end

	local function createSound(
		name: string,
		soundId: string,
		parent: Instance,
		soundGroup: SoundGroup
	): Sound
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = soundId
		sound.SoundGroup = soundGroup
		sound.Parent = parent
		lifetime:Add(sound)
		return sound
	end

	local ambienceGroup = createSoundGroup()

	local wind = createSound("HighAltitudeWind", WIND_SOUND_ID, SoundService, ambienceGroup)
	wind.Looped = true
	wind.Volume = 0.09
	wind.PlaybackSpeed = 0.94
	wind:Play()

	local world = workspace:WaitForChild("World")
	local islands = world:WaitForChild("ElementalIslands")
	if not isRunning or generation ~= currentGeneration then
		return
	end
	local volcanoStarted = false
	local function tryStartVolcano(fireIsland: Instance?)
		if not isRunning or generation ~= currentGeneration or volcanoStarted then
			return
		end
		if
			not fireIsland
			or fireIsland.Name ~= "FireIsland"
			or fireIsland.Parent ~= islands
			or not (fireIsland:IsA("Model") or fireIsland:IsA("BasePart"))
		then
			return
		end
		volcanoStarted = true
		local volcanoAnchor = createAnchor("VolcanoAudioAnchor", fireIsland:GetPivot().Position)
		local volcano = createSound("VolcanoRumble", VOLCANO_SOUND_ID, volcanoAnchor, ambienceGroup)
		volcano.Looped = true
		volcano.Volume = 0.2
		volcano.PlaybackSpeed = 0.9
		volcano.RollOffMode = Enum.RollOffMode.InverseTapered
		volcano.RollOffMinDistance = 70
		volcano.RollOffMaxDistance = 700

		local volcanoEqualizer = Instance.new("EqualizerSoundEffect")
		volcanoEqualizer.Name = "DeepRumble"
		volcanoEqualizer.LowGain = 2
		volcanoEqualizer.MidGain = -3
		volcanoEqualizer.HighGain = -10
		volcanoEqualizer.Parent = volcano
		volcano:Play()
	end
	-- Persistent models can arrive after their parent folder during initial replication.
	lifetime:Add(islands.ChildAdded:Connect(tryStartVolcano))
	tryStartVolcano(islands:FindFirstChild("FireIsland"))

	local arenaModel = world:WaitForChild("Arena")
	if not isRunning or generation ~= currentGeneration then
		return
	end
	assert(arenaModel:IsA("Model"), "[EnvironmentController.Audio] Arena must be a Model")
	local arenaCenter = arenaModel:GetPivot().Position
	local gustAnchor = createAnchor("BridgeGustAudioAnchor", arenaCenter)
	local gust = createSound("BridgeWindGust", GUST_SOUND_ID, gustAnchor, ambienceGroup)
	gust.Volume = 0.12
	gust.PlaybackSpeed = 0.92
	gust.RollOffMode = Enum.RollOffMode.InverseTapered
	gust.RollOffMinDistance = 45
	gust.RollOffMaxDistance = 330

	local random = Random.new()

	lifetime:Add(task.defer(function()
		task.wait(random:NextNumber(6, 10))
		while gustAnchor.Parent do
			local entranceIndex = random:NextInteger(0, 7)
			local angle = entranceIndex * math.pi / 4
			gustAnchor.Position = arenaCenter
				+ Vector3.new(
					math.cos(angle) * ARENA_RADIUS,
					GUST_HEIGHT_OFFSET,
					math.sin(angle) * ARENA_RADIUS
				)
			gust.PlaybackSpeed = random:NextNumber(0.88, 1)
			gust.Volume = random:NextNumber(0.08, 0.13)
			gust:Play()
			task.wait(random:NextNumber(18, 30))
		end
	end))
end

function Audio.Stop()
	isRunning = false
	generation += 1
	lifetime:Clean()
end

return Audio
