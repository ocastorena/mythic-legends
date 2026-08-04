-- StarterPlayer/StarterPlayerScripts/UI/CardListUtil
-- Scrolling grid of selectable cards cloned from a template.
--
-- InventoryController (Mythlings and Materials) and StandController each grew their own
-- copy of this: clone/name/parent the template, keep an id -> card map alongside an
-- id -> data map, track one selection, rebuild from a server list. Only the highlight
-- styling actually differed, so that is a callback rather than baked in.
--
--   local list = CardListUtil.new({
--       template = cardTemplate,
--       parent = scrollFrame,
--       setHighlight = function(card, selected) ... end,
--       decorate = function(card, id, entry) ... end,
--       onSelect = function(id, entry, card) ... end,
--   })
--   list:Replace(serverList)

local ButtonUtil = require(script.Parent.ButtonUtil)

local CardListUtil = {}
CardListUtil.__index = CardListUtil

export type Config = {
	template: GuiObject,
	parent: Instance,
	-- Applies the selected/deselected look. Required: styling is the one thing that
	-- genuinely differs between the GUIs.
	setHighlight: (card: GuiObject, selected: boolean) -> (),
	-- Fills in the card's images and labels for this entry.
	decorate: ((card: GuiObject, id: string, entry: any) -> ())?,
	-- Called after a card becomes selected, including the automatic first selection.
	onSelect: ((id: string, entry: any, card: GuiObject) -> ())?,
	-- Return false to leave an entry out of the list entirely.
	filter: ((id: string, entry: any) -> boolean)?,
	-- Select the first card added when nothing is selected yet. Defaults to true.
	autoSelectFirst: boolean?,
}

function CardListUtil.new(config: Config)
	assert(config.template, "[CardListUtil] template is required")
	assert(config.parent, "[CardListUtil] parent is required")
	assert(config.setHighlight, "[CardListUtil] setHighlight is required")

	return setmetatable({
		_config = config,
		_cards = {} :: { [string]: GuiObject },
		_data = {} :: { [string]: any },
		_selectedId = nil :: string?,
	}, CardListUtil)
end

--- The currently selected card's id, or nil.
function CardListUtil:GetSelectedId(): string?
	return self._selectedId
end

function CardListUtil:GetSelectedCard(): GuiObject?
	return self._selectedId and self._cards[self._selectedId] or nil
end

function CardListUtil:GetData(id: string): any
	return self._data[id]
end

function CardListUtil:GetCard(id: string): GuiObject?
	return self._cards[id]
end

--- Drops the highlight without selecting anything else.
function CardListUtil:ClearSelection()
	local card = self:GetSelectedCard()
	if card then
		self._config.setHighlight(card, false)
	end
	self._selectedId = nil
end

--- Selects by id. Re-selecting the current id is a no-op, so callers can call this
--- freely from click handlers without fighting their own state.
function CardListUtil:Select(id: string)
	if self._selectedId == id then
		return
	end
	local card = self._cards[id]
	if not card then
		return
	end

	self:ClearSelection()
	self._config.setHighlight(card, true)
	self._selectedId = id

	if self._config.onSelect then
		self._config.onSelect(id, self._data[id], card)
	end
end

--- Adds one card. Idempotent by id, and respects the configured filter.
function CardListUtil:Add(id: string, entry: any): GuiObject?
	if self._cards[id] then
		return self._cards[id]
	end
	if self._config.filter and not self._config.filter(id, entry) then
		return nil
	end

	local card = self._config.template:Clone()
	card.Name = id
	card.Visible = true
	card.LayoutOrder = 1
	card.Parent = self._config.parent

	if self._config.decorate then
		self._config.decorate(card, id, entry)
	end

	self._cards[id] = card
	self._data[id] = entry

	ButtonUtil.hookClick(card, function()
		self:Select(id)
	end)

	local autoSelect = self._config.autoSelectFirst
	if autoSelect == nil then
		autoSelect = true
	end
	if autoSelect and not self._selectedId then
		self:Select(id)
	end

	return card
end

--- Removes one card and its data, clearing the selection if it was selected.
function CardListUtil:Remove(id: string)
	if self._selectedId == id then
		self._selectedId = nil
	end
	local card = self._cards[id]
	if card then
		card:Destroy()
	end
	self._cards[id] = nil
	self._data[id] = nil
end

--- Destroys every card. Does not fire onSelect.
function CardListUtil:Clear()
	for _, card in pairs(self._cards) do
		card:Destroy()
	end
	table.clear(self._cards)
	table.clear(self._data)
	self._selectedId = nil
end

--- Rebuilds the whole list from a server-provided table of id -> entry.
function CardListUtil:Replace(list: { [string]: any })
	self:Clear()
	for id, entry in pairs(list or {}) do
		self:Add(id, entry)
	end
end

--- Iterates id -> card, for callers that need to restyle everything.
function CardListUtil:Cards(): { [string]: GuiObject }
	return self._cards
end

return CardListUtil
