--!strict
-- ServerStorage/Tests/__tests__/BaseRuntime.spec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local Types = require(ReplicatedStorage.Shared.Types)
local BaseRuntime = require(ServerScriptService.Services.BaseService.BaseRuntime)

local afterEach = JestGlobals.afterEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local STATION_DEFINITION_ID = "basic_crafting_station"
local STATION_MODEL_NAME = "PB_CraftingStation_Root"
local fixtureRoots: { Instance } = {}

type Slots = { [number]: { userId: number, base: Model } }
type Fixture = {
	template: Model,
	arena: BasePart,
	baseIslands: Folder,
	basesFolder: Folder,
}

local function track<T>(instance: T): T
	table.insert(fixtureRoots, instance :: any)
	return instance
end

local function fakePlayer(userId: number): Player
	return ({ UserId = userId, DisplayName = `Player {userId}` } :: unknown) :: Player
end

local function savedBase(): Types.BaseRecord
	return {
		stands = {
			["1"] = {},
			["2"] = {},
			["3"] = {},
			["4"] = {},
		},
		buildSlotUpgrades = 0,
		shrines = {},
		craftingStation = {
			id = "station_123",
			craftingStationId = STATION_DEFINITION_ID,
		},
	}
end

local function createTemplate(stationKind: "Model" | "Folder" | "Missing"): Model
	local template = track(Instance.new("Model"))
	template.Name = "BaseLevel1"

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(20, 2, 20)
	floor.Parent = template

	local nameSign = Instance.new("Part")
	nameSign.Name = "NameSign"
	nameSign.Anchored = true
	nameSign.Parent = template

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "SurfaceGui"
	surfaceGui.Parent = nameSign

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Parent = surfaceGui

	local spawn = Instance.new("Part")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Parent = template

	local stands = Instance.new("Folder")
	stands.Name = "Stands"
	stands.Parent = template
	for standId = 1, 4 do
		local stand = Instance.new("Part")
		stand.Name = `LegacyStand{standId}`
		stand:SetAttribute("Id", standId)
		stand.Parent = stands
		if standId == 1 then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Prompt"
			prompt.Parent = stand
		end
	end

	if stationKind ~= "Missing" then
		local station = Instance.new(stationKind)
		station.Name = STATION_MODEL_NAME
		station.Parent = template
		if station:IsA("Model") then
			local stationVisual = Instance.new("Part")
			stationVisual.Name = "StationVisual"
			stationVisual.Anchored = true
			stationVisual.Parent = station
		end
	end

	return template
end

local function createFixture(stationKind: "Model" | "Folder" | "Missing"): Fixture
	local arena = track(Instance.new("Part"))
	arena.Name = "Arena"
	arena.Anchored = true
	arena.Position = Vector3.new(100, 0, 0)

	local baseIslands = track(Instance.new("Folder"))
	baseIslands.Name = "BaseIslands"
	local island = Instance.new("Model")
	island.Name = "BaseIsland0"
	island.Parent = baseIslands
	local collision = Instance.new("Folder")
	collision.Name = "Collision"
	collision.Parent = island
	local grass = Instance.new("Part")
	grass.Name = "Grass"
	grass.Anchored = true
	grass.Size = Vector3.new(64, 2, 64)
	grass.Parent = collision

	local basesFolder = track(Instance.new("Folder"))
	basesFolder.Name = "Bases"

	return {
		template = createTemplate(stationKind),
		arena = arena,
		baseIslands = baseIslands,
		basesFolder = basesFolder,
	}
end

local function spawn(
	player: Player,
	slots: Slots,
	fixture: Fixture,
	baseRecord: Types.BaseRecord
): (boolean, string?)
	return BaseRuntime.SpawnBaseFor(
		player,
		slots,
		1,
		fixture.template,
		baseRecord,
		fixture.arena,
		fixture.baseIslands,
		fixture.basesFolder
	)
end

local function getStation(base: Model): Model
	local station = base:FindFirstChild(STATION_MODEL_NAME)
	assert(station and station:IsA("Model"), "Expected the spawned Crafting Station model")
	return station
end

