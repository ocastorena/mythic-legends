--!strict
-- ServerStorage/Tests/__tests__/RemoteUtil.spec

local JestGlobals = require(script.Parent.Parent.DevPackages.JestGlobals)
local RemoteUtil = require(game:GetService("ServerScriptService").Infrastructure.RemoteUtil)

local describe, expect, it, afterEach =
	JestGlobals.describe, JestGlobals.expect, JestGlobals.it, JestGlobals.afterEach
local roots: { Folder } = {}
local DECLARATIONS: { [string]: { [string]: string } } = {
	Admin = { Feedback = "RemoteEvent" },
	State = { Update = "RemoteEvent", Request = "RemoteFunction" },
	Inventory = {
		DeleteMythling = "RemoteFunction",
		EvolveMythling = "RemoteFunction",
		SellMythling = "RemoteFunction",
		SellEquipment = "RemoteFunction",
		SellMaterial = "RemoteFunction",
		DiscardMaterial = "RemoteFunction",
		UpgradeCapacity = "RemoteFunction",
	},
	Shop = { GetShop = "RemoteFunction", BuyOffer = "RemoteFunction" },
	Crafting = {
		GetStation = "RemoteFunction",
		StartJob = "RemoteFunction",
		CancelJob = "RemoteFunction",
	},
	Production = { GetStatus = "RemoteFunction", Collect = "RemoteFunction" },
	Base = {
		PlaceMythling = "RemoteFunction",
		RemoveMythling = "RemoteFunction",
		GetBase = "RemoteFunction",
		BuildShrine = "RemoteFunction",
		ExpandBase = "RemoteFunction",
	},
	Combat = {
		StartAttack = "RemoteEvent",
		ReportHit = "RemoteEvent",
		SetShieldGuard = "RemoteEvent",
		Reaction = "RemoteEvent",
		Impact = "RemoteEvent",
		GetLoadout = "RemoteFunction",
		Equip = "RemoteFunction",
		EquipEquipment = "RemoteFunction",
		UnequipEquipment = "RemoteFunction",
	},
	World = { Spawned = "RemoteEvent", ClaimState = "RemoteEvent" },
}

local function fixture(wrongName: string?, wrongClass: string?)
	-- Resolve only uses Instance child lookup; no production network is created or modified.
	local root = Instance.new("Folder")
	table.insert(roots, root)
	local network = Instance.new("Folder")
	network.Name = "Network"
	network.Parent = root
	for domain, declarations in DECLARATIONS do
		local folder = Instance.new("Folder")
		folder.Name = domain
		folder.Parent = network
		for name, class in declarations do
			local remote = Instance.new(if name == wrongName then wrongClass or class else class)
			remote.Name = name
			remote.Parent = folder
		end
	end
	return root, network
end

afterEach(function()
	for _, root in roots do
		root:Destroy()
	end
	table.clear(roots)
end)

describe("RemoteUtil", function()
	it(
		"resolves the declared feature endpoints and preserves all existing domain identities",
		function()
			local root, network = fixture()
			local before = #network:GetDescendants()
			local resolved = RemoteUtil.Resolve((root :: unknown) :: ReplicatedStorage)
			local domains = (resolved :: unknown) :: { [string]: { [string]: Instance } }
			for domain, declarations in DECLARATIONS do
				local folder = assert(network:FindFirstChild(domain))
				for name, class in declarations do
					local remote = domains[domain][name]
					expect(remote).toBe(folder:FindFirstChild(name))
					expect(remote.ClassName).toBe(class)
				end
			end
			expect(#network:GetDescendants()).toBe(before)
		end
	)

	it("rejects wrongly typed feature endpoints without replacing or creating instances", function()
		for _, name in
			{
				"GetShop",
				"BuyOffer",
				"GetStation",
				"StartJob",
				"CancelJob",
				"GetBase",
				"BuildShrine",
				"ExpandBase",
				"DeleteMythling",
				"EvolveMythling",
				"SellMythling",
				"SellEquipment",
				"SellMaterial",
				"DiscardMaterial",
				"UpgradeCapacity",
				"EquipEquipment",
				"UnequipEquipment",
			}
		do
			local root, network = fixture(name, "RemoteEvent")
			local domain = if name == "GetShop" or name == "BuyOffer"
				then "Shop"
				elseif
					name == "GetStation"
					or name == "StartJob"
					or name == "CancelJob"
				then "Crafting"
				elseif
					name == "GetBase"
					or name == "BuildShrine"
					or name == "ExpandBase"
				then "Base"
				elseif name == "EquipEquipment" or name == "UnequipEquipment" then "Combat"
				else "Inventory"
			local folder = assert(network:FindFirstChild(domain))
			local original = folder:FindFirstChild(name)
			local before = #network:GetDescendants()
			expect(function()
				RemoteUtil.Resolve((root :: unknown) :: ReplicatedStorage)
			end).toThrow()
			expect(folder:FindFirstChild(name)).toBe(original)
			expect(#network:GetDescendants()).toBe(before)
		end
	end)
end)
