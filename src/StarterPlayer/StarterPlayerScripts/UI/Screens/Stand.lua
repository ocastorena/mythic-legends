-- StarterPlayer/StarterPlayerScripts/UI/Screens/Stand

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local Ui = script.Parent.Parent
local ModalState = require(Ui:WaitForChild("State"):WaitForChild("ModalState"))
local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
local CardList = require(Ui:WaitForChild("Components"):WaitForChild("CardList"))
local Theme = require(Ui:WaitForChild("Theme"))
local Panel = require(Ui:WaitForChild("Components"):WaitForChild("Panel"))
local MythlingsMeta =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configurations"):WaitForChild("Mythlings"))
local MaterialsMeta =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configurations"):WaitForChild("Materials"))

export type Props = {
	localData: Types.LocalDataApi,
	standController: Types.StandControllerApi,
}

local PANEL_NAME = "Stand"

local function Stand(scope: any, props: Props): ScreenGui
	local connections: { RBXScriptConnection } = scope
	local alive = true
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

	local LocalData = props.localData
	local standGui = scope:New("ScreenGui")({
		Name = "StandGui",
		Enabled = false,
		DisplayOrder = Theme.Layer.panel,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
		ClipToDeviceSafeArea = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	--------------------------------------------------------------------------------
	-- Shell
	--------------------------------------------------------------------------------

	local panel = Panel.Create({
		parent = standGui,
		title = "Stand",
		accent = Theme.Accent.gold,
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
	rosterLabel.FontFace = Theme.Font.extraBold
	rosterLabel.TextSize = Theme.text(Theme.Em.sectionLabel, panel.Root)
	rosterLabel.TextColor3 = Theme.Text.strong
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

	local mythlingScrollFrame = Panel.CreateGrid(rosterHolder)
	local mythlingCardTemplate = Panel.CreateCellTemplate({
		parent = mythlingScrollFrame,
		check = true,
		root = panel.Root,
	})

	local details = Panel.CreateDetails({
		parent = panel.Details,
		root = panel.Root,
		accent = Theme.Accent.gold,
		stats = 2,
		progress = true,
		info = true,
		primary = "Collect",
	})
	details.Root.Visible = true

	local collectButton = details.PrimaryButton :: TextButton
	local removeButton = Panel.SquareTextButton(details.Footer :: Frame, "−", panel.Root, Theme.Accent.red)
	removeButton.LayoutOrder = 2

	--------------------------------------------------------------------------------
	-- State
	--------------------------------------------------------------------------------

	local standId: number? = nil
	-- The mythling currently placed on THIS stand, if any. Tracked by id rather than by
	-- Instance so it survives the card list being rebuilt from the server.
	local activeId: string? = nil
	-- Populated below, once the card template and frame are known.
	local mythlingList

	local productionTween: Tween? = nil
	local productionValue: NumberValue = Instance.new("NumberValue")
	productionValue.Value = 0
	table.insert(scope, productionValue)
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
		Panel.SetProgress(details, productionCapacity > 0 and stored / productionCapacity or 0)
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
			table.insert(
				connections,
				productionValue:GetPropertyChangedSignal("Value"):Connect(function()
					renderProduction()
					-- Only the Collect state belongs to production. While another card is selected
					-- the footer is showing Station/Swap In, and repainting it here would recolour
					-- that button green and toggle it on a timer that has nothing to do with it.
					if mythlingList and mythlingList:GetSelectedId() == activeId then
						Panel.SetButtonEnabled(collectButton, productionValue.Value >= 1, Theme.Accent.green)
					end
				end)
			)
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
		details.ElementIcon.BackgroundColor3 = Theme.Accent.gold
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
		Panel.SetCellRing(card, card:GetAttribute("Rarity"), selected)
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
			Panel.SetButtonEnabled(collectButton, productionValue.Value >= 1, Theme.Accent.green)
			removeButton.Visible = true
		elseif selectedId and activeId then
			-- Another mythling is stationed, so this one has to displace it.
			collectButton.Text = "Swap In"
			Panel.SetButtonEnabled(collectButton, true, Theme.Accent.gold)
			removeButton.Visible = false
		elseif selectedId then
			collectButton.Text = "Station"
			Panel.SetButtonEnabled(collectButton, true, Theme.Accent.gold)
			removeButton.Visible = false
		else
			collectButton.Text = "Collect"
			Panel.SetButtonEnabled(collectButton, false, Theme.Accent.green)
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
		local materialId = metadata.production.materialId
		local materialMeta = MaterialsMeta[materialId]
		local tint = Color3.fromHex(materialMeta.guiColor)

		details.NameLabel.Text = metadata.displayName
		details.Art.Image = metadata.variants[data.variantId].thumbnail
		Panel.SetHeroRarity(details, metadata.rarity)
		details.ElementIcon.Image = materialMeta.thumbnail
		details.ElementIcon.BackgroundColor3 = tint

		local status = props.standController.GetProductionStatus(id)
		if not alive or standGui.Parent == nil or activeId ~= id then
			return
		end
		local production = status.production or 0
		local rate = status.rate or 0
		local capacity = status.capacity or 0

		details.Stats[1].Value.Text = `{rate}/min`
		details.Stats[1].Label.Text = "Total Yield"
		details.Stats[2].Value.Text = materialMeta.displayName
		details.Stats[2].Label.Text = "Material"
		details.Stats[2].Value.TextColor3 = tint

		startProductionTween(production, capacity, rate)
	end

	mythlingList = CardList.new({
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

	local loreModal = Panel.CreateModal({
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
			local materialMeta = MaterialsMeta[metadata.production.materialId]

			loreModal.TitleLabel.Text = metadata.displayName
			loreModal.IconDisc.Image = metadata.variants[data.variantId].thumbnail
			loreModal.IconDisc.BackgroundColor3 = Color3.fromHex(materialMeta.guiColor)
			if loreModal.SubtitleLabel then
				loreModal.SubtitleLabel.Text = `{Theme.tier(metadata.rarity)} · {materialMeta.displayName}`
				loreModal.SubtitleLabel.TextColor3 = Theme.rarityColor(metadata.rarity)
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

	-- This ScreenGui's own Enabled property is the open/close contract; ModalState handles the
	-- backdrop, input guard and backpack. The old version called InputGuard.close() here
	-- AND again from the backdrop handler -- one open, two closes.
	table.insert(
		connections,
		standGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if standGui.Enabled then
				ModalState.Open(PANEL_NAME)
			else
				-- The roster is rebuilt from the server every time a prompt opens the panel, so
				-- dropping it on close keeps a stale stand's cards from flashing up on the next.
				-- The close button used to do this itself and missed every other close path.
				loreModal:Close()
				mythlingList:Clear()
				clearInfo()
				updateButtons()
				ModalState.Close(PANEL_NAME)
			end
		end)
	)

	-- The primary button carries whichever verb updateButtons settled on.
	ButtonUtil.hookClick(collectButton, function()
		local selectedId = mythlingList:GetSelectedId()

		if selectedId and selectedId == activeId then
			-- Collect
			if productionValue.Value > 0 then
				if props.standController.Collect(activeId :: string) then
					if alive then
						showMythlingInfo()
					end
				end
			end
			return
		end

		if not selectedId then
			return
		end

		if activeId then
			-- Swap In: remove the current occupant, then place the selection.
			if not props.standController.Remove(standId :: number, activeId) then
				return
			end
			activeId = nil
			if not alive then
				return
			end
		end
		if not props.standController.Place(standId :: number, selectedId) then
			refreshCards()
			updateButtons()
			showMythlingInfo()
			return
		end
		if not alive then
			return
		end

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
		if not props.standController.Remove(standId :: number, activeId) then
			return
		end
		if not alive then
			return
		end
		activeId = nil
		refreshCards()
		updateButtons()
		showMythlingInfo()
	end)

	-- The replicated private state cache keeps this view current without polling.
	table.insert(
		connections,
		LocalData.OnStateChanged:Connect(function(key, value)
			if key == "mythlings" and standGui.Enabled then
				addMythlingCards(value or {})
			end
		end)
	)

	--------------------------------------------------------------------------------
	-- Controller request -> open Stand GUI
	--------------------------------------------------------------------------------
	table.insert(
		connections,
		props.standController.OnStandRequested:Connect(function(requestedStandId: number)
			standId = requestedStandId
			standLabel.Text = "Stand #" .. tostring(standId)
			local list = LocalData.Peek("mythlings") or {}

			addMythlingCards(list)
			showMythlingInfo()
			updateButtons()

			standGui.Enabled = true
		end)
	)
	table.insert(scope, function()
		alive = false
		if productionTween then
			productionTween:Cancel()
		end
		ModalState.Close(PANEL_NAME)
	end)

	return standGui
end

return Stand