local function expectNoSpawn(slots: Slots, basesFolder: Folder)
	expect(slots[1]).toBeNil()
	expect(#basesFolder:GetChildren()).toBe(0)
end

afterEach(function()
	for _, instance in fixtureRoots do
		instance:Destroy()
	end
	table.clear(fixtureRoots)
end)

describe("BaseRuntime", function()
	it("refreshes capacity after construction without changing the permanent Station", function()
		local fixture = createFixture("Model")
		local player = fakePlayer(42)
		local slots: Slots = {}
		local record = savedBase()
		expect((spawn(player, slots, fixture, record))).toBe(true)
		local base = slots[1].base
		record.shrines = {
			built = { id = "built", shrineId = "fire_shrine", buildSlotId = 1, level = 1 },
		}
		expect(BaseRuntime.RefreshCapacity(base, record)).toBe(true)
		expect(base:GetAttribute("UsedShrineSlots")).toBe(1)
		expect(base:GetAttribute("UnlockedShrineSlots")).toBe(2)
		expect(getStation(base):GetAttribute("StationInstanceId")).toBe("station_123")
		record.buildSlotUpgrades = -1
		expect(BaseRuntime.RefreshCapacity(base, record)).toBe(false)
		expect(base:GetAttribute("UsedShrineSlots")).toBe(1)
	end)

	it("stamps identities without counting legacy stands or the permanent Station", function()
		local fixture = createFixture("Model")
		local player = fakePlayer(42)
		local slots: Slots = {}

		local spawned, spawnError = spawn(player, slots, fixture, savedBase())

		expect(spawned).toBe(true)
		expect(spawnError).toBeNil()
		local base = slots[1].base
		expect(base.Parent).toBe(fixture.basesFolder)
		expect(base:GetAttribute("UsedShrineSlots")).toBe(0)
		expect(base:GetAttribute("UnlockedShrineSlots")).toBe(2)
		expect(base:GetAttribute("MaxShrineSlots")).toBe(6)

		local station = getStation(base)
		expect(station:GetAttribute("StationInstanceId")).toBe("station_123")
		expect(station:GetAttribute("StationDefinitionId")).toBe(STATION_DEFINITION_ID)
		expect(station:GetAttribute("OwnerId")).toBe(player.UserId)

		local prompt = base:FindFirstChild("Prompt", true)
		expect(prompt and prompt:GetAttribute("OwnerId")).toBe(player.UserId)
	end)

	it("keeps the saved Station identity after removing and respawning the runtime Base", function()
		local fixture = createFixture("Model")
		local player = fakePlayer(57)
		local slots: Slots = {}
		local baseRecord = savedBase()

		expect((spawn(player, slots, fixture, baseRecord))).toBe(true)
		local firstStation = getStation(slots[1].base)
		local firstInstanceId = firstStation:GetAttribute("StationInstanceId")
		local firstDefinitionId = firstStation:GetAttribute("StationDefinitionId")

		local removed, removeError = BaseRuntime.RemoveBaseFor(player, slots)
		expect(removed).toBe(true)
		expect(removeError).toBeNil()
		expectNoSpawn(slots, fixture.basesFolder)

		expect((spawn(player, slots, fixture, baseRecord))).toBe(true)
		local secondStation = getStation(slots[1].base)
		expect(secondStation:GetAttribute("StationInstanceId")).toBe(firstInstanceId)
		expect(secondStation:GetAttribute("StationDefinitionId")).toBe(firstDefinitionId)
	end)

	it("rejects missing or invalid saved Base state without allocating a runtime slot", function()
		local fixture = createFixture("Model")
		local player = fakePlayer(71)
		local slots: Slots = {}

		local missing = (nil :: unknown) :: Types.BaseRecord
		expect((spawn(player, slots, fixture, missing))).toBe(false)
		expectNoSpawn(slots, fixture.basesFolder)

		local invalid = savedBase()
		invalid.craftingStation = {
			id = "",
			craftingStationId = STATION_DEFINITION_ID,
		}
		expect((spawn(player, slots, fixture, invalid))).toBe(false)
		expectNoSpawn(slots, fixture.basesFolder)
	end)

	it(
		"rejects missing or invalid Station assets without leaving a slot or orphaned Base",
		function()
			local player = fakePlayer(88)

			for _, stationKind in { "Missing", "Folder" } do
				local fixture = createFixture(stationKind :: "Missing" | "Folder")
				local slots: Slots = {}

				expect((spawn(player, slots, fixture, savedBase()))).toBe(false)
				expectNoSpawn(slots, fixture.basesFolder)
			end
		end
	)
end)
