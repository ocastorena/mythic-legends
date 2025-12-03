-- StarterGui/StandGui/StandGui.lua

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

--// Modules
local InputGuard = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("GuiInputGuard"))
local ButtonSetup = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("ButtonSetup"))
local MythlingsMeta = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))
local ResourcesMeta = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Resources"))

--// Player/UI roots
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local backgroundGui = playerGui.Background

-- ScreenGui + major frames
local standGui = playerGui:WaitForChild("StandGui")
local mainFrame = standGui:WaitForChild("Main")
local standLabel = mainFrame.Tabs.StandLabel
local closeButton = mainFrame.CloseButton

-- Mythling list + template + info panel
local mythlingScrollFrame = mainFrame.MythlingsFrame
local mythlingCardTemplate = mythlingScrollFrame:WaitForChild("CardTemplate") :: ImageButton
local mythlingInfoFrame = mainFrame:WaitForChild("MythlingInfo")

-- Buttons
local bottomFrame = standGui.Bottom
local removeButton = bottomFrame.FirstButton
local switchButton = bottomFrame.SecondButton
local addButton = bottomFrame.ThirdButton
local collectButton = bottomFrame.FourthButton

--// Remotes
local MythlingsRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsRequest")
local MythlingsEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsEvent")
local BaseEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BaseEvent")

--// UI palette (unchanged colors, standardized names)
local COLOR_CARD_DESELECT = Color3.fromRGB(29, 31, 37)
local COLOR_CARD_SELECTED = Color3.fromRGB(0, 255, 127)
local COLOR_CARD_ACTIVE = Color3.fromRGB(255, 212, 121)

--// State
local standId: any = nil
-- Map: mythlingId -> card Instance
local mythlingCards: { [string]: Instance } = {}
-- Map: mythlingId -> MythlingsMeta table
local mythlingCardData: { [string]: any } = {}
-- Selection state
local selectedCard: ImageButton? = nil
local activeCard: ImageButton? = nil

local productionTween: Tween = nil
local productionValue: NumberValue = Instance.new("NumberValue")
productionValue.Value = 0

-- Preserve original button styling for toggling enabled/disabled visuals.
local buttonDefaults: { [Instance]: { bg: Color3, text: Color3?, auto: boolean? } } = {}

local function setButtonEnabled(button: TextButton, enabled: boolean)
	if not buttonDefaults[button] then
		buttonDefaults[button] = {
			bg = button.BackgroundColor3,
			text = (button :: any).TextColor3,
			auto = (button :: any).AutoButtonColor,
		}
	end

	local defaults = buttonDefaults[button]
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled and defaults.auto or false

	if enabled then
		button.BackgroundColor3 = defaults.bg
		if defaults.text then
			button.TextColor3 = defaults.text
			button.TextTransparency = 0
		end
		button.BackgroundTransparency = 0
	else
		-- Dim colors to look disabled
		button.BackgroundColor3 = defaults.bg:Lerp(Color3.new(0.5, 0.5, 0.5), 0.5)
		if defaults.text then
			button.TextColor3 = defaults.text:Lerp(Color3.new(0.7, 0.7, 0.7), 0.5)
			button.TextTransparency = 0.2
		end
		button.BackgroundTransparency = 0
	end
end

--//////////////////////////////////////////////////////////////////////////////////////////////////
-- Helpers
--//////////////////////////////////////////////////////////////////////////////////////////////////
--
local function startProductionTween(production: number, capacity: number, rate: number): ()
	if productionTween then
		productionTween:Cancel()
	end
	-- update the production value based on the current values
	local productionLabel = mythlingInfoFrame.ProductionLabel

	-- Reset starting value
	productionValue.Value = production

	-- Compute how long it should take to fill up (in seconds)
	local ratePerSec = rate / 60
	local remaining = math.max(capacity - production, 0)
	local duration = remaining / ratePerSec

	print("production:", productionValue.Value)
	productionLabel.Text = `{math.floor(productionValue.Value)}/{capacity} (+{rate}/min)`

	-- Update text as the tween runs
	productionValue:GetPropertyChangedSignal("Value"):Connect(function()
		productionLabel.Text = `{math.floor(productionValue.Value)}/{capacity} (+{rate}/min)`
		if productionValue.Value < 1 then
			setButtonEnabled(collectButton, false)
		else
			setButtonEnabled(collectButton, true)
		end
	end)

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
	productionTween = TweenService:Create(productionValue, tweenInfo, { Value = capacity })
	productionTween:Play()
