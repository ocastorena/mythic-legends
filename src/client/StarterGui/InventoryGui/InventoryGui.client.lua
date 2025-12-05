-- StarterGui/InventoryGui/InventoryGui.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- Modules
local InputGuard = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("GuiInputGuard"))
local ButtonSetup = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("ButtonSetup"))
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
local backgroundGui = playerGui.Background
local inventoryGui = playerGui.InventoryGui
local inventoryBtn = playerGui.MainGui.MainFrame.OpenButton
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

local mythlingCards = {}
local mythlingCardsData = {}
local selectedMythlingCard = nil
local pendingDeleteId = nil
local pendingDeleteCard = nil
local mythlingButtonsConnected = false

local resourceCards = {}
local resourceCardsData = {}
local selectedResourceCard = nil
local resourceButtonsConnected = false

-- helper functions
local function closeConfirmDeleteModal()
	confirmModal.Visible = false
end

local function openConfirmDeleteModal(displayName)
	confirmTitle.Text = `Delete {displayName}?`
	confirmModal.Visible = true
end

-- Mythlings
local function clearMythlingCards()
	for _, card in pairs(mythlingCards) do
		card:Destroy()
	end
	table.clear(mythlingCards)
end

local function clearMythlingInfo()
	mythlingInfo.NameLabel.Text = ""
	mythlingInfo.VariantLabel.Text = ""
	mythlingInfo.DescriptionLabel.Text = ""
end

local function clearSelectedMythlingCard()
	if selectedMythlingCard then
		selectedMythlingCard.UIStroke.Color = deselectCardColor
		selectedMythlingCard.UIStroke.Thickness = 0.02
		selectedMythlingCard = nil
	end
end

local function setMythlingButtons()
	bottomFrame.FirstButton.Text = "Delete"
	bottomFrame.FirstButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	bottomFrame.FirstButton.Visible = true

	if mythlingButtonsConnected then
		return
	end
	mythlingButtonsConnected = true

	ButtonSetup.hookClick(bottomFrame.FirstButton, function()
		if not selectedMythlingCard then
			return
		end
		pendingDeleteId = selectedMythlingCard.Name
		pendingDeleteCard = selectedMythlingCard
		openConfirmDeleteModal(mythlingInfo.NameLabel.Text)
	end)

	ButtonSetup.hookClick(confirmButton, function()
		if not pendingDeleteId then
			closeConfirmDeleteModal()
			return
		end

		clearMythlingInfo()
		clearSelectedMythlingCard()

		local card = pendingDeleteCard or mythlingCards[pendingDeleteId]
		if card then
			card:Destroy()
		end
		mythlingCards[pendingDeleteId] = nil
		mythlingCardsData[pendingDeleteId] = nil
		selectedMythlingCard = nil

		MythlingsEvent:FireServer("Delete", pendingDeleteId)

		pendingDeleteId = nil
		pendingDeleteCard = nil
		closeConfirmDeleteModal()
	end)

	ButtonSetup.hookClick(cancelButton, function()
		pendingDeleteId = nil
		pendingDeleteCard = nil
		closeConfirmDeleteModal()
	end)
end

local function selectMythlingCard(card)
	if selectedMythlingCard == card then
		return
	end
	clearSelectedMythlingCard()
	card.UIStroke.Color = selectCardColor
	card.UIStroke.Thickness = 0.04
	selectedMythlingCard = card
end

local function showMythlingInfo()
	if not selectedMythlingCard then
		return
	end
	local mythlingMetadata = MythlingsData[mythlingCardsData[selectedMythlingCard.Name].typeId]
	mythlingInfo.NameLabel.Text = mythlingMetadata.displayName
	mythlingInfo.VariantLabel.Text = mythlingMetadata.rarity
	mythlingInfo.DescriptionLabel.Text = mythlingMetadata.description
end

local function createMythlingCard(mythlingId, mythlingEntry)
	local newCard = mythlingCardTemplate:Clone()
	newCard.Name = mythlingId
	newCard.Parent = mythlingsFrame
	newCard.Visible = true
	newCard.LayoutOrder = 1
	newCard:WaitForChild("2dPreview").Image =
		MythlingsData[mythlingEntry.typeId].variants[mythlingEntry.variantId].thumbnail
	ButtonSetup.hookClick(newCard, function()
		selectMythlingCard(newCard)
		showMythlingInfo()
	end)
	return newCard
end

local function addMythlingCard(mythlingId, mythlingEntry)
	if mythlingCards[mythlingId] then
		return
	end
	local newCard = createMythlingCard(mythlingId, mythlingEntry)
	mythlingCards[mythlingId] = newCard
	mythlingCardsData[mythlingId] = mythlingEntry
	if not selectedMythlingCard then
		selectMythlingCard(newCard)
		showMythlingInfo()
	end
end

