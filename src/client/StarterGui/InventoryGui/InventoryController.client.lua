-- StarterGui/InventoryGui/InventoryController
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Identifies this panel to ModalUtil, which owns the backdrop and input guard.
local PANEL_NAME = "Inventory"

-- Modules
local Util = ReplicatedStorage:WaitForChild("Util")
local ButtonUtil = require(Util:WaitForChild("ButtonUtil"))
local CardListUtil = require(Util:WaitForChild("CardListUtil"))
local ModalUtil = require(Util:WaitForChild("ModalUtil"))
local MythlingsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))
local ResourcesMeta = require(ReplicatedStorage.Metadata.Resources)

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MythlingsEvent = Remotes.MythlingsEvent
local MythlingsRequest = Remotes.MythlingsRequest
local ResourcesEvent = Remotes.ResourcesEvent
local ResourcesRequest = Remotes.ResourcesRequest

-- Inventory GUI Components
local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local inventoryGui = playerGui.InventoryGui
local mainFrame = inventoryGui.Main
local bottomFrame = inventoryGui.Bottom
local closeButton = inventoryGui.Main.CloseButton

-- Confirm Delete Modal Components
local confirmModal = inventoryGui.ConfirmDeleteModal
local confirmTitle = confirmModal.Frame.TitleLabel
local confirmButton = confirmModal.Frame.ConfirmButton
local cancelButton = confirmModal.Frame.CancelButton

-- Mythlings Components
local mythlingsFrame = mainFrame.MythlingsFrame
local mythlingCardTemplate = mythlingsFrame.CardTemplate
local mythlingInfo = mainFrame.MythlingInfo
local mythlingsTab = mainFrame.Tabs.Mythlings

-- Resources Components
local resourcesFrame = mainFrame.ResourcesFrame
local resourcesCardTemplate = resourcesFrame.CardTemplate
local resourceInfo = mainFrame.ResourceInfo
local resourcesTab = mainFrame.Tabs.Resources

-- Colors
local selectCardColor = Color3.fromRGB(255, 251, 0)
local deselectCardColor = Color3.fromRGB(119, 121, 128)

-- State
local selectedTab = nil
local selectedFrame = nil
local selectedInfo = nil

local pendingDeleteId = nil
local mythlingButtonsConnected = false
local resourceButtonsConnected = false

--- Both grids highlight with a UIStroke; shared by the mythling and resource lists.
local function setStrokeHighlight(card, selected: boolean)
	card.UIStroke.Color = selected and selectCardColor or deselectCardColor
	card.UIStroke.Thickness = selected and 0.04 or 0.02
end

-- helper functions
local function closeConfirmDeleteModal()
	confirmModal.Visible = false
end

local function openConfirmDeleteModal(displayName)
	confirmTitle.Text = `Delete {displayName}?`
	confirmModal.Visible = true
end

-- Mythlings
local function clearMythlingInfo()
	mythlingInfo.NameLabel.Text = ""
	mythlingInfo.VariantLabel.Text = ""
	mythlingInfo.DescriptionLabel.Text = ""
end

local mythlingList = CardListUtil.new({
	template = mythlingCardTemplate,
	parent = mythlingsFrame,
	setHighlight = setStrokeHighlight,
	decorate = function(card, _id, entry)
		card:WaitForChild("2dPreview").Image = MythlingsData[entry.typeId].variants[entry.variantId].thumbnail
	end,
	onSelect = function(_id, entry)
		local metadata = MythlingsData[entry.typeId]
		mythlingInfo.NameLabel.Text = metadata.displayName
		mythlingInfo.VariantLabel.Text = metadata.rarity
		mythlingInfo.DescriptionLabel.Text = metadata.description
	end,
})

local resourceList = CardListUtil.new({
	template = resourcesCardTemplate,
	parent = resourcesFrame,
	setHighlight = setStrokeHighlight,
	decorate = function(card, id, entry)
		card:WaitForChild("2dPreview").Image = ResourcesMeta[id].thumbnail
		card.QuantityLabel.Text = `x{entry.total}`
	end,
	onSelect = function(id)
		resourceInfo.NameLabel.Text = ResourcesMeta[id].displayName
		resourceInfo.ScrollingFrame.DescriptionLabel.Text = ResourcesMeta[id].description
	end,
})

local function setMythlingButtons()
	bottomFrame.FirstButton.Text = "Delete"
	bottomFrame.FirstButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	bottomFrame.FirstButton.Visible = true

	if mythlingButtonsConnected then
		return
	end
	mythlingButtonsConnected = true

	ButtonUtil.hookClick(bottomFrame.FirstButton, function()
		local selectedId = mythlingList:GetSelectedId()
		if not selectedId then
			return
		end
		pendingDeleteId = selectedId
		openConfirmDeleteModal(mythlingInfo.NameLabel.Text)
	end)

	ButtonUtil.hookClick(confirmButton, function()
		if not pendingDeleteId then
			closeConfirmDeleteModal()
			return
		end

		clearMythlingInfo()
		mythlingList:Remove(pendingDeleteId)

		MythlingsEvent:FireServer("Delete", pendingDeleteId)

		pendingDeleteId = nil
		closeConfirmDeleteModal()
	end)

	ButtonUtil.hookClick(cancelButton, function()
		pendingDeleteId = nil
		closeConfirmDeleteModal()
	end)
end

------------- Resources Start -------------
local function setResourceButtons()
	bottomFrame.FirstButton.Text = "Delete"
	bottomFrame.FirstButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	bottomFrame.FirstButton.Visible = false

	if resourceButtonsConnected then
		return
	end
	resourceButtonsConnected = true

	-- Resources have no delete action yet; FirstButton stays hidden above.
end


------------- Resources End -------------

local function selectTab(tab)
	if selectedTab == tab then
		return
	end
	if selectedTab then
		selectedTab.ImageTransparency = 0.6
		selectedFrame.Visible = false
		selectedInfo.Visible = false
	end

	if tab == mythlingsTab then
		setMythlingButtons()
		tab.ImageTransparency = 0
		mythlingsFrame.Visible = true
		mythlingInfo.Visible = true
		selectedTab = tab
		selectedFrame = mythlingsFrame
		selectedInfo = mythlingInfo
	end

	if tab == resourcesTab then
		setResourceButtons()
		tab.ImageTransparency = 0
		resourcesFrame.Visible = true
		resourceInfo.Visible = true
		selectedTab = tab
		selectedFrame = resourcesFrame
		selectedInfo = resourceInfo
	end
end

MythlingsEvent.OnClientEvent:Connect(function(event, list)
	if event == "Update" then
		mythlingList:Replace(list)
	end
end)

ButtonUtil.hookClick(mythlingsTab, function()
	selectTab(mythlingsTab)
end)

ButtonUtil.hookClick(resourcesTab, function()
	selectTab(resourcesTab)
end)

ButtonUtil.hookClick(closeButton, function()
	inventoryGui.Enabled = false
end)

-- This ScreenGui's own Enabled property is the open/close contract. HudController owns the
-- button in MainGui that toggles it, so this controller no longer reaches across into
-- another GUI, and anything else that wants the inventory open just sets this flag.
inventoryGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if inventoryGui.Enabled then
		mythlingList:Replace(MythlingsRequest:InvokeServer("GetMythlings"))
		resourceList:Replace(ResourcesRequest:InvokeServer("GetResources"))
		selectTab(mythlingsTab)
		ModalUtil.Open(PANEL_NAME)
	else
		ModalUtil.Close(PANEL_NAME)
	end
end)
