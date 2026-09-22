--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory/Materials

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Ui = script.Parent.Parent.Parent
local CardList = require(Ui.Components.CardList)
local Panel = require(Ui.Components.Panel)
local Theme = require(Ui.Theme)
local MaterialsMeta = require(ReplicatedStorage.Shared.Configurations.Materials)

local function titleCase(value: string): string
	return (value:gsub("^%l", string.upper))
end

local function setRingHighlight(card: GuiButton, selected: boolean)
	local rarity = card:GetAttribute("Rarity")
	local ringColor = card:GetAttribute("RingColor")
	Panel.SetCellRing(
		card,
		if type(rarity) == "string" then rarity else nil,
		selected,
		if typeof(ringColor) == "Color3" then ringColor else nil
	)
end

local Materials = {}

export type Config = {
	template: GuiButton,
	parent: Instance,
	details: Panel.Details,
	onSelected: (Panel.Details) -> (),
}

function Materials.Create(config: Config): CardList.List<SharedTypes.MaterialEntry>
	return CardList.new({
		template = config.template,
		parent = config.parent,
		setHighlight = setRingHighlight,
		filter = function(id)
			return MaterialsMeta[id] ~= nil
		end,
		decorate = function(card: GuiButton, id: string, entry: SharedTypes.MaterialEntry)
			local metadata = MaterialsMeta[id];
			(card:WaitForChild("2dPreview") :: ImageLabel).Image = metadata.thumbnail;
			(card:WaitForChild("QuantityLabel") :: TextLabel).Text = `x{entry.total}`
			-- Materials have no rarity, so the ring carries their gui colour instead. Read back
			-- by setRingHighlight, which only receives the card.
			card:SetAttribute("RingColor", Color3.fromHex(metadata.guiColor))
			Panel.SetCellRing(card, nil, false, Color3.fromHex(metadata.guiColor))
		end,
		onSelect = function(id: string, entry: SharedTypes.MaterialEntry)
			config.onSelected(config.details)
			local metadata = MaterialsMeta[id]
			local tint = Color3.fromHex(metadata.guiColor)

			config.details.NameLabel.Text = metadata.displayName
			config.details.Art.Image = metadata.thumbnail
			config.details.ElementIcon.BackgroundColor3 = tint
			config.details.ElementIcon.Image = metadata.thumbnail
			config.details.RarityLabel.Text = titleCase(metadata.category)
			config.details.RarityLabel.TextColor3 = tint
			Theme.Ring(config.details.Hero, tint, 3)

			config.details.Stats[1].Value.Text = tostring(entry.total)
			config.details.Stats[1].Label.Text = "Owned"
			config.details.Stats[2].Value.Text = titleCase(metadata.category)
			config.details.Stats[2].Label.Text = "Category"
		end,
	})
end

return Materials
