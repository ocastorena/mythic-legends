--!strict
-- StarterPlayer/StarterPlayerScripts/UI/Components/Panel/Modal

local Theme = require(script.Parent.Parent.Parent.Theme)
local Controls = require(script.Parent.Controls)
local Primitives = require(script.Parent.Primitives)
local ViewportUtil = require(script.Parent.Parent.Parent.ViewportUtil)

local Modal = {}
local metric = Theme.metric
local radius = Theme.radius
local surfaces = Theme.surface
local em = Theme.em
local newFrame = Primitives.NewFrame
local newLabel = Primitives.NewLabel
local newList = Primitives.NewList
local flexFill = Primitives.FlexFill
local setText = Primitives.SetText
export type ModalConfig = {
	parent: Instance,
	root: number,
	-- Instance name. Worth setting when a panel owns more than one modal, so the tree
	-- reads as LoreModal/ConfirmModal rather than two children both called "Modal".
	name: string?,
	title: string?,
	-- Adds the rarity · source subtitle row.
	subtitle: boolean?,
	-- Adds the italic lore paragraph.
	body: boolean?,
	-- Confirm/cancel buttons along the bottom.
	confirm: string?,
	cancel: string?,
	confirmTint: Color3?,
	accent: Color3?,
}

export type Modal = {
	Root: Frame,
	Card: Frame,
	TitleLabel: TextLabel,
	IconDisc: ImageLabel,
	SubtitleLabel: TextLabel?,
	BodyLabel: TextLabel?,
	CloseButton: TextButton,
	ConfirmButton: TextButton?,
	CancelButton: TextButton?,
	Open: (Modal) -> (),
	Close: (Modal) -> (),
}

