--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory/Mythlings

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Ui = script.Parent.Parent.Parent
local CardList = require(Ui.Components.CardList)
local Panel = require(Ui.Components.Panel)
local MythlingThumbnailUtil = require(Ui.MythlingThumbnailUtil)
local MythlingsData = require(ReplicatedStorage.Shared.Configurations.Mythlings)
local MaterialsMeta = require(ReplicatedStorage.Shared.Configurations.Materials)

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

local Mythlings = {}

export type Config = {
	template: GuiButton,
	parent: Instance,
	details: Panel.Details,
	onSelected: (Panel.Details) -> (),
}

function Mythlings.Create(config: Config): CardList.List<SharedTypes.MythlingEntry>
	return CardList.new({
		template = config.template,
		parent = config.parent,
		setHighlight = setRingHighlight,
		decorate = function(card: GuiButton, _id: string, entry: SharedTypes.MythlingEntry)
			local metadata = MythlingsData[entry.typeId]
			local variant = metadata.variants[entry.variantId]
			local preview = card:WaitForChild("2dPreview") :: ImageLabel
			MythlingThumbnailUtil.Render(preview, variant.thumbnail)
			-- Read back by setRingHighlight, which only receives the card.
			card:SetAttribute("Rarity", metadata.rarity)
			Panel.SetCellRing(card, metadata.rarity, false)

			-- The green check marks a Mythling already working a stand.
			local check = card:FindFirstChild("EquippedCheck")
			if check and check:IsA("GuiObject") then
				check.Visible = entry.standId ~= nil
			end
		end,
		onSelect = function(_id: string, entry: SharedTypes.MythlingEntry)
			config.onSelected(config.details)
			local metadata = MythlingsData[entry.typeId]
			local material = MaterialsMeta[metadata.production.materialId]
			local variant = metadata.variants[entry.variantId]

			config.details.NameLabel.Text = metadata.displayName
			MythlingThumbnailUtil.Render(config.details.Art, variant.thumbnail)
			Panel.SetHeroRarity(config.details, metadata.rarity)

			-- Current Mythling metadata does not yet expose elementId, so the produced Material's
			-- configured colour is the available identity colour for this view.
			config.details.ElementIcon.BackgroundColor3 = Color3.fromHex(material.guiColor)
			config.details.ElementIcon.Image = material.thumbnail

			config.details.Stats[1].Value.Text =
				string.format("%.2g/min", metadata.production.materialsPerMinute)
			config.details.Stats[1].Label.Text = material.displayName
			config.details.Stats[2].Value.Text = tostring(metadata.production.baseCapacity)
			config.details.Stats[2].Label.Text = "Max Storage"
			config.details.Stats[3].Value.Text = entry.standId and `#{entry.standId}` or "—"
			config.details.Stats[3].Label.Text = "Stationed At"
		end,
	})
end

return Mythlings
