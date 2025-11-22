-- StarterGui/StandGui/StandGui.lua
-- Refactor: readability, consistent naming, comments, Luau-friendly layout.
-- NOTE: Behavior intentionally unchanged.

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

--// Modules
local InputGuard = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("GuiInputGuard"))
local MythlingsData = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))

--// Player/UI roots
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ScreenGui + major frames
local standGui = playerGui:WaitForChild("StandGui")
local mainFrame = standGui:WaitForChild("Main")
local standLabel = mainFrame:WaitForChild("StandLabel")
local closeButton = mainFrame:WaitForChild("CloseButton")
local mythlingsFolder = mainFrame:WaitForChild("Mythlings")

-- Mythling list + template + info panel
local mythlingScrollFrame = mythlingsFolder:WaitForChild("ScrollingFrame")
local mythlingCardTemplate = mythlingScrollFrame:WaitForChild("CardTemplate") :: ImageButton
local mythlingInfoFrame = mythlingsFolder:WaitForChild("Info")

--// Remotes
local MythlingsRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsRequest")
local MythlingsEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsEvent")
local baseEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BaseEvent")
local MythlingsRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsRequest")

--// UI palette (unchanged colors, standardized names)
local COLOR_CARD_DESELECT = Color3.fromRGB(29, 31, 37)
local COLOR_CARD_SELECTED = Color3.fromRGB(0, 255, 127)
local COLOR_CARD_ACTIVE = Color3.fromRGB(255, 212, 121)

--// State
local standId: any = nil
-- Map: mythlingId -> card Instance
local mythlingCards: { [string]: Instance } = {}
-- Map: mythlingId -> MythlingsData table
local mythlingCardData: { [string]: any } = {}
-- Selection state
local selectedCard: ImageButton? = nil
local activeCard: ImageButton? = nil

local productionTween: Tween = nil
local productionValue: NumberValue = Instance.new("NumberValue")
productionValue.Value = 0

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

	-- Don’t tween if full or rate is zero
	if duration <= 0 or ratePerSec <= 0 then
		productionLabel.Text = `{capacity}/{capacity} (+{rate}/min)`
		return
	end

	-- Update text as the tween runs
	productionValue:GetPropertyChangedSignal("Value"):Connect(function()
		productionLabel.Text = `{math.floor(productionValue.Value)}/{capacity} (+{rate}/min)`
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
	mythlingInfoFrame.NameLabel.Text = "None"
	mythlingInfoFrame.VariantLabel.Text = ""
	mythlingInfoFrame.DescriptionLabel.Text = ""
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
local function updateInfoButtons(): ()
	local addBtn = mythlingInfoFrame.AddButton
	local removeBtn = mythlingInfoFrame.RemoveButton
	local switchBtn = mythlingInfoFrame.SwitchButton

	if selectedCard == activeCard then
		removeBtn.Visible = true
		addBtn.Visible = false
		switchBtn.Visible = false
	elseif activeCard and selectedCard ~= activeCard then
		removeBtn.Visible = false
		addBtn.Visible = false
		switchBtn.Visible = true
	elseif selectedCard and not activeCard then
		removeBtn.Visible = false
		addBtn.Visible = true
		switchBtn.Visible = false
	else
		-- No selection: hide all (not strictly needed, but explicit)
		removeBtn.Visible = false
		addBtn.Visible = false
		switchBtn.Visible = false
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

	mythlingInfoFrame.NameLabel.Text = data.displayName
	mythlingInfoFrame.VariantLabel.Text = data.rarity
	mythlingInfoFrame.DescriptionLabel.Text = MythlingsData[data.typeId].description

	local response = MythlingsRequest:InvokeServer("GetProduction", { mythlingId = id })

	local resource = MythlingsData[data.typeId].production.resource
	local production = response.production or 0
	local rate = response.rate or 0
	local capacity = response.capacity or 0
	local color = MythlingsData[data.typeId].production.guiColor
	mythlingInfoFrame.ResourceLabel.Text = resource
	mythlingInfoFrame.ResourceLabel.TextColor3 = Color3.fromHex(color)
	if production > 0 then
		mythlingInfoFrame.CollectButton.Visible = true
	end
	startProductionTween(production, capacity, rate)
end

--- Creates a visual card for a mythling and wires selection behavior.
local function createMythlingCard(data: any): ImageButton
	local newCard = mythlingCardTemplate:Clone()
	newCard.Name = data.id
	newCard.Parent = mythlingScrollFrame
	newCard.Visible = true
	newCard.LayoutOrder = 1

	newCard.NameLabel.Text = data.displayName
	newCard:WaitForChild("2dPreview").Image = MythlingsData[data.typeId].variants[data.variantId].thumbnail

	-- If this mythling is already on this stand, mark it as active (gold).
	if data.standId == standId then
		activeCard = newCard
		if activeCard then
			activeCard.BackgroundColor3 = COLOR_CARD_ACTIVE
		end
	end

	newCard.Activated:Connect(function()
		selectCard(newCard)
		updateInfoButtons()
		-- (No behavior changes)
	end)

	return newCard
end

--- Adds a single mythling card to the list (idempotent by id).
local function addMythlingCard(data: any): ()
	if mythlingCards[data.id] then
		return
	end
	if data.standId > -1 and data.standId ~= standId then
		return
	end
	local card = createMythlingCard(data)
	mythlingCards[data.id] = card
	mythlingCardData[data.id] = data
end

--- Rebuilds the card list from a server-provided array.
local function addMythlingCards(list: { any }): ()
	clearCards()
	for _, mythling in pairs(list) do
		addMythlingCard(mythling)
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

mythlingInfoFrame.CollectButton.Activated:Connect(function()
	if not activeCard then
		return
	end
	if productionValue.Value > 0 then
		MythlingsRequest:InvokeServer("CollectProduction", { mythlingId = activeCard.Name })
		showMythlingInfo()
	end
end)

-- Add button: place selected on this stand
mythlingInfoFrame.AddButton.Activated:Connect(function()
	if not selectedCard then
		return
	end
	local mythlingId = selectedCard.Name
	baseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = mythlingId })
	activeCard = selectedCard
	updateInfoButtons()
	showMythlingInfo()
end)

-- Switch button: remove current, then place selected
mythlingInfoFrame.SwitchButton.Activated:Connect(function()
	if not selectedCard then
		return
	end
	local mythlingId = selectedCard.Name
	baseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = mythlingId })
	baseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = mythlingId })

	if activeCard then
		activeCard.BackgroundColor3 = COLOR_CARD_DESELECT
	end
	activeCard = selectedCard
	if activeCard then
		activeCard.BackgroundColor3 = COLOR_CARD_SELECTED
	end
	updateInfoButtons()
	showMythlingInfo()
end)

-- Remove button: remove the currently active mythling from this stand
mythlingInfoFrame.RemoveButton.Activated:Connect(function()
	if not activeCard then
		return
	end
	local mythlingId = activeCard.Name
	baseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = mythlingId })
	activeCard.BackgroundColor3 = COLOR_CARD_SELECTED
	activeCard = nil
	updateInfoButtons()
	showMythlingInfo()
end)

-- Inventory updates from server
MythlingsEvent.OnClientEvent:Connect(function(ev, list)
	if ev == "Update" then
		addMythlingCards(list)
	end
end)

-- Close button
closeButton.Activated:Connect(function()
	clearCards()
	clearInfo()
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
	local list = MythlingsRequest:InvokeServer("getMythlings")
	InputGuard.open()
	addMythlingCards(list)
	showMythlingInfo()
	standGui.Enabled = true
end)