end

--- Destroys all card instances and clears lookup.
local function clearCards(): ()
	for _, card in pairs(mythlingCards) do
		card:Destroy()
	end
	table.clear(mythlingCards)
end

--- Resets info panel and active selection visuals.
local function clearInfo(): ()
	mythlingInfoFrame.NameLabel.Text = "Empty"
	mythlingInfoFrame.ResourceLabel.Text = ""
	mythlingInfoFrame.ProductionLabel.Text = ""
	activeCard = nil
end

--- Removes highlight from the previously selected card (keeps active highlight if needed).
local function clearSelectedCard(): ()
	if selectedCard then
		if selectedCard == activeCard then
			selectedCard.BackgroundColor3 = COLOR_CARD_ACTIVE
		else
			selectedCard.BackgroundColor3 = COLOR_CARD_DESELECT
			selectedCard = nil
		end
	end
end

--- Updates button visibility on the info panel based on selection/active states.
local function updateButtons(): ()
	-- for add and switch buttons since they overlap
	if selectedCard == activeCard then
		setButtonEnabled(addButton, false)
		addButton.Visible = true
		setButtonEnabled(switchButton, false)
		switchButton.Visible = false
		setButtonEnabled(removeButton, true)
	elseif activeCard and selectedCard ~= activeCard then
		setButtonEnabled(addButton, false)
		addButton.Visible = false
		setButtonEnabled(switchButton, true)
		switchButton.Visible = true
		setButtonEnabled(removeButton, false)
	elseif selectedCard and not activeCard then
		setButtonEnabled(addButton, true)
		addButton.Visible = true
		setButtonEnabled(switchButton, false)
		switchButton.Visible = false
		setButtonEnabled(removeButton, false)
	end
end

--- Applies selected highlight to the given card.
local function selectCard(card: ImageButton): ()
	if selectedCard == card then
		return
	end
	clearSelectedCard()
	card.BackgroundColor3 = COLOR_CARD_SELECTED
	selectedCard = card
end

--- Populates the mythling info panel based on current active card.
local function showMythlingInfo(): ()
	if not activeCard then
		clearInfo()
		return
	end

	local id = activeCard.Name
	local data = mythlingCardData[id]
	if not data then
		return
	end

	local metadata = MythlingsMeta[data.typeId]
	mythlingInfoFrame.NameLabel.Text = metadata.displayName

	local response = MythlingsRequest:InvokeServer("GetProduction", { mythlingId = id })

	local resourceId = metadata.production.resourceId
	local resourceMeta = ResourcesMeta[resourceId]
	local production = response.production or 0
	local rate = response.rate
	local capacity = response.capacity or 0
	mythlingInfoFrame.ResourceLabel.Text = resourceMeta.displayName
	mythlingInfoFrame.ResourceLabel.TextColor3 = Color3.fromHex(resourceMeta.guiColor)

	startProductionTween(production, capacity, rate)
end

--- Creates a visual card for a mythling and wires selection behavior.
local function createMythlingCard(mythlingId, data: any): ImageButton
	local newCard = mythlingCardTemplate:Clone()
	newCard.Name = mythlingId
	newCard.Parent = mythlingScrollFrame
	newCard.Visible = true
	newCard.LayoutOrder = 1

	local metadata = MythlingsMeta[data.typeId]
	newCard:WaitForChild("2dPreview").Image = metadata.variants[data.variantId].thumbnail

	-- If this mythling is already on this stand, mark it as active (gold).
	if data.standId == standId then
		activeCard = newCard
		if activeCard then
			activeCard.BackgroundColor3 = COLOR_CARD_ACTIVE
		end
	end

	ButtonSetup.hookClick(newCard, function()
		selectCard(newCard)
		updateButtons()
	end)

	return newCard
