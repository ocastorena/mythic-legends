--!strict
-- ServerStorage/Tests/__tests__/LoadingAssets.spec

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Assets = require(ReplicatedFirst.LoadingScreen.Assets)
local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)

local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it
local afterEach = JestGlobals.afterEach
local fixtures: { Instance } = {}

local function folder(name: string, parent: Instance?): Folder
	local instance = Instance.new("Folder")
	instance.Name = name
	instance.Parent = parent
	if not parent then
		table.insert(fixtures, instance)
	end
	return instance
end

local function model(name: string, parent: Instance): Model
	local instance = Instance.new("Model")
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function mesh(name: string, parent: Instance, position: Vector3): MeshPart
	local instance = Instance.new("MeshPart")
	instance.Name = name
	instance.Position = position
	instance.Parent = parent
	return instance
end

local function gui(name: string, parent: Instance): ScreenGui
	local instance = Instance.new("ScreenGui")
	instance.Name = name
	instance.Parent = parent
	return instance
end

afterEach(function()
	for _, fixture in fixtures do
		fixture:Destroy()
	end
	table.clear(fixtures)
end)

describe("LoadingAssets", function()
	it("waits for the owned Spawn and HUD even when Runtime arrives after the character", function()
		local world = folder("World", nil)
		local playerGui = folder("PlayerGui", world)
		local character = model("Character", world)
		mesh("HumanoidRootPart", character, Vector3.zero)
		expect(Assets.IsReady(Assets.Resolve(world, playerGui, character, 42))).toBe(false)
		local runtime = folder("Runtime", world)
		expect(Assets.IsReady(Assets.Resolve(world, playerGui, character, 42))).toBe(false)
		local bases = folder("Bases", runtime)
		local otherBase = model("99", bases)
		mesh("Spawn", otherBase, Vector3.zero)
		expect(Assets.IsReady(Assets.Resolve(world, playerGui, character, 42))).toBe(false)
		local base = model("42", bases)
		local invalidSpawn = folder("Spawn", base)
		gui("HUDGui", playerGui)
		expect(Assets.IsReady(Assets.Resolve(world, playerGui, character, 42))).toBe(false)
		invalidSpawn:Destroy()
		mesh("Spawn", base, Vector3.zero)
		expect(Assets.IsReady(Assets.Resolve(world, playerGui, character, 42))).toBe(true)
	end)

	it("streams the actual character position and falls back only to the owned Spawn", function()
		local world = folder("World", nil)
		local playerGui = folder("PlayerGui", world)
		local character = model("Character", world)
		local root = mesh("HumanoidRootPart", character, Vector3.new(500, 12, -200))
		local bases = folder("Bases", folder("Runtime", world))
		local base = model("42", bases)
		local spawn = mesh("Spawn", base, Vector3.new(-900, 20, 0))
		expect(Assets.GetStreamPosition(Assets.Resolve(world, playerGui, character, 42))).toBe(
			root.Position
		)
		expect(Assets.GetStreamPosition(Assets.Resolve(world, playerGui, nil, 42))).toBe(
			spawn.Position
		)
		base:Destroy()
		expect(Assets.GetStreamPosition(Assets.Resolve(world, playerGui, nil, 42))).toBeNil()
	end)

	it(
		"selects visible startup assets without menus, catalogues or distant players' content",
		function()
			local world = folder("World", nil)
			local playerGui = folder("PlayerGui", world)
			local loadingGui = gui("LoadingScreen", playerGui)
			local hud = gui("HUDGui", playerGui)
			local icon = Instance.new("ImageLabel")
			icon.Parent = hud
			local hidden = Instance.new("Frame")
			hidden.Visible = false
			hidden.Parent = hud
			local hiddenIcon = Instance.new("ImageLabel")
			hiddenIcon.Parent = hidden
			local menu = gui("InventoryGui", playerGui)
			local menuIcon = Instance.new("ImageLabel")
			menuIcon.Parent = menu
			local character = model("Character", world)
			mesh("HumanoidRootPart", character, Vector3.new(1000, 0, 0))
			local shirt = Instance.new("Shirt")
			shirt.Parent = character
			local catalogue =
				mesh("Preview", folder("ReplicatedStorage", world), Vector3.new(1000, 0, 0))
			local bases = folder("Bases", folder("Runtime", world))
			local ownBase = model("42", bases)
			mesh("Spawn", ownBase, Vector3.new(1000, 0, 0))
			local ownDecoration = mesh("Temple", ownBase, Vector3.new(1010, 0, 0))
			local otherDecoration = mesh("Temple", model("99", bases), Vector3.new(1010, 0, 0))
			local map = folder("Map", world)
			local coreDecoration = mesh("Cap", model("FloatingIsland", map), Vector3.zero)
			local islands = folder("BaseIslands", map)
			local nearbyIsland = model("BaseIsland0", islands)
			mesh("Grass", nearbyIsland, Vector3.new(1000, 0, 0))
			local nearbyRock = mesh("Rock", nearbyIsland, Vector3.new(1030, -10, 0))
			local remoteIsland = model("BaseIsland1", islands)
			mesh("Grass", remoteIsland, Vector3.new(-1000, 0, 0))
			local remoteRock = mesh("Rock", remoteIsland, Vector3.new(-1000, -10, 0))
			local snapshot = Assets.Resolve(world, playerGui, character, 42)
			local selected = Assets.Collect(world, playerGui, loadingGui, snapshot)
			for _, expected in { icon, shirt, ownDecoration, nearbyRock } do
				expect(table.find(selected, expected) ~= nil).toBe(true)
			end
			for _, excluded in
				{
					hiddenIcon,
					menuIcon,
					catalogue,
					otherDecoration,
					coreDecoration,
					remoteRock,
				}
			do
				expect(table.find(selected, excluded)).toBeNil()
			end
		end
	)

	it("selects nearby surfaces using geometry bounds instead of distant model pivots", function()
		local world = folder("World", nil)
		local playerGui = folder("PlayerGui", world)
		local loadingGui = gui("LoadingScreen", playerGui)
		local character = model("Character", world)
		mesh("HumanoidRootPart", character, Vector3.zero)
		local map = folder("Map", world)
		local island = model("BaseIsland0", folder("BaseIslands", map))
		island.WorldPivot = CFrame.new(3000, 0, 0)
		local grass = mesh("Grass", island, Vector3.new(150, 0, 0))
		grass.Size = Vector3.new(200, 2, 200)
		local nearbyRock = mesh("Rock", island, Vector3.new(75, 0, 0))
		local distantRock = mesh("Rock", island, Vector3.new(500, 0, 0))
		local snapshot = Assets.Resolve(world, playerGui, character, 42)
		local selected = Assets.Collect(world, playerGui, loadingGui, snapshot)
		expect(table.find(selected, grass) ~= nil).toBe(true)
		expect(table.find(selected, nearbyRock) ~= nil).toBe(true)
		expect(table.find(selected, distantRock)).toBeNil()
	end)
end)
