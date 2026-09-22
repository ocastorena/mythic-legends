--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory/Consumables

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Ui = script.Parent.Parent.Parent
local CardList = require(Ui.Components.CardList)
local Panel = require(Ui.Components.Panel)
local Theme = require(Ui.Theme)
local ConsumablesMeta = require(ReplicatedStorage.Shared.Configurations.Consumables)

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

local Consumables = {}

local function getConsumableMetadata(consumableId: string): SharedTypes.ConsumableDef?
	local direct = ConsumablesMeta[consumableId]
	if direct then
		return direct
	end
	for metadataId, metadata in pairs(ConsumablesMeta) do
		if string.lower(metadataId) == string.lower(consumableId) then
			return metadata
		end
	end
	return nil
end

export type Config = {
	template: GuiButton,
	parent: Instance,
	details: Panel.Details,
	onSelected: (Panel.Details) -> (),
}

function Consumables.Create(config: Config): CardList.List<SharedTypes.ConsumableEntry>
	return CardList.new({
		template = config.template,
		parent = config.parent,
		setHighlight = setRingHighlight,
		filter = function(id: string, entry: SharedTypes.ConsumableEntry)
			return getConsumableMetadata(entry.consumableId or id) ~= nil
		end,
		decorate = function(card: GuiButton, id: string, entry: SharedTypes.ConsumableEntry)
			local metadata = getConsumableMetadata(entry.consumableId or id)
			if not metadata then
				return
			end
			local rarity = metadata.rarity or "Common"
			(card:WaitForChild("2dPreview") :: ImageLabel).Image = metadata.thumbnail or ""
			(card:WaitForChild("QuantityLabel") :: TextLabel).Text =
				`x{entry.quantity or entry.total or 1}`
			card:SetAttribute("Rarity", rarity)
			Panel.SetCellRing(card, rarity, false)
		end,
		onSelect = function(id: string, entry: SharedTypes.ConsumableEntry)
			config.onSelected(config.details)
			local metadata = getConsumableMetadata(entry.consumableId or id)
			if not metadata then
				return
			end
			local rarity = metadata.rarity or "Common"
			local consumableType = metadata.category or "Consumable"
			config.details.NameLabel.Text = metadata.displayName
				or titleCase(entry.consumableId or id)
			config.details.Art.Image = metadata.thumbnail or ""
			config.details.ElementIcon.BackgroundColor3 = Theme.RarityColor(rarity)
			config.details.ElementIcon.Image = metadata.thumbnail or ""
			Panel.SetHeroRarity(config.details, rarity)
			config.details.Stats[1].Value.Text = tostring(entry.quantity or entry.total or 1)
			config.details.Stats[1].Label.Text = "Owned"
			config.details.Stats[2].Value.Text = consumableType
			config.details.Stats[2].Label.Text = "Type"
			config.details.Stats[3].Value.Text = metadata.value and `+{metadata.value}` or "—"
			config.details.Stats[3].Label.Text = metadata.effect or "Effect"
		end,
	})
end

Consumables.GetMetadata = getConsumableMetadata

return Consumables
