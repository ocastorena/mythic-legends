-- StarterGui/InventoryGui/InventoryGui.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- Modules
local InputGuard = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("GuiInputGuard"))
local MythlingsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryEvent = Remotes.InventoryEvent
local baseEvent = Remotes.BaseEvent
local InventoryRequest = Remotes.InventoryRequest

-- Inventory GUI Components
local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local backgroundGui = playerGui.Background
local inventoryGui = playerGui.InventoryGui
local inventoryBtn = playerGui.MainGui.Frame.OpenButton
local mainFrame = inventoryGui.Main
local bottomFrame = inventoryGui.Bottom

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
local selectTabColor = Color3.fromRGB(0, 0, 0)
local deselectTabColor = Color3.fromRGB(156, 154, 151)
local selectCardColor = Color3.fromRGB(255, 251, 0)
local deselectCardColor = Color3.fromRGB(119, 121, 128)

-- State
local selectedTab = nil
local selectedFrame = nil
local selectedInfo = nil

local mythlingCards = {}
local mythlingCardsData = {}
local selectedMythlingCard = nil

local resourceCards = {}
local resourceCardsData = {}
local selectedResourceCard = nil

-- helper functions
local function clearCards()
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

local function clearSelectedResourceCard()
	if selectedResourceCard then
		selectedResourceCard.UIStroke.Color = deselectCardColor
		selectedResourceCard.UIStroke.Thickness = 0.02
		selectedResourceCard = nil
	end
end

-- Mythlings
local function setMythlingButtons()
	bottomFrame.FirstButton.Text = "Delete"
	bottomFrame.FirstButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	bottomFrame.FirstButton.Visible = true

	print("mythlingCards:", mythlingCards)
	bottomFrame.FirstButton.Activated:Connect(function()
		if not selectedMythlingCard then
			return
		end
		local id = selectedMythlingCard.Name
		InventoryEvent:FireServer("Delete", id)
		clearMythlingInfo()

		-- get next mythling card in mythlingCards

		-- remove card from UI
		mythlingCards[id]:Destroy()
		mythlingCards[id] = nil
		mythlingCardsData[id] = nil
	end)
end

local function selectCard(card)
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
	mythlingInfo.NameLabel.Text = mythlingCardsData[selectedMythlingCard.Name].displayName
	mythlingInfo.VariantLabel.Text = mythlingCardsData[selectedMythlingCard.Name].rarity
	mythlingInfo.DescriptionLabel.Text = MythlingsData[mythlingCardsData[selectedMythlingCard.Name].typeId].description
end

local function createMythlingCard(mythlingData)
	local newCard = mythlingCardTemplate:Clone()
	newCard.Name = mythlingData.id
	newCard.Parent = mythlingsFrame
	newCard.Visible = true
	newCard.LayoutOrder = 1
	newCard:WaitForChild("2dPreview").Image =
		MythlingsData[mythlingData.typeId].variants[mythlingData.variantId].thumbnail
	newCard.Activated:Connect(function()
		selectCard(newCard)
		showMythlingInfo()
	end)
	return newCard
end

local function addMythlingCard(mythlingData)
	if mythlingCards[mythlingData.id] then
		return
	end
	local newCard = createMythlingCard(mythlingData)
	mythlingCards[mythlingData.id] = newCard
	mythlingCardsData[mythlingData.id] = mythlingData
	if not selectedMythlingCard then
		selectCard(newCard)
		showMythlingInfo()
	end
end

local function addMythlingsCards(list)
	clearCards()
	for _, mythling in pairs(list) do
		addMythlingCard(mythling)
	end
end

local function selectTab(tab)
	if selectedTab == tab then
		return
	end
	if selectedTab then
		selectedTab.ImageColor3 = deselectTabColor
		selectedFrame.Visible = false
		selectedInfo.Visible = false
	end

	if tab == mythlingsTab then
		setMythlingButtons()
		tab.ImageColor3 = selectTabColor
		mythlingsFrame.Visible = true
		mythlingInfo.Visible = true
		selectedTab = tab
		selectedFrame = mythlingsFrame
		selectedInfo = mythlingInfo
	end

	if tab == resourcesTab then
		tab.ImageColor3 = selectTabColor
		resourcesFrame.Visible = true
		resourceInfo.Visible = true
		selectedTab = tab
		selectedFrame = resourcesFrame
		selectedInfo = resourceInfo
	end
end

InventoryEvent.OnClientEvent:Connect(function(event, list)
	if event == "Update" then
		addMythlingsCards(list)
	end
end)

mythlingsTab.Activated:Connect(function()
	selectTab(mythlingsTab)
end)

resourcesTab.Activated:Connect(function()
	selectTab(resourcesTab)
end)

inventoryBtn.Activated:Connect(function()
	if not inventoryGui.Enabled then
		backgroundGui.Enabled = true
		addMythlingsCards(InventoryRequest:InvokeServer("getMythlings"))
		selectTab(mythlingsTab)
		inventoryGui.Enabled = true
	else
		inventoryGui.Enabled = false
		backgroundGui.Enabled = false
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
