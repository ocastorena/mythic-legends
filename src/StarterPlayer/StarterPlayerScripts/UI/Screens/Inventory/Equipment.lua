--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Inventory/Equipment

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local ClientTypes = require(script.Parent.Parent.Parent.Parent.Types)
local Ui = script.Parent.Parent.Parent
local CardList = require(Ui.Components.CardList)
local Panel = require(Ui.Components.Panel)
local Theme = require(Ui.Theme)
local EquipmentPreviewUtil = require(Ui.EquipmentPreviewUtil)
local EquipmentMeta = require(ReplicatedStorage.Shared.Configurations.Equipment)

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

local Equipment = {}

local function equipmentThumbnail(
	profile: SharedTypes.EquipmentProfile,
	entry: ClientTypes.InventoryEquipmentEntry
): string
	if profile.thumbnail and profile.thumbnail ~= "" then
		return profile.thumbnail
	end
	return entry.textureId or ""
end

local function setEquipmentPreview(
	imageLabel: ImageLabel,
	profile: SharedTypes.EquipmentProfile,
	entry: ClientTypes.InventoryEquipmentEntry
)
	local thumbnail = equipmentThumbnail(profile, entry)
	EquipmentPreviewUtil.Clear(imageLabel)
	imageLabel.Image = thumbnail
	if thumbnail == "" then
		EquipmentPreviewUtil.Render(imageLabel, entry.previewModel)
	end
end

export type Config = {
	template: GuiButton,
	parent: Instance,
	details: Panel.Details,
	onSelected: (Panel.Details) -> (),
}

function Equipment.Create(config: Config): CardList.List<ClientTypes.InventoryEquipmentEntry>
	return CardList.new({
		template = config.template,
		parent = config.parent,
		setHighlight = setRingHighlight,
		decorate = function(
			card: GuiButton,
			id: string,
			entry: ClientTypes.InventoryEquipmentEntry
		)
			local profile = EquipmentMeta.profiles[id]
			setEquipmentPreview(card:WaitForChild("2dPreview") :: ImageLabel, profile, entry)
			local quantityLabel = card:WaitForChild("QuantityLabel") :: TextLabel
			quantityLabel.Text = if entry.quantity > 1 then `x{entry.quantity}` else ""
			card:SetAttribute("Rarity", profile.rarity or "Common")
			Panel.SetCellRing(card, profile.rarity or "Common", false)
			local equippedCheck = card:WaitForChild("EquippedCheck") :: GuiObject
			equippedCheck.Visible = entry.equipped
		end,
		onSelect = function(id: string, entry: ClientTypes.InventoryEquipmentEntry)
			config.onSelected(config.details)
			local profile = EquipmentMeta.profiles[id]
			local rarity = profile.rarity or "Common"
			config.details.NameLabel.Text = profile.displayName or titleCase(id)
			setEquipmentPreview(config.details.Art, profile, entry)
			config.details.ElementIcon.BackgroundColor3 = Theme.RarityColor(rarity)
			setEquipmentPreview(config.details.ElementIcon, profile, entry)
			Panel.SetHeroRarity(config.details, rarity)
			if config.details.PrimaryButton then
				config.details.PrimaryButton.Text = if entry.equipped then "Unequip" else "Equip"
				Panel.SetButtonEnabled(
					config.details.PrimaryButton,
					not entry.equipped,
					Theme.tabIcon.equipment
				)
			end

			if profile.kind == "Shield" then
				config.details.Stats[1].Value.Text =
					string.format("%.2fs", profile.activationCooldownSeconds or 0)
				config.details.Stats[1].Label.Text = "Raise Cooldown"
				config.details.Stats[2].Value.Text =
					string.format("%.0f°", profile.blockArcDegrees or 0)
				config.details.Stats[2].Label.Text = "Block Arc"
				config.details.Stats[3].Value.Text = tostring(profile.slideKnockback or 0)
				config.details.Stats[3].Label.Text = "Block Slide"
			elseif profile.kind == "PrimaryWeapon" then
				config.details.Stats[1].Value.Text =
					string.format("%.2fs", profile.cooldownSeconds or 0)
				config.details.Stats[1].Label.Text = "Swing Cooldown"
				config.details.Stats[2].Value.Text = string.format("%.2f", profile.reachStuds or 0)
				config.details.Stats[2].Label.Text = "Reach (studs)"
				config.details.Stats[3].Value.Text = tostring(profile.planarKnockback or 0)
				config.details.Stats[3].Label.Text = "Knockback"
			else
				for _, stat in ipairs(config.details.Stats) do
					stat.Value.Text = "—"
					stat.Label.Text = ""
				end
			end
		end,
	})
end

Equipment.Thumbnail = equipmentThumbnail

return Equipment
