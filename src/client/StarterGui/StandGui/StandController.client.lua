-- StarterGui/StandGui/StandController
--
-- The stand panel is the design's shrine panel: same shell, a roster grid in the 2/3
-- column under a section label, and a details column of hero art, hero stats, a storage
-- bar and a footer.
--
-- The four actions used to be four buttons in a `Bottom` frame outside the card, three of
-- which were always visible and two of which overlapped. §07 allows one wide primary and
-- one square secondary, so they collapse onto the selection instead:
--
--   selected card is on this stand -> primary "Collect" · secondary "−" (remove)
--   selected card is another one    -> primary "Station" or "Swap In"
--
-- Every action the old layout offered is still reachable, and which one applies is now
-- obvious from what is selected.

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

--// Modules
local Util = ReplicatedStorage:WaitForChild("Util")
local ModalUtil = require(Util:WaitForChild("ModalUtil"))
local ButtonUtil = require(Util:WaitForChild("ButtonUtil"))
local CardListUtil = require(Util:WaitForChild("CardListUtil"))
local ThemeUtil = require(Util:WaitForChild("ThemeUtil"))
local PanelUtil = require(Util:WaitForChild("PanelUtil"))
local MythlingsMeta = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Mythlings"))
local ResourcesMeta = require(ReplicatedStorage:WaitForChild("Metadata"):WaitForChild("Resources"))

-- Identifies this panel to ModalUtil, which owns the backdrop and input guard.
local PANEL_NAME = "Stand"

--// Player/UI roots
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local standGui = playerGui:WaitForChild("StandGui")

--------------------------------------------------------------------------------
-- Shell
--------------------------------------------------------------------------------

-- The authored frames predate the design system; the shell replaces them outright.
for _, name in ipairs({ "Main", "Bottom" }) do
	local authored = standGui:FindFirstChild(name)
	if authored then
		authored:Destroy()
	end
end

local panel = PanelUtil.panel({
	parent = standGui,
	title = "Stand",
	accent = ThemeUtil.Accent.gold,
	onClose = function()
		standGui.Enabled = false
	end,
})
local standLabel = panel.TitleLabel

-- The roster column carries a section label, as the shrine panel's does.
local rosterLabel = Instance.new("TextLabel")
rosterLabel.Name = "RosterLabel"
rosterLabel.Size = UDim2.new(1, 0, 0, 18)
rosterLabel.BackgroundTransparency = 1
rosterLabel.BorderSizePixel = 0
rosterLabel.FontFace = ThemeUtil.Font.extraBold
rosterLabel.TextSize = ThemeUtil.text(ThemeUtil.Em.sectionLabel, panel.Root)
rosterLabel.TextColor3 = ThemeUtil.Text.strong
rosterLabel.TextTransparency = 0.4
rosterLabel.TextXAlignment = Enum.TextXAlignment.Left
rosterLabel.Text = "Available Mythlings"
rosterLabel.Parent = panel.Grid

local rosterHolder = Instance.new("Frame")
rosterHolder.Name = "MythlingsFrame"
rosterHolder.Position = UDim2.fromOffset(0, 26)
rosterHolder.Size = UDim2.new(1, 0, 1, -26)
rosterHolder.BackgroundTransparency = 1
rosterHolder.BorderSizePixel = 0
rosterHolder.Parent = panel.Grid

local mythlingScrollFrame = PanelUtil.grid(rosterHolder)
local mythlingCardTemplate = PanelUtil.cellTemplate({
	parent = mythlingScrollFrame,
	check = true,
	root = panel.Root,
})

local details = PanelUtil.details({
	parent = panel.Details,
	root = panel.Root,
	accent = ThemeUtil.Accent.gold,
	stats = 2,
	progress = true,
	info = true,
	primary = "Collect",
})
details.Root.Visible = true

local collectButton = details.PrimaryButton :: TextButton
local removeButton = PanelUtil.squareTextButton(
	details.Footer :: Frame,
	"−",
	panel.Root,
	ThemeUtil.Accent.red
)
removeButton.LayoutOrder = 2

--------------------------------------------------------------------------------
-- Remotes
--------------------------------------------------------------------------------

local MythlingsRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsRequest")
local MythlingsEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MythlingsEvent")
local BaseEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BaseEvent")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local standId: any = nil
-- The mythling currently placed on THIS stand, if any. Tracked by id rather than by
-- Instance so it survives the card list being rebuilt from the server.
local activeId: string? = nil
-- Populated below, once the card template and frame are known.
local mythlingList

local productionTween: Tween = nil
local productionValue: NumberValue = Instance.new("NumberValue")
productionValue.Value = 0
-- Capacity for the bar currently on screen, so the value listener can size the fill.
local productionCapacity = 0
-- Connected once; the old code added a new listener on every tween.
local productionConnected = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Shows how full the stand's storage is, using §06's progress row: label left, figures
--- right, accent fill. Replaces the old "12/300 (+5/min)" text line.
local function renderProduction()
	local stored = math.floor(productionValue.Value)
	if details.ProgressLabel then
		details.ProgressLabel.Text = "Storage"
	end
	if details.ProgressDetail then
		details.ProgressDetail.Text = `{stored} / {productionCapacity}`
	end
	PanelUtil.setProgress(details, productionCapacity > 0 and stored / productionCapacity or 0)
end

local function startProductionTween(production: number, capacity: number, rate: number): ()
	if productionTween then
		productionTween:Cancel()
	end

	productionCapacity = capacity
	-- Reset starting value
	productionValue.Value = production

	-- Compute how long it should take to fill up (in seconds)
	local ratePerSec = rate / 60
	local remaining = math.max(capacity - production, 0)
	local duration = ratePerSec > 0 and remaining / ratePerSec or 0

	renderProduction()

	if not productionConnected then
		productionConnected = true
		productionValue:GetPropertyChangedSignal("Value"):Connect(function()
			renderProduction()
			-- Only the Collect state belongs to production. While another card is selected
			-- the footer is showing Station/Swap In, and repainting it here would recolour
			-- that button green and toggle it on a timer that has nothing to do with it.
			if mythlingList and mythlingList:GetSelectedId() == activeId then
				PanelUtil.setButtonEnabled(collectButton, productionValue.Value >= 1, ThemeUtil.Accent.green)
			end
		end)
	end

	if duration > 0 then
		local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
		productionTween = TweenService:Create(productionValue, tweenInfo, { Value = capacity })
		productionTween:Play()
	end
end

--- Resets the details column to its empty state.
local function clearInfo(): ()
	details.NameLabel.Text = "Empty"
	details.Art.Image = ""
	details.RarityLabel.Text = ""
	details.ElementIcon.Image = ""
	details.ElementIcon.BackgroundColor3 = ThemeUtil.Accent.gold
	for _, stat in ipairs(details.Stats) do
		stat.Value.Text = "—"
		stat.Label.Text = ""
	end
	productionCapacity = 0
	if productionTween then
		productionTween:Cancel()
	end
	productionValue.Value = 0
	renderProduction()
	activeId = nil
end

--- Card styling has three states, and "active" outranks "selected": the mythling on this
--- stand keeps its green ✓ even while another card carries the selection ring.
local function paintCard(card: GuiObject, selected: boolean)
	PanelUtil.setCellRing(card, card:GetAttribute("Rarity"), selected)
	local check = card:FindFirstChild("EquippedCheck")
	if check then
		check.Visible = card.Name == activeId
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

--- Collapses the old four buttons onto §07's primary + secondary pair. The primary's verb
--- depends on what is selected relative to what is stationed.
local function updateButtons(): ()
	local selectedId = mythlingList:GetSelectedId()

	if selectedId and selectedId == activeId then
		-- Looking at the stationed mythling: collect from it, or take it off.
		collectButton.Text = "Collect"
		PanelUtil.setButtonEnabled(collectButton, productionValue.Value >= 1, ThemeUtil.Accent.green)
		removeButton.Visible = true
	elseif selectedId and activeId then
		-- Another mythling is stationed, so this one has to displace it.
		collectButton.Text = "Swap In"
		PanelUtil.setButtonEnabled(collectButton, true, ThemeUtil.Accent.gold)
		removeButton.Visible = false
	elseif selectedId then
		collectButton.Text = "Station"
		PanelUtil.setButtonEnabled(collectButton, true, ThemeUtil.Accent.gold)
		removeButton.Visible = false
	else
		collectButton.Text = "Collect"
		PanelUtil.setButtonEnabled(collectButton, false, ThemeUtil.Accent.green)
		removeButton.Visible = false
	end