--- Lore/confirmation modal: a dedicated scrim over the panel, a near-opaque card with a
--- hairline border, an identity row, and optional lore or confirm buttons. Lore lives
--- here; the item details retain compact gameplay information.
function Modal.CreateModal(config: ModalConfig): Modal
	local root = config.root
	local accent = config.accent or Theme.accent.gold

	local scrim = newFrame(config.name or "Modal", config.parent)
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Visible = false
	scrim.ZIndex = 10
	Theme.Paint(scrim, surfaces.modalScrim)

	-- Swallows clicks so the panel behind the modal cannot be used.
	local blocker = Instance.new("TextButton")
	blocker.Name = "Blocker"
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.BackgroundTransparency = 1
	blocker.Text = ""
	blocker.AutoButtonColor = false
	blocker.Parent = scrim

	local card = newFrame("Card", scrim)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(380, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.ZIndex = 11
	Theme.Paint(card, surfaces.modal)
	Theme.Corner(card, radius.modal)
	Theme.Ring(card, Color3.fromRGB(255, 255, 255), 1).Transparency = 0.91
	Theme.Padding(card, 20, 20, 20, 20)
	local cardLayout = newList(card, Enum.FillDirection.Vertical, 12)
	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	local titleRow = newFrame("TitleRow", card)
	titleRow.Size = UDim2.new(1, 0, 0, metric.closeSize)
	titleRow.LayoutOrder = 1

	local identity = newFrame("Identity", titleRow)
	identity.Size = UDim2.new(1, -40, 1, 0)
	newList(identity, Enum.FillDirection.Horizontal, 9)

	local disc = Instance.new("ImageLabel")
	disc.Name = "IconDisc"
	disc.Size = UDim2.fromOffset(28, 28)
	disc.BackgroundColor3 = accent
	disc.BackgroundTransparency = 0
	disc.BorderSizePixel = 0
	-- Untinted for the same reason as the details pane's element disc.
	disc.ScaleType = Enum.ScaleType.Fit
	disc.LayoutOrder = 1
	disc.Parent = identity
	Theme.Pill(disc)
	Theme.Padding(disc, 6, 6, 6, 6)

	local titleLabel = newLabel("Title", identity)
	titleLabel.Size = UDim2.new(1, -37, 1, 0)
	setText(titleLabel, em.itemName, root)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Text = config.title or ""
	titleLabel.LayoutOrder = 2

	local closeButton = Controls.CloseButton(titleRow)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.fromScale(1, 0.5)

	local subtitleLabel: TextLabel? = nil
	if config.subtitle then
		subtitleLabel = newLabel("Subtitle", card);
		(subtitleLabel :: TextLabel).Size = UDim2.new(1, 0, 0, 16)
		setText(subtitleLabel :: TextLabel, em.sectionLabel, root);
		(subtitleLabel :: TextLabel).TextColor3 = accent;
		(subtitleLabel :: TextLabel).Text = ""
		(subtitleLabel :: TextLabel).LayoutOrder = 2

		local divider = newFrame("Divider", card)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.LayoutOrder = 3
		Theme.Paint(divider, surfaces.divider)
	end

	local bodyLabel: TextLabel? = nil
	if config.body then
		bodyLabel = newLabel("Body", card);
		(bodyLabel :: TextLabel).Size = UDim2.fromScale(1, 0);
		(bodyLabel :: TextLabel).AutomaticSize = Enum.AutomaticSize.Y;
		(bodyLabel :: TextLabel).FontFace =
			Font.fromName("Nunito", Enum.FontWeight.Bold, Enum.FontStyle.Italic)
		setText(bodyLabel :: TextLabel, em.body, root);
		(bodyLabel :: TextLabel).TextColor3 = Theme.textColors.body;
		(bodyLabel :: TextLabel).TextTransparency = 0.15
		(bodyLabel :: TextLabel).TextWrapped = true
		(bodyLabel :: TextLabel).TextYAlignment = Enum.TextYAlignment.Top;
		(bodyLabel :: TextLabel).LineHeight = 1.35
		(bodyLabel :: TextLabel).Text = ""
		(bodyLabel :: TextLabel).LayoutOrder = 4
	end

	local confirmButton: TextButton? = nil
	local cancelButton: TextButton? = nil
	if config.confirm or config.cancel then
		local actions = newFrame("Actions", card)
		actions.Size = UDim2.new(1, 0, 0, metric.buttonHeight)
		actions.LayoutOrder = 5
		local actionLayout = newList(actions, Enum.FillDirection.Horizontal, 8)
		actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center

		if config.cancel then
			cancelButton = Controls.PrimaryButton(actions, config.cancel, root, Theme.accent.gold);
			(cancelButton :: TextButton).Name = "CancelButton"
			(cancelButton :: TextButton).LayoutOrder = 1
			flexFill(cancelButton :: TextButton)
			-- Cancel is the quiet half of the pair: chip fill, plain white label.
			Theme.Paint(cancelButton :: TextButton, surfaces.chipStrong);
			(cancelButton :: TextButton).TextColor3 = Theme.textColors.strong
		end
		if config.confirm then
			confirmButton = Controls.PrimaryButton(
				actions,
				config.confirm,
				root,
				config.confirmTint or Theme.accent.red
			);
			(confirmButton :: TextButton).Name = "ConfirmButton"
			(confirmButton :: TextButton).LayoutOrder = 2
			flexFill(confirmButton :: TextButton)
		end
	end

	local modal: Modal
	modal = {
		Root = scrim,
		Card = card,
		TitleLabel = titleLabel,
		IconDisc = disc,
		SubtitleLabel = subtitleLabel,
		BodyLabel = bodyLabel,
		CloseButton = closeButton,
		ConfirmButton = confirmButton,
		CancelButton = cancelButton,
		Open = function()
			scrim.Visible = true
		end,
		Close = function()
			scrim.Visible = false
		end,
	}

	closeButton.Activated:Connect(function()
		scrim.Visible = false
	end)
	blocker.Activated:Connect(function()
		scrim.Visible = false
	end)

	-- A modal is a sibling of the panel card, not a descendant, so it needs its own pass
	-- when the device root changes.
	ViewportUtil.Observe(scrim, function(viewport)
		Primitives.RescaleText(card, Theme.Root(viewport))
	end)

	return modal
end

return Modal
