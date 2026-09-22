--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Screens/Stand

local Fusion = require(game:GetService("ReplicatedStorage").Packages.Fusion)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Types = require(script.Parent.Parent.Parent.Types)
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Ui = script.Parent.Parent
local ButtonUtil = require(Ui:WaitForChild("ButtonUtil"))
local CardList = require(Ui:WaitForChild("Components"):WaitForChild("CardList"))
local MenuState = require(Ui:WaitForChild("State"):WaitForChild("MenuState"))
local Motion = require(Ui:WaitForChild("Motion"))
local ToastBus = require(Ui:WaitForChild("State"):WaitForChild("ToastBus"))
local Theme = require(Ui:WaitForChild("Theme"))
local Panel = require(Ui:WaitForChild("Components"):WaitForChild("Panel"))
local MythlingsMeta = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Configurations")
		:WaitForChild("Mythlings")
)
local MaterialsMeta = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("Configurations")
		:WaitForChild("Materials")
)

export type Props = {
	localData: Types.LocalDataApi,
	standController: Types.StandControllerApi,
}

local PANEL_NAME = "Stand"

local function Stand(scope: Fusion.Scope<typeof(Fusion)>, props: Props): ScreenGui
	local connections = scope
	-- Storage belongs to the stand and remains accessible independently of its worker.

	local LocalData = props.localData
	local standGui = scope:New("ScreenGui")({
		Name = "StandGui",
		Enabled = false,
		DisplayOrder = Theme.layer.panel,
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
		accent = Theme.accent.gold,
	})
	local standLabel = panel.TitleLabel

	-- The roster column carries a section label, as the shrine panel's does.
	local rosterLabel = Instance.new("TextLabel")
	rosterLabel.Name = "RosterLabel"
	rosterLabel.Size = UDim2.new(1, 0, 0, 18)
	rosterLabel.BackgroundTransparency = 1
	rosterLabel.BorderSizePixel = 0
	rosterLabel.FontFace = Theme.font.extraBold
	rosterLabel:SetAttribute("Em", Theme.em.sectionLabel)
	rosterLabel.TextSize = Theme.Text(Theme.em.sectionLabel, panel.rootScale)
	rosterLabel.TextColor3 = Theme.textColors.strong
	rosterLabel.TextTransparency = 0.4
	rosterLabel.TextXAlignment = Enum.TextXAlignment.Left
	rosterLabel.Text = "Available Mythlings"
	rosterLabel.Parent = panel.Grid

	local rosterHolder = Instance.new("Frame")
	rosterHolder.Name = "MythlingsFrame"
	rosterHolder.Position = UDim2.fromOffset(0, 26)
	rosterHolder.Size = UDim2.new(1, 0, 1, -178)
	rosterHolder.BackgroundTransparency = 1
	rosterHolder.BorderSizePixel = 0
	rosterHolder.Parent = panel.Grid

	local mythlingScrollFrame = Panel.CreateGrid(rosterHolder)
	local mythlingCardTemplate = Panel.CreateCellTemplate({
		parent = mythlingScrollFrame,
		check = true,
		root = panel.rootScale,
	})

	local storage = Instance.new("Frame")
	storage.Name = "StandStorage"
	storage.AnchorPoint = Vector2.new(0, 1)
	storage.Position = UDim2.fromScale(0, 1)
	storage.Size = UDim2.new(1, 0, 0, 142)
	storage.BackgroundTransparency = 1
	storage.Parent = panel.Grid

	local function storageText(name: string, parent: Instance, y: number, height: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, -6, 0, height)
		label.BackgroundTransparency = 1
		label.FontFace = Theme.font.bold
		label:SetAttribute("Em", Theme.em.caption)
		label.TextSize = Theme.Text(Theme.em.caption, panel.rootScale)
		label.TextColor3 = Theme.textColors.strong
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Text = ""
		label.Parent = parent
		return label
	end

	local storageTitle = storageText("StoredMaterials", storage, 0, 20)
	storageTitle.Text = "Stored Materials"
	local materialScroll = Instance.new("ScrollingFrame")
	materialScroll.Name = "StoredMaterialList"
	materialScroll.Position = UDim2.fromOffset(0, 22)
	materialScroll.Size = UDim2.new(1, 0, 0, 42)
	materialScroll.BackgroundTransparency = 1
	materialScroll.BorderSizePixel = 0
	materialScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	materialScroll.CanvasSize = UDim2.new()
	materialScroll.ScrollBarThickness = 3
	materialScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	materialScroll.Parent = storage
	local materialSummary = storageText("Materials", materialScroll, 0, 0)
	materialSummary.AutomaticSize = Enum.AutomaticSize.Y
	materialSummary.TextWrapped = true
	local productionLabel = storageText("ProductionState", storage, 68, 22)
	local storageCollectButton =
		Panel.PrimaryButton(storage, "Collect", panel.rootScale, Theme.accent.green)
	storageCollectButton.Name = "CollectStoredMaterials"
	storageCollectButton.Position = UDim2.fromOffset(0, 98)

	local details = Panel.CreateDetails({
		parent = panel.Details,
		root = panel.rootScale,
		accent = Theme.accent.gold,
		stats = 2,
		progress = true,
		info = true,
		primary = "Collect",
	})
	details.Root.Visible = true

	local collectButton = details.PrimaryButton :: TextButton
	local removeButton =
		Panel.SquareTextButton(details.Footer :: Frame, "−", panel.rootScale, Theme.accent.red)
	removeButton.LayoutOrder = 2

	--------------------------------------------------------------------------------
	-- State
	--------------------------------------------------------------------------------

	local standId: number? = nil
	-- The mythling currently placed on THIS stand, if any. Tracked by id rather than by
	-- Instance so it survives the card list being rebuilt from the server.
	local activeId: string? = nil
	-- Populated below, once the card template and frame are known.
	local mythlingList: CardList.List<SharedTypes.MythlingEntry>

	local productionTween: Tween? = nil
	local progressValue = Instance.new("NumberValue")
	table.insert(scope, progressValue)
	local productionStatus: Types.ProductionStatus? = nil
	local productionUnavailable = false
	local actionPending = false

	--------------------------------------------------------------------------------
	-- Helpers
	--------------------------------------------------------------------------------

	local function canCollect(): boolean
		local status = productionStatus
		return not actionPending
			and not productionUnavailable
			and status ~= nil
			and (status.production > 0 or (status.active and progressValue.Value >= 1))
	end

	local function renderProduction()
		local status = productionStatus
		storageCollectButton.Text = if actionPending
			then "Updating…"
			elseif productionUnavailable then "Retry"
			else "Collect"
		Panel.SetButtonEnabled(
			storageCollectButton,
			not actionPending and (productionUnavailable or canCollect()),
			Theme.accent.green
		)
		if not status then
			storageTitle.Text = "Stored Materials"
			materialSummary.Text = if productionUnavailable
				then "Storage could not be synchronized."
				else "Loading storage…"
			productionLabel.Text = ""
			if details.ProgressLabel then
				details.ProgressLabel.Text = "Unfinished"
			end
			if details.ProgressDetail then
				details.ProgressDetail.Text = "—"
			end
			Panel.SetProgress(details, 0)
			return
		end
		storageTitle.Text = if status.active
			then `{status.production} / {status.capacity} stored Materials`
			else `{status.production} stored Materials`
		if productionUnavailable then
			productionLabel.Text = "Sync unavailable · last confirmed values"
		elseif not status.active then
			productionLabel.Text = "Paused · earned work retained"
		elseif status.production >= status.capacity then
			productionLabel.Text = "Paused · storage full"
		elseif status.rate <= 0 then
			productionLabel.Text = "Paused · no production"
		elseif progressValue.Value >= 1 then
			productionLabel.Text = "Next Material ready (estimate)"
		else
			local seconds = math.ceil((1 - progressValue.Value) * 60 / status.rate)
			productionLabel.Text = `Next Material in about {seconds}s`
		end
		if details.ProgressLabel then
			details.ProgressLabel.Text = "Unfinished"
		end
		if details.ProgressDetail then
			details.ProgressDetail.Text = if status.active
				then `{math.floor(progressValue.Value * 100)}%`
				else "Paused"
		end
		Panel.SetProgress(details, progressValue.Value)
		if activeId and mythlingList and mythlingList:GetSelectedId() == activeId then
			Panel.SetButtonEnabled(collectButton, canCollect(), Theme.accent.green)
		end
	end

	local function applyProductionStatus(status: Types.ProductionStatus)
		if productionTween then
			productionTween:Cancel()
		end
		productionStatus = status
		productionUnavailable = false
		local lines = {}
		for materialId, bucket in pairs(status.materials) do
			local metadata = MaterialsMeta[materialId]
			local name = metadata and metadata.displayName or materialId
			local unfinished = if bucket.progress > 0
				then ` · {math.floor(bucket.progress * 100)}% unfinished`
				else ""
			table.insert(lines, `{name}: {bucket.stored} ready{unfinished}`)
		end
		table.sort(lines)
		materialSummary.Text = if #lines > 0
			then table.concat(lines, "\n")
			else "No stored Materials or unfinished work."
		local elapsed = math.max(workspace:GetServerTimeNow() - status.sampledAt, 0)
		local isWorking = status.active and status.rate > 0 and status.production < status.capacity
		local progress = if isWorking
			then status.progress + elapsed * status.rate / 60
			else status.progress
		progressValue.Value = math.clamp(progress, 0, 1)
		renderProduction()
		local duration = if isWorking then (1 - progressValue.Value) * 60 / status.rate else 0
		if duration > 0 then
			local tween = TweenService:Create(
				progressValue,
				TweenInfo.new(duration, Enum.EasingStyle.Linear),
				{ Value = 1 }
			)
			productionTween = tween
			tween:Play()
		end
	end
	table.insert(
		connections,
		progressValue:GetPropertyChangedSignal("Value"):Connect(renderProduction)
	)

	--- Resets the details column to its empty state.
	local function clearInfo(): ()
		details.NameLabel.Text = "Empty"
		details.Art.Image = ""
		details.RarityLabel.Text = ""
		details.ElementIcon.Image = ""
		details.ElementIcon.BackgroundColor3 = Theme.accent.gold
		for _, stat in ipairs(details.Stats) do
			stat.Value.Text = "—"
			stat.Label.Text = ""
		end
		activeId = nil
	end

	--- Card styling has three states, and "active" outranks "selected": the mythling on this
	--- stand keeps its green ✓ even while another card carries the selection ring.
	local function paintCard(card: GuiObject, selected: boolean)
		local rarity = card:GetAttribute("Rarity")
		Panel.SetCellRing(card, if type(rarity) == "string" then rarity else nil, selected)
		local check = card:FindFirstChild("EquippedCheck")
		if check and check:IsA("GuiObject") then
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

	--- Uses one primary and one secondary button. The primary's verb
	--- depends on what is selected relative to what is stationed.
	local function updateButtons(): ()
		local selectedId = mythlingList:GetSelectedId()

		if selectedId and selectedId == activeId then
			-- Collection remains available separately even when this worker is removed.
			collectButton.Text = "Collect"
			Panel.SetButtonEnabled(collectButton, canCollect(), Theme.accent.green)
			removeButton.Visible = true
		elseif selectedId and activeId then
			-- Another mythling is stationed, so this one has to displace it.
			collectButton.Text = "Swap In"
			Panel.SetButtonEnabled(collectButton, not actionPending, Theme.accent.gold)
			removeButton.Visible = false
		elseif selectedId then
			collectButton.Text = "Station"
			Panel.SetButtonEnabled(collectButton, not actionPending, Theme.accent.gold)
			removeButton.Visible = false
		else
			collectButton.Text = "Collect"
			Panel.SetButtonEnabled(collectButton, false, Theme.accent.green)
			removeButton.Visible = false
		end
		Panel.SetButtonEnabled(removeButton, not actionPending, Theme.accent.red)
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

		local status = productionStatus
		details.Stats[1].Value.Text = if status then `{status.rate}/min` else "—"
		details.Stats[1].Label.Text = "Total Yield"
		details.Stats[2].Value.Text = materialMeta.displayName
		details.Stats[2].Label.Text = "Material"
		details.Stats[2].Value.TextColor3 = tint
	end

	mythlingList = CardList.new({
		template = mythlingCardTemplate,
		parent = mythlingScrollFrame,
		setHighlight = paintCard,
		-- Only mythlings that are unplaced or already on THIS stand belong in the list.
		filter = function(_id: string, data: SharedTypes.MythlingEntry)
			return not data.standId or data.standId == standId
		end,
		decorate = function(card: GuiButton, id: string, data: SharedTypes.MythlingEntry)
			local metadata = MythlingsMeta[data.typeId];
			(card:WaitForChild("2dPreview") :: ImageLabel).Image =
				metadata.variants[data.variantId].thumbnail
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
	local function addMythlingCards(list: { [string]: SharedTypes.MythlingEntry }): ()
		activeId = nil
		mythlingList:Replace(list)
		refreshCards()
	end

	local session = props.standController.BindSession({
		onPending = function(isPending)
			actionPending = isPending
			if isPending and productionTween then
				productionTween:Cancel()
			end
			if not isPending then
				refreshCards()
				showMythlingInfo()
			end
			renderProduction()
			updateButtons()
		end,
		onStatus = function(status)
			if status then
				applyProductionStatus(status)
			else
				productionUnavailable = true
				if productionTween then
					productionTween:Cancel()
				end
				renderProduction()
			end
			showMythlingInfo()
			updateButtons()
		end,
		onAssigned = function(id)
			activeId = id
			if not actionPending then
				refreshCards()
				showMythlingInfo()
				updateButtons()
				renderProduction()
			end
		end,
		onCollection = function(result)
			if result then
				if result.collected > 0 then
					ToastBus.Show(
						`Collected {result.collected} Materials. {result.remaining} remain in storage.`
					)
				elseif result.remaining > 0 then
					ToastBus.Show(
						`No Materials fit in Inventory. {result.remaining} remain in storage.`
					)
				else
					ToastBus.Show("No whole Materials are ready yet. Unfinished work is retained.")
				end
			else
				ToastBus.Show("Collection could not be confirmed. Refreshing storage.")
			end
		end,
	})
	table.insert(scope, session.Destroy)

	local function collectStorage()
		if productionUnavailable then
			session.Refresh()
		elseif standId and canCollect() then
			session.Collect()
		end
	end
	--------------------------------------------------------------------------------
	-- Lore modal
	--------------------------------------------------------------------------------

	local loreModal = Panel.CreateModal({
		parent = standGui,
		root = panel.rootScale,
		name = "LoreModal",
		subtitle = true,
		body = true,
	})

	if details.InfoButton then
		ButtonUtil.HookClick(details.InfoButton, function()
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
				loreModal.SubtitleLabel.Text =
					`{Theme.Tier(metadata.rarity)} · {materialMeta.displayName}`
				loreModal.SubtitleLabel.TextColor3 = Theme.RarityColor(metadata.rarity)
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

	-- The primary button carries whichever verb updateButtons settled on.
	ButtonUtil.HookClick(collectButton, function()
		if actionPending or not standId then
			return
		end
		local selectedId = mythlingList:GetSelectedId()

		if selectedId and selectedId == activeId then
			collectStorage()
			return
		end

		if not selectedId then
			return
		end

		session.Assign(selectedId, activeId)
	end)
	ButtonUtil.HookClick(storageCollectButton, collectStorage)

	-- Square secondary: take the stationed mythling off this stand.
	ButtonUtil.HookClick(removeButton, function()
		if not activeId or not standId or actionPending then
			return
		end
		session.Remove(activeId)
	end)

	-- The replicated private state cache keeps this view current without polling.
	table.insert(
		connections,
		LocalData.OnStateChanged:Connect(function(key, value)
			if not standGui.Enabled then
				return
			end
			if key == "mythlings" then
				addMythlingCards(value or {})
				showMythlingInfo()
				updateButtons()
			end
			if key == "base" or key == "materials" or key == "mythlings" then
				session.Refresh()
			end
		end)
	)

	--------------------------------------------------------------------------------
	-- Controller request -> open Stand GUI
	--------------------------------------------------------------------------------
	table.insert(
		connections,
		props.standController.OnStandRequested:Connect(function(requestedStandId: number)
			actionPending = false
			if standId ~= requestedStandId then
				productionStatus = nil
				progressValue.Value = 0
			end
			productionUnavailable = false
			if productionTween then
				productionTween:Cancel()
			end
			standId = requestedStandId
			standLabel.Text = "Stand #" .. tostring(standId)
			local list = LocalData.Peek("mythlings") or {}

			addMythlingCards(list)
			showMythlingInfo()
			updateButtons()
			renderProduction()

			MenuState.Open(PANEL_NAME)
			session.Open(requestedStandId)
		end)
	)

	Panel.ApplyTextScale(standGui, panel.rootScale, Theme.menuTextScale)

	local menuTransition = Motion.CreateMenuTransition({
		screenGui = standGui,
		motionRoot = panel.MotionRoot,
		panelName = PANEL_NAME,
		onCloseStart = function()
			session.Close()
			loreModal:Close()
		end,
		onClosed = function()
			-- The roster is rebuilt from the server every time a prompt opens the panel, so
			-- dropping it on close keeps a stale stand's cards from flashing up on the next.
			session.Close()
			mythlingList:Clear()
			clearInfo()
			actionPending = false
			if productionTween then
				productionTween:Cancel()
			end
			updateButtons()
		end,
	})
	local unregisterMenu = MenuState.Register(PANEL_NAME, menuTransition)
	table.insert(scope, unregisterMenu)
	table.insert(scope, menuTransition.Destroy)
	table.insert(scope, function()
		if productionTween then
			productionTween:Cancel()
		end
	end)

	return standGui
end

return Stand