local function addMythlingsCards(list)
	clearMythlingCards()
	for mythlingId, mythlingEntry in pairs(list) do
		addMythlingCard(mythlingId, mythlingEntry)
	end
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

	-- ButtonSetup.hookClick(bottomFrame.FirstButton, function()
	-- 	if not selectedResourceCard then
	-- 		return
	-- 	end
	-- 	pendingDeleteId = selectedResourceCard.Name
	-- 	pendingDeleteCard = selectedResourceCard
	-- 	openConfirmDeleteModal(mythlingInfo.NameLabel.Text)
	-- end)

	-- ButtonSetup.hookClick(confirmButton, function()
	-- 	if not pendingDeleteId then
	-- 		closeConfirmDeleteModal()
	-- 		return
	-- 	end

	-- 	clearMythlingInfo()
	-- 	clearSelectedMythlingCard()

	-- 	local card = pendingDeleteCard or mythlingCards[pendingDeleteId]
	-- 	if card then
	-- 		card:Destroy()
	-- 	end
	-- 	mythlingCards[pendingDeleteId] = nil
	-- 	mythlingCardsData[pendingDeleteId] = nil
	-- 	selectedMythlingCard = nil

	-- 	MythlingsEvent:FireServer("Delete", pendingDeleteId)

	-- 	pendingDeleteId = nil
	-- 	pendingDeleteCard = nil
	-- 	closeConfirmDeleteModal()
	-- end)

	-- ButtonSetup.hookClick(cancelButton, function()
	-- 	pendingDeleteId = nil
	-- 	pendingDeleteCard = nil
	-- 	closeConfirmDeleteModal()
	-- end)
end

local function clearResourceCards()
	for _, card in pairs(resourceCards) do
		card:Destroy()
	end
	table.clear(resourceCards)
end

local function clearSelectedResourceCard()
	if selectedResourceCard then
		selectedResourceCard.UIStroke.Color = deselectCardColor
		selectedResourceCard.UIStroke.Thickness = 0.02
		selectedResourceCard = nil
	end
end

local function selectResourceCard(card)
	if selectedResourceCard == card then
		return
	end
	clearSelectedResourceCard()
	card.UIStroke.Color = selectCardColor
	card.UIStroke.Thickness = 0.04
	selectedResourceCard = card
end

local function showResourceInfo()
	if not selectedResourceCard then
		return
	end

	resourceInfo.NameLabel.Text = ResourcesMeta[selectedResourceCard.Name].displayName
	resourceInfo.ScrollingFrame.DescriptionLabel.Text = ResourcesMeta[selectedResourceCard.Name].description
end

local function createResourceCard(resourceId, resourceEntry)
	local newCard = resourcesCardTemplate:Clone()
	newCard.Name = resourceId
	newCard.Parent = resourcesFrame
	newCard.Visible = true
	newCard.LayoutOrder = 1
	newCard:WaitForChild("2dPreview").Image = ResourcesMeta[resourceId].thumbnail
	newCard.QuantityLabel.Text = `x{resourceEntry.total}`
	ButtonSetup.hookClick(newCard, function()
		selectResourceCard(newCard)
		showResourceInfo()
	end)
	return newCard
end

local function addResourceCard(resourceId, resourceEntry)
	if resourceCards[resourceId] then
		return
	end
	local newCard = createResourceCard(resourceId, resourceEntry)
	resourceCards[resourceId] = newCard
	resourceCardsData[resourceId] = resourceEntry
	if not selectedResourceCard then
		selectResourceCard(newCard)
		showResourceInfo()
	end
end

local function addResourcesCards(list)
	clearResourceCards()
	for resourceId, resourceEntry in pairs(list) do
		addResourceCard(resourceId, resourceEntry)
	end
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
		addMythlingsCards(list)
	end
end)

ButtonSetup.hookClick(mythlingsTab, function()
	selectTab(mythlingsTab)
end)

ButtonSetup.hookClick(resourcesTab, function()
	selectTab(resourcesTab)
end)

ButtonSetup.hookClick(inventoryBtn, function()
	if not inventoryGui.Enabled then
		backgroundGui.Enabled = true
		selectedMythlingCard = nil
		selectedResourceCard = nil
		addMythlingsCards(MythlingsRequest:InvokeServer("GetMythlings"))
		addResourcesCards(ResourcesRequest:InvokeServer("GetResources"))
		selectTab(mythlingsTab)
		inventoryGui.Enabled = true
	else
		inventoryGui.Enabled = false
		backgroundGui.Enabled = false
	end
end)

ButtonSetup.hookClick(closeButton, function()
	if inventoryGui.Enabled then
		backgroundGui.Enabled = false
		inventoryGui.Enabled = false
	end
end)

backgroundGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if backgroundGui.Enabled then
		-- ScreenGui just got enabled → block inputs
		InputGuard.open()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	else
		-- ScreenGui just got disabled → allow inputs
		InputGuard.close()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end
end)