end

--- Fills the details column from the mythling on this stand.
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
	local resourceId = metadata.production.resourceId
	local resourceMeta = ResourcesMeta[resourceId]
	local tint = Color3.fromHex(resourceMeta.guiColor)

	details.NameLabel.Text = metadata.displayName
	details.Art.Image = metadata.variants[data.variantId].thumbnail
	PanelUtil.setHeroRarity(details, metadata.rarity)
	details.ElementIcon.Image = resourceMeta.thumbnail
	details.ElementIcon.BackgroundColor3 = tint

	local response = MythlingsRequest:InvokeServer("GetProduction", { mythlingId = id })
	local production = response.production or 0
	local rate = response.rate
	local capacity = response.capacity or 0

	details.Stats[1].Value.Text = `{rate}/min`
	details.Stats[1].Label.Text = "Total Yield"
	details.Stats[2].Value.Text = resourceMeta.displayName
	details.Stats[2].Label.Text = "Resource"
	details.Stats[2].Value.TextColor3 = tint

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
		-- Read back by paintCard, which only receives the card.
		card:SetAttribute("Rarity", metadata.rarity)

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

--------------------------------------------------------------------------------
-- Lore modal (§08)
--------------------------------------------------------------------------------

local loreModal = PanelUtil.modal({
	parent = standGui,
	root = panel.Root,
	name = "LoreModal",
	subtitle = true,
	body = true,
})

if details.InfoButton then
	ButtonUtil.hookClick(details.InfoButton, function()
		local id = activeId
		local data = id and mythlingList:GetData(id)
		if not data then
			return
		end
		local metadata = MythlingsMeta[data.typeId]
		local resourceMeta = ResourcesMeta[metadata.production.resourceId]

		loreModal.TitleLabel.Text = metadata.displayName
		loreModal.IconDisc.Image = metadata.variants[data.variantId].thumbnail
		loreModal.IconDisc.BackgroundColor3 = Color3.fromHex(resourceMeta.guiColor)
		if loreModal.SubtitleLabel then
			loreModal.SubtitleLabel.Text = `{ThemeUtil.tier(metadata.rarity)} · {resourceMeta.displayName}`
			loreModal.SubtitleLabel.TextColor3 = ThemeUtil.rarityColor(metadata.rarity)
		end
		if loreModal.BodyLabel then
			loreModal.BodyLabel.Text = metadata.description
		end
		loreModal:Open()
	end)
end

--------------------------------------------------------------------------------
-- UI lifecycle
--------------------------------------------------------------------------------

-- This ScreenGui's own Enabled property is the open/close contract; ModalUtil handles the
-- backdrop, input guard and backpack. The old version called InputGuardUtil.close() here
-- AND again from the backdrop handler -- one open, two closes.
standGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if standGui.Enabled then
		ModalUtil.Open(PANEL_NAME)
	else
		-- The roster is rebuilt from the server every time a prompt opens the panel, so
		-- dropping it on close keeps a stale stand's cards from flashing up on the next.
		-- The close button used to do this itself and missed every other close path.
		loreModal:Close()
		mythlingList:Clear()
		clearInfo()
		updateButtons()
		ModalUtil.Close(PANEL_NAME)
	end
end)

-- The primary button carries whichever verb updateButtons settled on.
ButtonUtil.hookClick(collectButton, function()
	local selectedId = mythlingList:GetSelectedId()

	if selectedId and selectedId == activeId then
		-- Collect
		if productionValue.Value > 0 then
			MythlingsRequest:InvokeServer("CollectProduction", { mythlingId = activeId })
			showMythlingInfo()
		end
		return
	end

	if not selectedId then
		return
	end

	if activeId then
		-- Swap In: remove the current occupant, then place the selection.
		BaseEvent:FireServer("RemoveMythling", { standId = standId, mythlingId = activeId })
	end
	BaseEvent:FireServer("PlaceMythling", { standId = standId, mythlingId = selectedId })

	activeId = selectedId
	refreshCards()
	updateButtons()
	showMythlingInfo()
end)

-- Square secondary: take the stationed mythling off this stand.
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

--------------------------------------------------------------------------------
-- Proximity prompt -> open Stand GUI
--------------------------------------------------------------------------------
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

	standGui.Enabled = true
end)
