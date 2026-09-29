--!strict
-- ReplicatedStorage/Shared/Configurations/Materials

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)
local Types = require(script.Parent.Parent.Types)
local Inventory = require(script.Parent.Inventory)

-- IDs are stable; these neutral display names and empty thumbnails await final presentation.
-- Prices are per whole Material. Future launch offers must select launchEnabled definitions only.
local Materials: { [string]: Types.MaterialDef } = {
	fire_material = {
		displayName = "Fire Material",
		category = "material",
		guiColor = "FFFFFF",
		thumbnail = "",
		description = "Normal Fire Material produced by a Fire Shrine.",
		launchEnabled = true,
		element = "Fire",
		stackLimit = Inventory.materialStackLimit,
		buyGold = 10,
		sellGold = 2,
	},
	water_material = {
		displayName = "Water Material",
		category = "material",
		guiColor = "FFFFFF",
		thumbnail = "",
		description = "Normal Water Material produced by a Water Shrine.",
		launchEnabled = true,
		element = "Water",
		stackLimit = Inventory.materialStackLimit,
		buyGold = 10,
		sellGold = 2,
	},
	earth_material = {
		displayName = "Earth Material",
		category = "material",
		guiColor = "FFFFFF",
		thumbnail = "",
		description = "Normal Earth Material produced by an Earth Shrine.",
		launchEnabled = true,
		element = "Earth",
		stackLimit = Inventory.materialStackLimit,
		buyGold = 10,
		sellGold = 2,
	},
	air_material = {
		displayName = "Air Material",
		category = "material",
		guiColor = "FFFFFF",
		thumbnail = "",
		description = "Normal Air Material produced by an Air Shrine.",
		launchEnabled = true,
		element = "Air",
		stackLimit = Inventory.materialStackLimit,
		buyGold = 10,
		sellGold = 2,
	},
	light_material = {
		displayName = "Light Material",
		category = "material",
		guiColor = "FFFFFF",
		thumbnail = "",
		description = "Normal Light Material produced by a Light Shrine.",
		launchEnabled = true,
		element = "Light",
		stackLimit = Inventory.materialStackLimit,
		buyGold = 10,
		sellGold = 2,
	},
	dark_material = {
		displayName = "Dark Material",
		category = "material",
		guiColor = "FFFFFF",
		thumbnail = "",
		description = "Normal Dark Material produced by a Dark Shrine.",
		launchEnabled = true,
		element = "Dark",
		stackLimit = Inventory.materialStackLimit,
		buyGold = 10,
		sellGold = 2,
	},
	-- Retained prototype identities are not aliases for elemental Materials. The existing
	-- prototype production path still resolves them until its separate replacement increment.
	essence = {
		launchEnabled = false,
		displayName = "Essence",
		category = "material",
		guiColor = "39C0FF",
		thumbnail = "rbxassetid://102449498933091",
		description = "A rare alchemical concentrate produced only by the Aqualotl Mythlings. When these gentle creatures meditate within pure water, their bodies release a shimmering golden residue infused with life energy. Though it appears simple, Essence carries traces of ancient aquatic magic — said to be the same energy used by the First Mages to shape early Mythlings from the waters of creation.",
	},
	crystal = {
		launchEnabled = false,
		displayName = "Crystal",
		category = "material",
		guiColor = "9B6BFF",
		thumbnail = "rbxassetid://97907732163601",
		description = "Crystals are shed from the armored hide of the Crystal Dragon, a Mythling whose body naturally forms magical mineral plating. As these dragons grow, the crystalline plates along their spine and tail periodically crack and regrow, leaving behind sharp, luminous fragments infused with dormant draconic energy.",
	},
	shadow_dust = {
		launchEnabled = false,
		displayName = "Shadow Dust",
		category = "material",
		guiColor = "7A7F94",
		thumbnail = "rbxassetid://103923910263404",
		description = "An eerie residue shed by Shadow Satyrs when they move between light and darkness. These elusive Mythlings exist partially out of phase with reality, leaving behind a fine, obsidian-like powder wherever their bodies slip through shadow. The dust absorbs light naturally, and when stirred, it behaves almost like liquid night.",
	},
}

return FreezeUtil.DeepFreeze(Materials)
