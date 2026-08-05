--!strict
-- ServerStorage/Tests/__tests__/StandPlacement.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local StandPlacement = require(game:GetService("ServerScriptService").Services.BaseService.StandPlacement)

local afterEach = JestGlobals.afterEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local it = JestGlobals.it

local fixtureAssets: Folder? = nil
local fixtureBase: Model? = nil

local function createFixture(): (Folder, Model, BasePart)
	local assets = Instance.new("Folder")
	local asset = Instance.new("Model")
	asset.Name = "TestMythling"
	asset.Parent = assets

	local mesh = Instance.new("MeshPart")
	mesh.Name = "Body"
	mesh.Parent = asset
	asset.PrimaryPart = mesh

	local variants = Instance.new("Folder")
	variants.Name = "Variants"
	variants.Parent = asset
	local surface = Instance.new("SurfaceAppearance")
	surface.Name = "regular"
	surface.Parent = variants

	local base = Instance.new("Model")
	local stands = Instance.new("Folder")
	stands.Name = "Stands"
	stands.Parent = base
	local stand = Instance.new("Part")
	stand.Name = "Stand"
	stand:SetAttribute("Id", 0)
	stand.Parent = stands

	fixtureAssets = assets
	fixtureBase = base
	return assets, base, stand
end

afterEach(function()
	if fixtureAssets then
		fixtureAssets:Destroy()
		fixtureAssets = nil
	end
	if fixtureBase then
		fixtureBase:Destroy()
		fixtureBase = nil
	end
end)

describe("StandPlacement", function()
	it("places only after validating the target and rejects an occupied stand", function()
		local assets, base, stand = createFixture()
		local metadata = { variants = { regular = { model = "TestMythling" } } }
		local entry: any = { variantId = "regular" }

		local placed, placementError = StandPlacement.SetMythlingOnStand(entry, base, 0, assets, metadata)
		expect(placed).toBe(true)
		expect(placementError).toBeNil()
		expect(entry.standId).toBe(0)
		expect(stand:FindFirstChildWhichIsA("Model") ~= nil).toBe(true)

		local occupiedEntry: any = { variantId = "regular" }
		local occupied = StandPlacement.SetMythlingOnStand(occupiedEntry, base, 0, assets, metadata)
		expect(occupied).toBe(false)
		expect(occupiedEntry.standId).toBeNil()
	end)

	it("does not mutate saved placement when its configured asset is missing", function()
		local assets, base = createFixture()
		local metadata = { variants = { regular = { model = "MissingModel" } } }
		local entry: any = { variantId = "regular" }

		local placed = StandPlacement.SetMythlingOnStand(entry, base, 0, assets, metadata)
		expect(placed).toBe(false)
		expect(entry.standId).toBeNil()
	end)

	it("clears saved placement after removing the visual model", function()
		local assets, base, stand = createFixture()
		local metadata = { variants = { regular = { model = "TestMythling" } } }
		local entry: any = { variantId = "regular" }

		local placed = StandPlacement.SetMythlingOnStand(entry, base, 0, assets, metadata)
		expect(placed).toBe(true)

		local removed, removeError = StandPlacement.RemoveMythlingFromStand(entry, base)
		expect(removed).toBe(true)
		expect(removeError).toBeNil()
		expect(entry.standId).toBeNil()
		expect(stand:FindFirstChildWhichIsA("Model") == nil).toBe(true)
	end)
end)