end

--- Adds a single mythling card to the list (idempotent by id).
local function addMythlingCard(mythlingId, data: any): ()
	if mythlingCards[mythlingId] then
		return
	end
	if data.standId and data.standId ~= standId then
		return
	end
	local card = createMythlingCard(mythlingId, data)
	mythlingCards[mythlingId] = card
	mythlingCardData[mythlingId] = data

	if not activeCard then
		selectCard(card)
	end
end

--- Rebuilds the card list from a server-provided array.
local function addMythlingCards(list: { any }): ()
	clearCards()
	for mythlingId, entry in pairs(list) do
		addMythlingCard(mythlingId, entry)
	end
end

--//////////////////////////////////////////////////////////////////////////////////////////////////
-- UI lifecycle
--//////////////////////////////////////////////////////////////////////////////////////////////////

-- When the Stand GUI is toggled on/off
standGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if standGui.Enabled then
		-- Do nothing
	else
		InputGuard.close()
	end
end)

ButtonSetup.hookClick(collectButton, function()
	if not activeCard then
		return
	end
	if productionValue.Value > 0 then
		MythlingsRequest:InvokeServer("CollectProduction", { mythlingId = activeCard.Name })
		showMythlingInfo()
	end
end)

-- Add button: place selected on this stand
ButtonSetup.hookClick(addButton, function()
	if not selectedCard then
		return
	end
	local mythlingId = selectedCard.Name
	BaseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = mythlingId })
	activeCard = selectedCard
	updateButtons()
	showMythlingInfo()
end)

-- Switch button: remove current, then place selected
ButtonSetup.hookClick(switchButton, function()
	if not selectedCard then
		return
	end
	local placeMythlingId = selectedCard.Name
	local removeMythlingId = activeCard and activeCard.Name
	BaseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = removeMythlingId })
	BaseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = placeMythlingId })

	if activeCard then
		activeCard.BackgroundColor3 = COLOR_CARD_DESELECT
	end
	activeCard = selectedCard
	if activeCard then
		activeCard.BackgroundColor3 = COLOR_CARD_SELECTED
	end
	updateButtons()
	showMythlingInfo()
end)

-- Remove button: remove the currently active mythling from this stand
ButtonSetup.hookClick(removeButton, function()
	if not activeCard then
		return
	end
	local mythlingId = activeCard.Name
	BaseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = mythlingId })
	activeCard.BackgroundColor3 = COLOR_CARD_SELECTED
	activeCard = nil
	updateButtons()
	showMythlingInfo()
end)

-- Inventory updates from server
MythlingsEvent.OnClientEvent:Connect(function(ev, list)
	if ev == "Update" then
		addMythlingCards(list)
	end
end)

-- Close button
ButtonSetup.hookClick(closeButton, function()
	clearCards()
	clearInfo()
	backgroundGui.Enabled = false
	standGui.Enabled = false
end)

--//////////////////////////////////////////////////////////////////////////////////////////////////
-- Proximity prompt -> open Stand GUI
-- NOTE: Logic preserved; minimal guard to avoid runtime error if hierarchy differs.
--//////////////////////////////////////////////////////////////////////////////////////////////////
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	-- Original approach: prompt.Parent.Parent:GetAttribute("Id")
	local parent = prompt.Parent
	local grandparent = parent and parent.Parent or nil
	if not (grandparent and grandparent.GetAttribute) then
		return -- keep behavior safe; do not change flow
	end

	standId = grandparent:GetAttribute("Id")
	standLabel.Text = "Stand #" .. tostring(standId)
	local list = MythlingsRequest:InvokeServer("GetMythlings")

	addMythlingCards(list)
	showMythlingInfo()
	updateButtons()

	backgroundGui.Enabled = true
	standGui.Enabled = true
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
