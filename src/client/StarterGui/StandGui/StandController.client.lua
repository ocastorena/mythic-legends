-- StarterGui/StandGui/StandController

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

--// Modules
local InputGuardUtil = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("InputGuardUtil"))
local ButtonUtil = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("ButtonUtil"))
local CardListUtil = require(ReplicatedStorage:WaitForChild("Util"):WaitForChild("CardListUtil"))
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
local COLOR_CARD_SELECTED = Color3.fromRGB(255, 251, 0)
local COLOR_CARD_ACTIVE = Color3.fromRGB(0, 255, 127)

--// State
local standId: any = nil
-- The mythling currently placed on THIS stand, if any. Tracked by id rather than by
-- Instance so it survives the card list being rebuilt from the server.
local activeId: string? = nil
-- Populated below, once the card template and frame are known.
local mythlingList

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

--- Resets info panel and active selection visuals.
local function clearInfo(): ()
	mythlingInfoFrame.NameLabel.Text = "Empty"
	mythlingInfoFrame.ResourceLabel.Text = ""
	mythlingInfoFrame.ProductionLabel.Text = ""
	activeId = nil
end

--- Card colouring has three states, and "active" outranks "selected": the mythling on
--- this stand stays green even while another card is highlighted.
local function paintCard(card: GuiObject, selected: boolean)
	if card.Name == activeId then
		card.BackgroundColor3 = COLOR_CARD_ACTIVE
	elseif selected then
		card.BackgroundColor3 = COLOR_CARD_SELECTED
	else
		card.BackgroundColor3 = COLOR_CARD_DESELECT
	end
end

--- Repaints every card. Needed after activeId changes, since that can restyle two cards
--- at once (the one leaving the stand and the one taking its place).
local function refreshCards(): ()
	local selectedId = mythlingList:GetSelectedId()
	for id, card in pairs(mythlingList:Cards()) do
		paintCard(card, id == selectedId)
	end
end

--- Updates button visibility on the info panel based on selection/active states.
local function updateButtons(): ()
	local selectedId = mythlingList:GetSelectedId()
	-- for add and switch buttons since they overlap
	if selectedId == activeId then
		setButtonEnabled(addButton, false)
		addButton.Visible = true
		setButtonEnabled(switchButton, false)
		switchButton.Visible = false
		setButtonEnabled(removeButton, true)
	elseif activeId and selectedId ~= activeId then
		setButtonEnabled(addButton, false)
		addButton.Visible = false
		setButtonEnabled(switchButton, true)
		switchButton.Visible = true
		setButtonEnabled(removeButton, false)
	elseif selectedId and not activeId then
		setButtonEnabled(addButton, true)
		addButton.Visible = true
		setButtonEnabled(switchButton, false)
		switchButton.Visible = false
		setButtonEnabled(removeButton, false)
	end
end

--- Populates the mythling info panel based on the mythling on this stand.
local function showMythlingInfo(): ()
	if not activeId then
		clearInfo()
		return
	end

	local id = activeId
	local data = mythlingList:GetData(id)
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

mythlingList = CardListUtil.new({
	template = mythlingCardTemplate,
	parent = mythlingScrollFrame,
	setHighlight = paintCard,
	-- Only mythlings that are unplaced or already on THIS stand belong in the list.
	filter = function(_id, data)
		return not data.standId or data.standId == standId
	end,
	decorate = function(card, id, data)
		local metadata = MythlingsMeta[data.typeId]
		card:WaitForChild("2dPreview").Image = metadata.variants[data.variantId].thumbnail

		-- If this mythling is already on this stand, it is the active one.
		if data.standId == standId then
			activeId = id
		end
	end,
	onSelect = function()
		updateButtons()
	end,
})

--- Rebuilds the card list from a server-provided table.
local function addMythlingCards(list: { any }): ()
	activeId = nil
	mythlingList:Replace(list)
	refreshCards()
end

--//////////////////////////////////////////////////////////////////////////////////////////////////
-- UI lifecycle
--//////////////////////////////////////////////////////////////////////////////////////////////////

-- When the Stand GUI is toggled on/off
standGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if standGui.Enabled then
		-- Do nothing
	else
		InputGuardUtil.close()
	end
end)

ButtonUtil.hookClick(collectButton, function()
	if not activeId then
		return
	end
	if productionValue.Value > 0 then
		MythlingsRequest:InvokeServer("CollectProduction", { mythlingId = activeId })
		showMythlingInfo()
	end
end)

-- Add button: place selected on this stand
ButtonUtil.hookClick(addButton, function()
	local selectedId = mythlingList:GetSelectedId()
	if not selectedId then
		return
	end
	BaseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = selectedId })
	activeId = selectedId
	refreshCards()
	updateButtons()
	showMythlingInfo()
end)

-- Switch button: remove current, then place selected
ButtonUtil.hookClick(switchButton, function()
	local placeMythlingId = mythlingList:GetSelectedId()
	if not placeMythlingId then
		return
	end
	local removeMythlingId = activeId
	BaseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = removeMythlingId })
	BaseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = placeMythlingId })

	activeId = placeMythlingId
	refreshCards()
	updateButtons()
	showMythlingInfo()
end)

-- Remove button: remove the currently active mythling from this stand
ButtonUtil.hookClick(removeButton, function()
	if not activeId then
		return
	end
	BaseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = activeId })
	activeId = nil
	refreshCards()
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
ButtonUtil.hookClick(closeButton, function()
	mythlingList:Clear()
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
		InputGuardUtil.open()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	else
		-- ScreenGui just got disabled → allow inputs
		InputGuardUtil.close()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end
end)
